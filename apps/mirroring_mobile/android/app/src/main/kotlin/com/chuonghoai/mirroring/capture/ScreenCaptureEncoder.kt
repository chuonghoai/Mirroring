package com.chuonghoai.mirroring.capture

import android.content.Context
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.util.Log
import android.view.Display
import android.view.Surface
import android.view.WindowManager
import com.chuonghoai.mirroring.stream.H264StreamServer
import java.util.concurrent.atomic.AtomicBoolean

class ScreenCaptureEncoder(
    private val context: Context,
    private val mediaProjection: MediaProjection,
    private val maxDimension: Int = 1280,
    private val targetFps: Int = 30,
    private val bitrate: Int = 4_000_000,
    private val listener: Listener,
) {
    interface Listener {
        fun onVideoFrame(
            frameType: Int,
            rotationQuarterTurns: Int,
            width: Int,
            height: Int,
            timestampUs: Long,
            payload: ByteArray,
        )

        fun onStreamDimensionsChanged(width: Int, height: Int, rotationQuarterTurns: Int)
        fun onProjectionStopped()
        fun onCaptureError(message: String)
    }

    companion object {
        private const val TAG = "ScreenCaptureEncoder"
        private const val MIME_AVC = MediaFormat.MIMETYPE_VIDEO_AVC
    }

    private val running = AtomicBoolean(false)
    private val reconfiguring = AtomicBoolean(false)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val codecLock = Any()

    private var mediaCodec: MediaCodec? = null
    private var inputSurface: Surface? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var drainThread: Thread? = null

    @Volatile
    private var currentWidth: Int = 720
    @Volatile
    private var currentHeight: Int = 1280
    @Volatile
    private var currentRotation: Int = 0
    @Volatile
    private var currentDpi: Int = 320
    @Volatile
    private var cachedConfigBytes: ByteArray? = null

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            Log.i(TAG, "MediaProjection stopped by system/user")
            stop()
            listener.onProjectionStopped()
        }
    }

    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) {}
        override fun onDisplayRemoved(displayId: Int) {}
        override fun onDisplayChanged(displayId: Int) {
            if (displayId != Display.DEFAULT_DISPLAY || !running.get()) return
            val metrics = readScaledDisplayMetrics()
            if (metrics.width != currentWidth ||
                metrics.height != currentHeight ||
                metrics.rotation != currentRotation
            ) {
                Log.i(
                    TAG,
                    "Display changed: ${currentWidth}x$currentHeight (rot=$currentRotation) -> ${metrics.width}x${metrics.height} (rot=${metrics.rotation})",
                )
                reconfigureCapture(metrics)
            }
        }
    }

    private data class CaptureMetrics(
        val width: Int,
        val height: Int,
        val dpi: Int,
        val rotation: Int,
    )

    fun start(): CaptureMetricsSnapshot {
        if (!running.compareAndSet(false, true)) {
            return CaptureMetricsSnapshot(currentWidth, currentHeight, currentRotation)
        }

        val initial = readScaledDisplayMetrics()
        currentWidth = initial.width
        currentHeight = initial.height
        currentDpi = initial.dpi
        currentRotation = initial.rotation

        mediaProjection.registerCallback(projectionCallback, mainHandler)
        val dm = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        dm.registerDisplayListener(displayListener, mainHandler)

        try {
            synchronized(codecLock) {
                createAndStartCodecLocked(currentWidth, currentHeight)
                virtualDisplay = mediaProjection.createVirtualDisplay(
                    "MirroringScreenCapture",
                    currentWidth,
                    currentHeight,
                    currentDpi,
                    DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                    inputSurface,
                    null,
                    mainHandler,
                )
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to start ScreenCaptureEncoder: ${t.message}", t)
            stop()
            throw t
        }

        drainThread = Thread({ drainLoop() }, "MirroringMediaCodecDrain").apply {
            isDaemon = true
            start()
        }

        return CaptureMetricsSnapshot(currentWidth, currentHeight, currentRotation)
    }

    data class CaptureMetricsSnapshot(
        val width: Int,
        val height: Int,
        val rotation: Int,
    )

    fun requestKeyFrame() {
        synchronized(codecLock) {
            try {
                val bundle = Bundle().apply {
                    putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0)
                }
                mediaCodec?.setParameters(bundle)
            } catch (_: Throwable) {
            }
        }
    }

    fun stop() {
        if (!running.compareAndSet(true, false)) return

        try {
            val dm = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
            dm.unregisterDisplayListener(displayListener)
        } catch (_: Throwable) {
        }

        try {
            mediaProjection.unregisterCallback(projectionCallback)
        } catch (_: Throwable) {
        }

        drainThread?.interrupt()
        drainThread = null

        synchronized(codecLock) {
            releaseCodecLocked()
            try {
                virtualDisplay?.release()
            } catch (_: Throwable) {
            }
            virtualDisplay = null
        }

        try {
            mediaProjection.stop()
        } catch (_: Throwable) {
        }
    }

    private fun reconfigureCapture(metrics: CaptureMetrics) {
        if (!running.get() || !reconfiguring.compareAndSet(false, true)) return
        Thread({
            try {
                synchronized(codecLock) {
                    if (!running.get()) return@synchronized
                    releaseCodecLocked()
                    currentWidth = metrics.width
                    currentHeight = metrics.height
                    currentDpi = metrics.dpi
                    currentRotation = metrics.rotation
                    cachedConfigBytes = null

                    createAndStartCodecLocked(currentWidth, currentHeight)
                    virtualDisplay?.resize(currentWidth, currentHeight, currentDpi)
                    virtualDisplay?.surface = inputSurface
                }
                listener.onStreamDimensionsChanged(currentWidth, currentHeight, currentRotation)
            } catch (t: Throwable) {
                Log.e(TAG, "Reconfigure error: ${t.message}", t)
                listener.onCaptureError("Không thể cập nhật độ phân giải xoay màn hình: ${t.message}")
            } finally {
                reconfiguring.set(false)
            }
        }, "MirroringReconfigure").apply {
            isDaemon = true
            start()
        }
    }

    private fun createAndStartCodecLocked(width: Int, height: Int) {
        val format = MediaFormat.createVideoFormat(MIME_AVC, width, height).apply {
            setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface,
            )
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, targetFps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            setLong(MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER, 100_000L)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                setInteger(MediaFormat.KEY_MAX_B_FRAMES, 0)
            }
            // Prefer Baseline profile so there is zero B-frame reordering latency
            setInteger(
                MediaFormat.KEY_PROFILE,
                MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline,
            )
            setInteger(
                MediaFormat.KEY_LEVEL,
                MediaCodecInfo.CodecProfileLevel.AVCLevel4,
            )
        }

        val codec = MediaCodec.createEncoderByType(MIME_AVC)
        try {
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        } catch (_: Throwable) {
            // Fallback without explicit profile/level if device encoder rejects Baseline+Level4
            val fallback = MediaFormat.createVideoFormat(MIME_AVC, width, height).apply {
                setInteger(
                    MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface,
                )
                setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
                setInteger(MediaFormat.KEY_FRAME_RATE, targetFps)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
                setLong(MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER, 100_000L)
            }
            codec.configure(fallback, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        }

        inputSurface = codec.createInputSurface()
        codec.start()
        mediaCodec = codec
    }

    private fun releaseCodecLocked() {
        try {
            mediaCodec?.stop()
        } catch (_: Throwable) {
        }
        try {
            mediaCodec?.release()
        } catch (_: Throwable) {
        }
        mediaCodec = null
        try {
            inputSurface?.release()
        } catch (_: Throwable) {
        }
        inputSurface = null
    }

    private fun drainLoop() {
        val info = MediaCodec.BufferInfo()
        while (running.get()) {
            if (reconfiguring.get()) {
                try {
                    Thread.sleep(15)
                } catch (_: InterruptedException) {
                    break
                }
                continue
            }

            val codec = synchronized(codecLock) { mediaCodec }
            if (codec == null) {
                try {
                    Thread.sleep(15)
                } catch (_: InterruptedException) {
                    break
                }
                continue
            }

            try {
                val outIndex = codec.dequeueOutputBuffer(info, 25_000L)
                when {
                    outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val newFormat = codec.outputFormat
                        val sps = newFormat.getByteBuffer("csd-0")
                        val pps = newFormat.getByteBuffer("csd-1")
                        if (sps != null) {
                            val spsBytes = ByteArray(sps.remaining()).also { sps.duplicate().get(it) }
                            val ppsBytes = if (pps != null) {
                                ByteArray(pps.remaining()).also { pps.duplicate().get(it) }
                            } else {
                                ByteArray(0)
                            }
                            val combined = spsBytes + ppsBytes
                            if (combined.isNotEmpty()) {
                                cachedConfigBytes = combined
                                listener.onVideoFrame(
                                    frameType = H264StreamServer.FRAME_TYPE_CONFIG,
                                    rotationQuarterTurns = currentRotation,
                                    width = currentWidth,
                                    height = currentHeight,
                                    timestampUs = System.nanoTime() / 1000L,
                                    payload = combined,
                                )
                            }
                        }
                    }

                    outIndex >= 0 -> {
                        val outBuf = codec.getOutputBuffer(outIndex)
                        if (outBuf != null && info.size > 0) {
                            outBuf.position(info.offset)
                            outBuf.limit(info.offset + info.size)
                            val data = ByteArray(info.size)
                            outBuf.get(data)

                            val isConfig = (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0
                            val isKey = (info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME) != 0

                            if (isConfig) {
                                cachedConfigBytes = data
                                listener.onVideoFrame(
                                    frameType = H264StreamServer.FRAME_TYPE_CONFIG,
                                    rotationQuarterTurns = currentRotation,
                                    width = currentWidth,
                                    height = currentHeight,
                                    timestampUs = info.presentationTimeUs,
                                    payload = data,
                                )
                            } else if (isKey) {
                                val cfg = cachedConfigBytes
                                val framePayload = if (cfg != null && !startsWithSps(data)) {
                                    cfg + data
                                } else {
                                    data
                                }
                                listener.onVideoFrame(
                                    frameType = H264StreamServer.FRAME_TYPE_KEY,
                                    rotationQuarterTurns = currentRotation,
                                    width = currentWidth,
                                    height = currentHeight,
                                    timestampUs = info.presentationTimeUs,
                                    payload = framePayload,
                                )
                            } else {
                                listener.onVideoFrame(
                                    frameType = H264StreamServer.FRAME_TYPE_DELTA,
                                    rotationQuarterTurns = currentRotation,
                                    width = currentWidth,
                                    height = currentHeight,
                                    timestampUs = info.presentationTimeUs,
                                    payload = data,
                                )
                            }
                        }
                        codec.releaseOutputBuffer(outIndex, false)
                    }
                }
            } catch (t: Throwable) {
                if (running.get() && !reconfiguring.get()) {
                    Log.w(TAG, "Codec drain exception: ${t.message}")
                    try {
                        Thread.sleep(20)
                    } catch (_: InterruptedException) {
                        break
                    }
                }
            }
        }
    }

    private fun startsWithSps(data: ByteArray): Boolean {
        if (data.size < 5) return false
        return data[0] == 0.toByte() &&
            data[1] == 0.toByte() &&
            data[2] == 0.toByte() &&
            data[3] == 1.toByte() &&
            (data[4].toInt() and 0x1F) == 7
    }

    @Suppress("DEPRECATION")
    private fun readScaledDisplayMetrics(): CaptureMetrics {
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val rawWidth: Int
        val rawHeight: Int
        val dpi: Int = context.resources.displayMetrics.densityDpi.coerceAtLeast(160)
        val rotation: Int

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = wm.maximumWindowMetrics.bounds
            rawWidth = bounds.width().coerceAtLeast(320)
            rawHeight = bounds.height().coerceAtLeast(320)
            val dm = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
            rotation = dm.getDisplay(Display.DEFAULT_DISPLAY)?.rotation ?: Surface.ROTATION_0
        } else {
            val dmMetrics = DisplayMetrics()
            val display = wm.defaultDisplay
            display.getRealMetrics(dmMetrics)
            rawWidth = dmMetrics.widthPixels.coerceAtLeast(320)
            rawHeight = dmMetrics.heightPixels.coerceAtLeast(320)
            rotation = display.rotation
        }

        val maxSide = maxOf(rawWidth, rawHeight)
        val scale = if (maxSide > maxDimension) maxDimension.toDouble() / maxSide.toDouble() else 1.0
        val scaledW = roundToMultipleOf16((rawWidth * scale).toInt())
        val scaledH = roundToMultipleOf16((rawHeight * scale).toInt())

        return CaptureMetrics(
            width = scaledW.coerceAtLeast(320),
            height = scaledH.coerceAtLeast(320),
            dpi = dpi,
            rotation = rotation and 0x03,
        )
    }

    private fun roundToMultipleOf16(value: Int): Int {
        val rounded = ((value + 8) / 16) * 16
        return rounded.coerceAtLeast(16)
    }
}
