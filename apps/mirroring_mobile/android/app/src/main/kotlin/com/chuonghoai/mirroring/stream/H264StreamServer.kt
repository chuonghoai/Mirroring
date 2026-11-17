package com.chuonghoai.mirroring.stream

import android.util.Log
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.ByteArrayOutputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
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

        const val FRAME_TYPE_CONFIG = 0
        const val FRAME_TYPE_KEY = 1
        const val FRAME_TYPE_DELTA = 2
        const val FRAME_TYPE_METADATA = 3
    }

    private val running = AtomicBoolean(false)
    private var serverSocket: ServerSocket? = null
    private var acceptThread: Thread? = null

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

    private data class CachedConfig(
        val width: Int,
        val height: Int,
        val rotation: Int,
        val payload: ByteArray,
    )

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
        Log.i(TAG, "H264StreamServer listening on port $listeningPort")
        return listeningPort
    }

    fun stop() {
        if (!running.compareAndSet(true, false)) return
        listeningPort = 0
        lastConfigFrame = null
        closeActiveClient()
        try {
            serverSocket?.close()
        } catch (_: Throwable) {
        }
        serverSocket = null
        acceptThread?.interrupt()
        acceptThread = null
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

        val out = synchronized(clientLock) { clientOutput } ?: return
        try {
            val header = ByteBuffer.allocate(HEADER_SIZE).order(ByteOrder.BIG_ENDIAN).apply {
                putInt(STREAM_MAGIC)
                put(frameType.toByte())
                put((rotationQuarterTurns and 0x03).toByte())
                putShort(width.toShort())
                putShort(height.toShort())
                putShort(0)
                putLong(timestampUs)
                putInt(payload.size)
            }.array()

            synchronized(clientLock) {
                val activeOut = clientOutput ?: return
                activeOut.write(header)
                activeOut.write(payload)
                activeOut.flush()
            }
        } catch (t: Throwable) {
            Log.w(TAG, "Stream write failed: ${t.message}")
            closeActiveClient()
            onClientStreamLost(t.message ?: "Stream write error")
        }
    }

    private fun acceptLoop() {
        while (running.get()) {
            val ss = serverSocket ?: break
            try {
                val socket = ss.accept()
                socket.tcpNoDelay = true
                socket.sendBufferSize = 256 * 1024
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
            val out = BufferedOutputStream(socket.getOutputStream(), 65536)
            out.write("{\"accepted\":true}\n".toByteArray(Charsets.UTF_8))
            out.flush()

            synchronized(clientLock) {
                // Replace any stale stream socket
                try {
                    clientSocket?.close()
                } catch (_: Throwable) {
                }
                clientSocket = socket
                clientOutput = out
            }

            Log.i(TAG, "Authenticated stream client connected from ${socket.inetAddress?.hostAddress}")

            // Immediately push cached SPS/PPS config if present, then request IDR keyframe
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
