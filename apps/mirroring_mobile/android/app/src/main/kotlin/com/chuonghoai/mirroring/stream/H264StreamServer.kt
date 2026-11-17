package com.chuonghoai.mirroring.stream

import android.util.Log
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.concurrent.LinkedBlockingDeque
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class H264StreamServer(
    private val preferredPort: Int = 45456,
    private val sessionTokenProvider: () -> String?,
    private val onClientAuthenticated: () -> Unit,
    private val onClientStreamLost: (String) -> Unit,
) {
    companion object {
        private const val TAG = "H264StreamServer"
        private const val STREAM_MAGIC = 0x4D525631 // 'MRV1'
        private const val HEADER_SIZE = 24
        private const val MAX_QUEUED_FRAMES = 12

        const val FRAME_TYPE_CONFIG = 0
        const val FRAME_TYPE_KEY = 1
        const val FRAME_TYPE_DELTA = 2
        const val FRAME_TYPE_METADATA = 3
    }

    private data class OutboundPacket(
        val frameType: Int,
        val encodedBytes: ByteArray,
    )

    private data class CachedConfig(
        val width: Int,
        val height: Int,
        val rotation: Int,
        val payload: ByteArray,
    )

    private val running = AtomicBoolean(false)
    private var serverSocket: ServerSocket? = null
    private var acceptThread: Thread? = null
    private var senderThread: Thread? = null

    private val sendQueue = LinkedBlockingDeque<OutboundPacket>(MAX_QUEUED_FRAMES)
    private val clientLock = Any()
    @Volatile
    private var clientSocket: Socket? = null
    @Volatile
    private var clientOutput: OutputStream? = null

    @Volatile
    var listeningPort: Int = 0
        private set

    @Volatile
    private var lastConfigFrame: CachedConfig? = null

    fun start(): Int {
        if (running.get()) return listeningPort
        val ss = try {
            ServerSocket().apply {
                reuseAddress = true
                bind(InetSocketAddress(preferredPort))
            }
        } catch (_: Throwable) {
            ServerSocket().apply {
                reuseAddress = true
                bind(InetSocketAddress(0))
            }
        }
        serverSocket = ss
        listeningPort = ss.localPort
        running.set(true)

        acceptThread = Thread({ acceptLoop() }, "MirroringStreamAccept").apply {
            isDaemon = true
            start()
        }
        senderThread = Thread({ senderLoop() }, "MirroringStreamSender").apply {
            isDaemon = true
            start()
        }
        Log.i(TAG, "H264StreamServer listening on port $listeningPort")
        return listeningPort
    }

    fun stop() {
        if (!running.compareAndSet(true, false)) return
        listeningPort = 0
        lastConfigFrame = null
        sendQueue.clear()
        closeActiveClient()
        try {
            serverSocket?.close()
        } catch (_: Throwable) {
        }
        serverSocket = null
        acceptThread?.interrupt()
        senderThread?.interrupt()
        acceptThread = null
        senderThread = null
    }

    fun closeActiveClient() {
        synchronized(clientLock) {
            try {
                clientSocket?.close()
            } catch (_: Throwable) {
            }
            clientSocket = null
            clientOutput = null
        }
        sendQueue.clear()
    }

    fun sendFrame(
        frameType: Int,
        rotationQuarterTurns: Int,
        width: Int,
        height: Int,
        timestampUs: Long,
        payload: ByteArray,
    ) {
        if (frameType == FRAME_TYPE_CONFIG) {
            lastConfigFrame = CachedConfig(width, height, rotationQuarterTurns, payload.copyOf())
        }
        if (clientOutput == null) return

        val packetBytes = ByteBuffer.allocate(HEADER_SIZE + payload.size)
            .order(ByteOrder.BIG_ENDIAN)
            .apply {
                putInt(STREAM_MAGIC)
                put(frameType.toByte())
                put((rotationQuarterTurns and 0x03).toByte())
                putShort(width.toShort())
                putShort(height.toShort())
                putShort(0)
                putLong(timestampUs)
                putInt(payload.size)
                put(payload)
            }.array()

        val packet = OutboundPacket(frameType, packetBytes)
        if (!sendQueue.offerLast(packet)) {
            if (frameType == FRAME_TYPE_CONFIG || frameType == FRAME_TYPE_KEY) {
                // Make space by dropping older queued delta frames so keyframe/config go through.
                sendQueue.removeIf { it.frameType == FRAME_TYPE_DELTA }
                if (!sendQueue.offerLast(packet)) {
                    sendQueue.pollFirst()
                    sendQueue.offerLast(packet)
                }
            }
            // If queue is full on a delta frame, skip enqueueing to avoid unbounded latency buildup.
        }
    }

    private fun senderLoop() {
        while (running.get()) {
            try {
                val packet = sendQueue.pollFirst(200, TimeUnit.MILLISECONDS) ?: continue
                val out = synchronized(clientLock) { clientOutput } ?: continue
                out.write(packet.encodedBytes)
                // Only flush when the queue is drained so burst frames coalesce cleanly.
                if (sendQueue.isEmpty()) {
                    out.flush()
                }
            } catch (_: InterruptedException) {
                if (!running.get()) break
            } catch (t: Throwable) {
                if (running.get() && clientOutput != null) {
                    Log.w(TAG, "Stream write failed: ${t.message}")
                    closeActiveClient()
                    onClientStreamLost(t.message ?: "Stream write error")
                }
            }
        }
    }

    private fun acceptLoop() {
        while (running.get()) {
            val ss = serverSocket ?: break
            try {
                val socket = ss.accept()
                socket.tcpNoDelay = true
                socket.sendBufferSize = 512 * 1024
                Thread({ handleClientConnection(socket) }, "MirroringStreamAuth").apply {
                    isDaemon = true
                    start()
                }
            } catch (t: Throwable) {
                if (running.get()) {
                    Log.w(TAG, "Stream accept error: ${t.message}")
                }
            }
        }
    }

    private fun handleClientConnection(socket: Socket) {
        try {
            socket.soTimeout = 4000
            val input = BufferedInputStream(socket.getInputStream())
            val line = readLineLimited(input, 1024)
            val expectedToken = sessionTokenProvider()

            val providedToken = try {
                if (line != null) JSONObject(line).optString("sessionToken", "") else ""
            } catch (_: Throwable) {
                ""
            }

            if (expectedToken.isNullOrBlank() ||
                providedToken.isBlank() ||
                !MessageDigest.isEqual(
                    expectedToken.toByteArray(Charsets.UTF_8),
                    providedToken.toByteArray(Charsets.UTF_8),
                )
            ) {
                Log.w(TAG, "Rejected unauthorized stream client from ${socket.inetAddress?.hostAddress}")
                try {
                    socket.getOutputStream().write("{\"accepted\":false}\n".toByteArray(Charsets.UTF_8))
                } catch (_: Throwable) {
                }
                socket.close()
                return
            }

            socket.soTimeout = 0
            val rawOut = socket.getOutputStream()
            rawOut.write("{\"accepted\":true}\n".toByteArray(Charsets.UTF_8))
            rawOut.flush()

            synchronized(clientLock) {
                try {
                    clientSocket?.close()
                } catch (_: Throwable) {
                }
                sendQueue.clear()
                clientSocket = socket
                clientOutput = rawOut
            }

            Log.i(TAG, "Authenticated stream client connected from ${socket.inetAddress?.hostAddress}")

            lastConfigFrame?.let { cfg ->
                sendFrame(
                    frameType = FRAME_TYPE_CONFIG,
                    rotationQuarterTurns = cfg.rotation,
                    width = cfg.width,
                    height = cfg.height,
                    timestampUs = System.nanoTime() / 1000L,
                    payload = cfg.payload,
                )
            }
            onClientAuthenticated()
        } catch (t: Throwable) {
            Log.w(TAG, "Stream handshake failed: ${t.message}")
            try {
                socket.close()
            } catch (_: Throwable) {
            }
        }
    }

    private fun readLineLimited(input: BufferedInputStream, maxBytes: Int): String? {
        val buf = ByteArrayOutputStream()
        while (buf.size() < maxBytes) {
            val b = input.read()
            if (b == -1) return null
            if (b == '\n'.code) {
                return String(buf.toByteArray(), Charsets.UTF_8).trim()
            }
            if (b != '\r'.code) {
                buf.write(b)
            }
        }
        return null
    }
}
