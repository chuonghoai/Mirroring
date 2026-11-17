package com.chuonghoai.mirroring.network

import android.util.Base64
import android.util.Log
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Lightweight RFC 6455 WebSocket server running in Kotlin Native so control messages,
 * heartbeats, and session termination continue even when the Flutter Activity is closed.
 */
class ControlWebSocketServer(
    private val preferredPort: Int = 45455,
    private val listener: Listener,
) {
    interface Listener {
        fun onClientConnected(client: ClientSession)
        fun onClientMessage(client: ClientSession, json: JSONObject)
        fun onClientDisconnected(client: ClientSession, reason: String)
    }

    class ClientSession(
        val remoteIp: String,
        private val socket: Socket,
        private val outputStream: OutputStream,
    ) {
        private val closed = AtomicBoolean(false)
        private val writeExecutor = Executors.newSingleThreadExecutor { r ->
            Thread(r, "MirroringWsWrite").apply { isDaemon = true }
        }

        val isOpen: Boolean get() = !closed.get() && !socket.isClosed

        fun sendJson(json: JSONObject): Boolean = sendText(json.toString())

        fun sendText(text: String): Boolean {
            if (closed.get()) return false
            val payload = text.toByteArray(Charsets.UTF_8)
            return sendFrameAsync(opcode = 0x1, payload = payload)
        }

        fun sendPong(payload: ByteArray) {
            if (closed.get()) return
            sendFrameAsync(opcode = 0xA, payload = payload)
        }

        fun sendJsonAndClose(json: JSONObject) {
            if (closed.get()) {
                close()
                return
            }
            val payload = json.toString().toByteArray(Charsets.UTF_8)
            try {
                writeExecutor.execute {
                    try {
                        writeFrameSync(opcode = 0x1, payload = payload)
                    } finally {
                        close()
                    }
                }
            } catch (_: Throwable) {
                close()
            }
        }

        private fun sendFrameAsync(opcode: Int, payload: ByteArray): Boolean {
            if (closed.get()) return false
            return try {
                writeExecutor.execute {
                    writeFrameSync(opcode, payload)
                }
                true
            } catch (t: Throwable) {
                Log.w(TAG, "Failed to enqueue WS frame: ${t.message}")
                close()
                false
            }
        }

        private fun writeFrameSync(opcode: Int, payload: ByteArray): Boolean {
            if (closed.get()) return false
            return try {
                val header = ByteArrayOutputStream()
                header.write(0x80 or (opcode and 0x0F))
                val len = payload.size
                when {
                    len <= 125 -> header.write(len)
                    len <= 65535 -> {
                        header.write(126)
                        header.write((len shr 8) and 0xFF)
                        header.write(len and 0xFF)
                    }
                    else -> {
                        header.write(127)
                        for (shift in 56 downTo 0 step 8) {
                            header.write(((len.toLong() shr shift) and 0xFF).toInt())
                        }
                    }
                }
                outputStream.write(header.toByteArray())
                outputStream.write(payload)
                outputStream.flush()
                true
            } catch (t: Throwable) {
                Log.w(TAG, "WS write error: ${t.message}")
                close()
                false
            }
        }

        fun close() {
            if (!closed.compareAndSet(false, true)) return
            try {
                socket.close()
            } catch (_: Throwable) {
            }
            try {
                writeExecutor.shutdown()
            } catch (_: Throwable) {
            }
        }
    }

    companion object {
        private const val TAG = "ControlWebSocketServer"
        private const val WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        private const val MAX_FRAME_BYTES = 1024 * 1024 // 1 MiB
    }

    private val running = AtomicBoolean(false)
    private var serverSocket: ServerSocket? = null
    private var acceptThread: Thread? = null

    @Volatile
    var listeningPort: Int = 0
        private set

    fun start(): Int {
        if (running.get()) return listeningPort
        val server = try {
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

        serverSocket = server
        listeningPort = server.localPort
        running.set(true)

        acceptThread = Thread({ acceptLoop() }, "MirroringControlAccept").apply {
            isDaemon = true
            start()
        }
        Log.i(TAG, "Control WebSocket server listening on port $listeningPort")
        return listeningPort
    }

    fun stop() {
        if (!running.compareAndSet(true, false)) return
        listeningPort = 0
        try {
            serverSocket?.close()
        } catch (_: Throwable) {
        }
        serverSocket = null
        acceptThread?.interrupt()
        acceptThread = null
    }

    private fun acceptLoop() {
        while (running.get()) {
            val ss = serverSocket ?: break
            try {
                val socket = ss.accept()
                socket.tcpNoDelay = true
                Thread({ handleClient(socket) }, "MirroringControlClient").apply {
                    isDaemon = true
                    start()
                }
            } catch (t: Throwable) {
                if (running.get()) {
                    Log.w(TAG, "Accept error: ${t.message}")
                }
            }
        }
    }

    private fun handleClient(socket: Socket) {
        val remoteIp = socket.inetAddress?.hostAddress ?: "unknown"
        var session: ClientSession? = null
        try {
            socket.soTimeout = 10000
            val input = BufferedInputStream(socket.getInputStream())
            val output = socket.getOutputStream()

            val headers = readHttpHeaders(input) ?: run {
                socket.close()
                return
            }

            val wsKey = headers["sec-websocket-key"] ?: run {
                output.write("HTTP/1.1 400 Bad Request\r\n\r\n".toByteArray())
                socket.close()
                return
            }

            val acceptDigest = MessageDigest.getInstance("SHA-1")
                .digest((wsKey.trim() + WS_GUID).toByteArray(Charsets.UTF_8))
            val acceptValue = Base64.encodeToString(acceptDigest, Base64.NO_WRAP)

            val response = buildString {
                append("HTTP/1.1 101 Switching Protocols\r\n")
                append("Upgrade: websocket\r\n")
                append("Connection: Upgrade\r\n")
                append("Sec-WebSocket-Accept: ").append(acceptValue).append("\r\n")
                append("\r\n")
            }
            output.write(response.toByteArray(Charsets.US_ASCII))
            output.flush()

            // Remove initial handshake timeout; heartbeats supervise active connection.
            socket.soTimeout = 0
            session = ClientSession(remoteIp, socket, output)
            listener.onClientConnected(session)

            readWebSocketLoop(input, session)
            listener.onClientDisconnected(session, "Client closed connection")
        } catch (t: Throwable) {
            if (session != null) {
                listener.onClientDisconnected(session, t.message ?: "Connection reset")
            } else {
                try {
                    socket.close()
                } catch (_: Throwable) {
                }
            }
        } finally {
            session?.close()
        }
    }

    private fun readHttpHeaders(input: InputStream): Map<String, String>? {
        val headerBuf = ByteArrayOutputStream()
        var prev = -1
        var state = 0
        while (headerBuf.size() < 8192) {
            val b = input.read()
            if (b == -1) return null
            headerBuf.write(b)
            when (state) {
                0 -> state = if (b == '\r'.code) 1 else 0
                1 -> state = if (b == '\n'.code) 2 else if (b == '\r'.code) 1 else 0
                2 -> state = if (b == '\r'.code) 3 else 0
                3 -> if (b == '\n'.code) {
                    val raw = String(headerBuf.toByteArray(), Charsets.US_ASCII)
                    val lines = raw.split("\r\n")
                    if (lines.isEmpty() || !lines[0].startsWith("GET ")) return null
                    val map = mutableMapOf<String, String>()
                    for (line in lines.drop(1)) {
                        val idx = line.indexOf(':')
                        if (idx > 0) {
                            map[line.substring(0, idx).trim().lowercase()] =
                                line.substring(idx + 1).trim()
                        }
                    }
                    return map
                } else {
                    state = 0
                }
            }
            prev = b
        }
        return null
    }

    private fun readWebSocketLoop(input: InputStream, session: ClientSession) {
        val fragmented = ByteArrayOutputStream()
        var fragmentedOpcode = -1

        while (session.isOpen) {
            val b0 = input.read()
            if (b0 == -1) break
            val b1 = input.read()
            if (b1 == -1) break

            val fin = (b0 and 0x80) != 0
            val opcode = b0 and 0x0F
            val masked = (b1 and 0x80) != 0
            var len = (b1 and 0x7F).toLong()

            if (len == 126L) {
                val hi = input.read()
                val lo = input.read()
                if (hi == -1 || lo == -1) break
                len = ((hi shl 8) or lo).toLong()
            } else if (len == 127L) {
                var v = 0L
                for (i in 0 until 8) {
                    val next = input.read()
                    if (next == -1) throw EOFException("Unexpected EOF")
                    v = (v shl 8) or next.toLong()
                }
                len = v
            }

            if (len < 0 || len > MAX_FRAME_BYTES) {
                throw IllegalStateException("Frame too large: $len")
            }

            val maskKey = if (masked) readFully(input, 4) else null
            val payload = readFully(input, len.toInt())
            if (maskKey != null) {
                for (i in payload.indices) {
                    payload[i] = (payload[i].toInt() xor maskKey[i % 4].toInt()).toByte()
                }
            }

            when (opcode) {
                0x8 -> { // Close
                    break
                }
                0x9 -> { // Ping
                    session.sendPong(payload)
                }
                0xA -> { // Pong
                    // Ignored
                }
                0x1, 0x2 -> { // Text or Binary
                    if (fin) {
                        handlePayloadText(session, payload)
                    } else {
                        fragmented.reset()
                        fragmented.write(payload)
                        fragmentedOpcode = opcode
                    }
                }
                0x0 -> { // Continuation
                    if (fragmentedOpcode != -1) {
                        fragmented.write(payload)
                        if (fin) {
                            handlePayloadText(session, fragmented.toByteArray())
                            fragmented.reset()
                            fragmentedOpcode = -1
                        }
                    }
                }
            }
        }
    }

    private fun handlePayloadText(session: ClientSession, payload: ByteArray) {
        val text = String(payload, Charsets.UTF_8)
        val json = try {
            JSONObject(text)
        } catch (_: Throwable) {
            return
        }
        if (json.optInt("protocolVersion", -1) != 1) return
        listener.onClientMessage(session, json)
    }

    private fun readFully(input: InputStream, count: Int): ByteArray {
        val buf = ByteArray(count)
        var offset = 0
        while (offset < count) {
            val read = input.read(buf, offset, count - offset)
            if (read == -1) throw EOFException("Unexpected EOF")
            offset += read
        }
        return buf
    }
}
