package com.chuonghoai.mirroring.service

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import androidx.core.content.ContextCompat
import com.chuonghoai.mirroring.capture.ScreenCaptureEncoder
import com.chuonghoai.mirroring.core.DeviceIdentity
import com.chuonghoai.mirroring.network.ControlWebSocketServer
import com.chuonghoai.mirroring.network.DiscoveredWindowsHost
import com.chuonghoai.mirroring.network.LanDiscoveryManager
import com.chuonghoai.mirroring.stream.H264StreamServer
import org.json.JSONObject
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

enum class CompanionSessionState {
    IDLE,
    PENDING_APPROVAL,
    AWAITING_CAPTURE_PERMISSION,
    STREAMING,
    RECONNECTING,
}

data class PendingPairRequest(
    val requestId: String,
    val windowsDeviceId: String,
    val windowsDeviceName: String,
    val remoteIp: String,
    val createdAtMs: Long,
    val expiresAtMs: Long,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "requestId" to requestId,
        "windowsDeviceId" to windowsDeviceId,
        "windowsDeviceName" to windowsDeviceName,
        "remoteIp" to remoteIp,
        "createdAtMs" to createdAtMs,
        "expiresAtMs" to expiresAtMs,
    )
}

interface CompanionUiObserver {
    fun onStateChanged(snapshot: Map<String, Any?>)
    fun onLogMessage(level: String, message: String)
}

/**
 * Application-scoped coordinator that owns LAN discovery, WebSocket control server,
 * pairing approval, session token verification, heartbeat/reconnection supervision,
 * and H.264 MediaProjection streaming lifecycle independently of Flutter Activity UI.
 */
object MirroringSessionCoordinator : ControlWebSocketServer.Listener {
    private const val TAG = "MirroringCoordinator"
    private const val PROTOCOL_VERSION = 1
    private const val PAIR_TIMEOUT_MS = 30_000L
    private const val HEARTBEAT_TIMEOUT_MS = 8_000L
    private const val RECONNECT_WINDOW_MS = 20_000L

    private val secureRandom = SecureRandom()
    private val scheduler = Executors.newSingleThreadScheduledExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val observers = CopyOnWriteArrayList<CompanionUiObserver>()

    @Volatile
    private var appContext: Context? = null
    @Volatile
    private var initialized = false

    private var discoveryManager: LanDiscoveryManager? = null
    private var controlServer: ControlWebSocketServer? = null
    private var streamServer: H264StreamServer? = null
    private var captureEncoder: ScreenCaptureEncoder? = null
    private var activeService: MirroringForegroundService? = null

    private val stateLock = Any()

    @Volatile
    private var sessionState: CompanionSessionState = CompanionSessionState.IDLE
    @Volatile
    private var discoveredHosts: List<DiscoveredWindowsHost> = emptyList()
    @Volatile
    private var pendingRequest: PendingPairRequest? = null
    @Volatile
    private var pendingClient: ControlWebSocketServer.ClientSession? = null
    @Volatile
    private var activeClient: ControlWebSocketServer.ClientSession? = null
    @Volatile
    private var activeSessionToken: String? = null
    @Volatile
    private var connectedWindowsId: String? = null
    @Volatile
    private var connectedWindowsName: String? = null
    @Volatile
    private var lastHeartbeatAtMs: Long = 0L
    @Volatile
    private var reconnectDeadlineMs: Long = 0L
    @Volatile
    private var currentWidth: Int = 0
    @Volatile
    private var currentHeight: Int = 0
    @Volatile
    private var currentRotation: Int = 0
    @Volatile
    private var lastStatusMessage: String? = null

    private var pairTimeoutFuture: ScheduledFuture<*>? = null
    private var supervisorFuture: ScheduledFuture<*>? = null

    fun init(context: Context) {
        synchronized(this) {
            if (initialized) return
            val ctx = context.applicationContext
            appContext = ctx

            val control = ControlWebSocketServer(preferredPort = 45455, listener = this)
            control.start()
            controlServer = control

            val discovery = LanDiscoveryManager(
                context = ctx,
                controlPortProvider = { controlServer?.listeningPort ?: 0 },
                availabilityProvider = {
                    when (sessionState) {
                        CompanionSessionState.IDLE -> "available"
                        CompanionSessionState.STREAMING,
                        CompanionSessionState.RECONNECTING -> "streaming"
                        CompanionSessionState.PENDING_APPROVAL,
                        CompanionSessionState.AWAITING_CAPTURE_PERMISSION -> "busy"
                    }
                },
                onHostsChanged = { hosts ->
                    discoveredHosts = hosts
                    notifyObservers()
                },
            )
            discovery.start()
            discoveryManager = discovery
            initialized = true
            Log.i(TAG, "Coordinator initialized (controlPort=${control.listeningPort})")
        }
    }

    fun addObserver(observer: CompanionUiObserver) {
        if (!observers.contains(observer)) {
            observers.add(observer)
        }
        observer.onStateChanged(buildStateSnapshot())
    }

    fun removeObserver(observer: CompanionUiObserver) {
        observers.remove(observer)
    }

    fun refreshDiscovery() {
        discoveryManager?.broadcastNow()
        notifyObservers()
    }

    fun buildStateSnapshot(): Map<String, Any?> {
        val ctx = appContext
        return mapOf(
            "sessionState" to sessionState.name,
            "deviceId" to (ctx?.let { DeviceIdentity.getOrCreateDeviceId(it) } ?: ""),
            "deviceName" to (ctx?.let { DeviceIdentity.getDeviceName(it) } ?: "Android"),
            "localIps" to DeviceIdentity.getLocalIpv4Addresses(),
            "controlPort" to (controlServer?.listeningPort ?: 0),
            "streamPort" to (streamServer?.listeningPort ?: 0),
            "discoveredHosts" to discoveredHosts.map { it.toMap() },
            "pendingRequest" to pendingRequest?.toMap(),
            "connectedWindowsId" to connectedWindowsId,
            "connectedWindowsName" to connectedWindowsName,
            "streamWidth" to currentWidth,
            "streamHeight" to currentHeight,
            "streamRotation" to currentRotation,
            "reconnectSecondsLeft" to if (sessionState == CompanionSessionState.RECONNECTING) {
                ((reconnectDeadlineMs - System.currentTimeMillis()).coerceAtLeast(0L) / 1000L).toInt()
            } else {
                0
            },
            "accessibilityEnabled" to (ctx?.let { MirroringAccessibilityService.isServiceEnabled(it) } ?: false),
            "statusMessage" to lastStatusMessage,
        )
    }

    fun onAccessibilityStateChanged(enabled: Boolean) {
        val tok = activeSessionToken
        val client = activeClient
        if (tok != null && client != null && sessionState == CompanionSessionState.STREAMING) {
            client.sendJson(
                buildControlJson(
                    "accessibilityStatus",
                    JSONObject().apply {
                        put("sessionToken", tok)
                        put("enabled", enabled)
                    },
                ),
            )
        }
        emitLog("info", if (enabled) "Đã bật dịch vụ Điều khiển từ xa (Accessibility)" else "Dịch vụ Điều khiển từ xa đã tắt")
        notifyObservers()
    }

    /**
     * Called from Flutter UI when the user explicitly accepts or rejects a pending Windows request.
     */
    fun respondToPendingRequest(requestId: String, accepted: Boolean, reason: String? = null): Boolean {
        val req: PendingPairRequest
        val client: ControlWebSocketServer.ClientSession?
        synchronized(stateLock) {
            val current = pendingRequest ?: return false
            if (current.requestId != requestId) return false
            req = current
            client = pendingClient
            cancelPairTimeoutLocked()

            if (!accepted) {
                pendingRequest = null
                pendingClient = null
                sessionState = CompanionSessionState.IDLE
                lastStatusMessage = reason ?: "Đã từ chối yêu cầu từ ${req.windowsDeviceName}"
            } else {
                sessionState = CompanionSessionState.AWAITING_CAPTURE_PERMISSION
                lastStatusMessage = "Đang chờ cấp quyền ghi màn hình..."
            }
        }

        if (!accepted) {
            client?.sendJson(
                buildControlJson(
                    "pairResponse",
                    JSONObject().apply {
                        put("requestId", req.requestId)
                        put("accepted", false)
                        put("reason", reason ?: "Người dùng trên điện thoại đã từ chối kết nối")
                    },
                ),
            )
            emitLog("info", "Rejected pairing request from ${req.windowsDeviceName}")
            notifyObservers()
            discoveryManager?.broadcastNow()
            return true
        }

        emitLog("info", "Accepted pairing request from ${req.windowsDeviceName}; awaiting MediaProjection")
        notifyObservers()
        discoveryManager?.broadcastNow()
        return true
    }

    /**
     * Called by MainActivity when the user cancels or denies the system MediaProjection dialog.
     */
    fun onMediaProjectionDenied() {
        val req: PendingPairRequest?
        val client: ControlWebSocketServer.ClientSession?
        synchronized(stateLock) {
            req = pendingRequest
            client = pendingClient
            pendingRequest = null
            pendingClient = null
            if (sessionState == CompanionSessionState.AWAITING_CAPTURE_PERMISSION ||
                sessionState == CompanionSessionState.PENDING_APPROVAL
            ) {
                sessionState = CompanionSessionState.IDLE
            }
            lastStatusMessage = "Quyền chia sẻ màn hình bị từ chối."
        }
        if (req != null) {
            client?.sendJson(
                buildControlJson(
                    "pairResponse",
                    JSONObject().apply {
                        put("requestId", req.requestId)
                        put("accepted", false)
                        put("reason", "Người dùng từ chối cấp quyền ghi màn hình (MediaProjection)")
                    },
                ),
            )
        }
        emitLog("warn", "MediaProjection permission denied by user")
        notifyObservers()
        discoveryManager?.broadcastNow()
    }

    /**
     * Called by MainActivity right after MediaProjection permission is granted.
     * Starts MirroringForegroundService which will call [onForegroundServiceReady].
     */
    fun launchForegroundMirroringService(context: Context, resultCode: Int, data: Intent) {
        val windowsName: String
        synchronized(stateLock) {
            windowsName = pendingRequest?.windowsDeviceName ?: connectedWindowsName ?: "Windows PC"
        }
        val intent = Intent(context, MirroringForegroundService::class.java).apply {
            action = MirroringForegroundService.ACTION_START_MIRRORING
            putExtra(MirroringForegroundService.EXTRA_RESULT_CODE, resultCode)
            putExtra(MirroringForegroundService.EXTRA_DATA_INTENT, data)
            putExtra(MirroringForegroundService.EXTRA_WINDOWS_NAME, windowsName)
        }
        ContextCompat.startForegroundService(context, intent)
    }

    /**
     * Called from inside [MirroringForegroundService.onStartCommand] AFTER startForeground() has run.
     */
    fun onForegroundServiceReady(
        service: MirroringForegroundService,
        resultCode: Int,
        data: Intent,
    ) {
        val ctx = service.applicationContext
        val req: PendingPairRequest
        val client: ControlWebSocketServer.ClientSession?
        val token = generateSessionToken()

        synchronized(stateLock) {
            val currentReq = pendingRequest
            if (currentReq == null) {
                Log.w(TAG, "No pending request when foreground service became ready; stopping service")
                service.stopServiceCleanly()
                return
            }
            req = currentReq
            client = pendingClient
            activeService = service
            activeClient = client
            activeSessionToken = token
            connectedWindowsId = req.windowsDeviceId
            connectedWindowsName = req.windowsDeviceName
            pendingRequest = null
            pendingClient = null
            lastHeartbeatAtMs = System.currentTimeMillis()
        }

        try {
            val mpm = ctx.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val projection: MediaProjection? = mpm.getMediaProjection(resultCode, data)
            if (projection == null) {
                throw IllegalStateException("MediaProjection returned null")
            }

            val stream = H264StreamServer(
                preferredPort = 45456,
                sessionTokenProvider = { activeSessionToken },
                onClientAuthenticated = {
                    captureEncoder?.requestKeyFrame()
                },
                onClientStreamLost = { reason ->
                    handleUnexpectedConnectionLoss("Stream lost: $reason")
                },
            )
            val streamPort = stream.start()
            streamServer = stream

            val encoder = ScreenCaptureEncoder(
                context = ctx,
                mediaProjection = projection,
                maxDimension = 1280,
                targetFps = 60,
                bitrate = 6_000_000,
                listener = object : ScreenCaptureEncoder.Listener {
                    override fun onVideoFrame(
                        frameType: Int,
                        rotationQuarterTurns: Int,
                        width: Int,
                        height: Int,
                        timestampUs: Long,
                        payload: ByteArray,
                    ) {
                        if (sessionState == CompanionSessionState.STREAMING) {
                            streamServer?.sendFrame(
                                frameType = frameType,
                                rotationQuarterTurns = rotationQuarterTurns,
                                width = width,
                                height = height,
                                timestampUs = timestampUs,
                                payload = payload,
                            )
                        }
                    }

                    override fun onStreamDimensionsChanged(
                        width: Int,
                        height: Int,
                        rotationQuarterTurns: Int,
                    ) {
                        currentWidth = width
                        currentHeight = height
                        currentRotation = rotationQuarterTurns
                        val tok = activeSessionToken ?: return
                        activeClient?.sendJson(
                            buildControlJson(
                                "streamConfig",
                                JSONObject().apply {
                                    put("sessionToken", tok)
                                    put("width", width)
                                    put("height", height)
                                    put("rotation", rotationQuarterTurns)
                                },
                            ),
                        )
                        notifyObservers()
                    }

                    override fun onProjectionStopped() {
                        stopSession("Quyền chia sẻ màn hình đã bị thu hồi trên Android", notifyPeer = true)
                    }

                    override fun onCaptureError(message: String) {
                        lastStatusMessage = message
                        emitLog("error", message)
                        stopSession(message, notifyPeer = true)
                    }
                },
            )
            val snapshot = encoder.start()
            captureEncoder = encoder
            currentWidth = snapshot.width
            currentHeight = snapshot.height
            currentRotation = snapshot.rotation

            synchronized(stateLock) {
                sessionState = CompanionSessionState.STREAMING
                lastHeartbeatAtMs = System.currentTimeMillis()
                lastStatusMessage = "Đang chia sẻ màn hình với ${req.windowsDeviceName}"
            }

            startSupervisorTimer()
            activeService?.updateNotification(
                isReconnecting = false,
                windowsName = req.windowsDeviceName,
            )

            // Reply pairResponse(accepted: true) with secure sessionToken & streamPort
            client?.sendJson(
                buildControlJson(
                    "pairResponse",
                    JSONObject().apply {
                        put("requestId", req.requestId)
                        put("accepted", true)
                        put("sessionToken", token)
                        put("streamPort", streamPort)
                        put("deviceId", DeviceIdentity.getOrCreateDeviceId(ctx))
                        put("deviceName", DeviceIdentity.getDeviceName(ctx))
                    },
                ),
            )

            emitLog("info", "Streaming started to ${req.windowsDeviceName} (${snapshot.width}x${snapshot.height}, port=$streamPort)")
            notifyObservers()
            discoveryManager?.broadcastNow()
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to start capture/stream: ${t.message}", t)
            client?.sendJson(
                buildControlJson(
                    "pairResponse",
                    JSONObject().apply {
                        put("requestId", req.requestId)
                        put("accepted", false)
                        put("reason", "Không thể khởi động MediaProjection: ${t.message}")
                    },
                ),
            )
            stopSession("Lỗi khởi động ghi màn hình: ${t.message}", notifyPeer = false)
        }
    }

    fun stopSession(reason: String, notifyPeer: Boolean = true) {
        val clientToNotify: ControlWebSocketServer.ClientSession?
        val tokenToNotify: String?
        val serviceToStop: MirroringForegroundService?

        synchronized(stateLock) {
            if (sessionState == CompanionSessionState.IDLE &&
                captureEncoder == null &&
                streamServer == null &&
                activeService == null
            ) {
                return
            }

            cancelPairTimeoutLocked()
            supervisorFuture?.cancel(false)
            supervisorFuture = null

            clientToNotify = activeClient ?: pendingClient
            tokenToNotify = activeSessionToken
            serviceToStop = activeService

            pendingRequest = null
            pendingClient = null
            activeClient = null
            activeSessionToken = null
            connectedWindowsId = null
            connectedWindowsName = null
            activeService = null
            currentWidth = 0
            currentHeight = 0
            currentRotation = 0
            reconnectDeadlineMs = 0L
            sessionState = CompanionSessionState.IDLE
            lastStatusMessage = reason
        }

        if (notifyPeer && clientToNotify != null && tokenToNotify != null) {
            clientToNotify.sendJsonAndClose(
                buildControlJson(
                    "sessionStop",
                    JSONObject().apply {
                        put("sessionToken", tokenToNotify)
                        put("reason", reason)
                    },
                ),
            )
        } else {
            try {
                clientToNotify?.close()
            } catch (_: Throwable) {
            }
        }

        try {
            captureEncoder?.stop()
        } catch (_: Throwable) {
        }
        captureEncoder = null

        try {
            streamServer?.stop()
        } catch (_: Throwable) {
        }
        streamServer = null

        serviceToStop?.stopServiceCleanly()
        emitLog("info", "Session ended: $reason")
        notifyObservers()
        discoveryManager?.broadcastNow()
    }

    // --- ControlWebSocketServer.Listener ---

    override fun onClientConnected(client: ControlWebSocketServer.ClientSession) {
        Log.d(TAG, "Control WS client connected from ${client.remoteIp}")
    }

    override fun onClientMessage(client: ControlWebSocketServer.ClientSession, json: JSONObject) {
        val type = json.optString("type")
        val payload = json.optJSONObject("payload") ?: JSONObject()

        when (type) {
            "pairRequest" -> handlePairRequest(client, payload)
            "pairCancel" -> handlePairCancel(client, payload)
            "sessionStart" -> handleSessionStart(client, payload)
            "heartbeat" -> handleHeartbeat(client, payload)
            "sessionStop" -> handleSessionStop(client, payload)
            "clipboardPush" -> handleClipboardPush(client, payload)
            "inputGesture" -> handleInputGesture(client, payload)
            "inputAction" -> handleInputAction(client, payload)
            "inputText" -> handleInputText(client, payload)
            else -> {
                client.sendJson(
                    buildControlJson(
                        "error",
                        JSONObject().apply {
                            put("code", "UNSUPPORTED_MESSAGE")
                            put("message", "Unknown control message type: $type")
                        },
                    ),
                )
            }
        }
    }

    override fun onClientDisconnected(client: ControlWebSocketServer.ClientSession, reason: String) {
        synchronized(stateLock) {
            if (pendingClient === client && sessionState == CompanionSessionState.PENDING_APPROVAL) {
                cancelPairTimeoutLocked()
                pendingRequest = null
                pendingClient = null
                sessionState = CompanionSessionState.IDLE
                lastStatusMessage = "Yêu cầu kết nối đã đóng"
                notifyObservers()
                discoveryManager?.broadcastNow()
                return
            }
        }

        if (activeClient === client) {
            handleUnexpectedConnectionLoss("Control WebSocket closed: $reason")
        }
    }

    private fun handlePairRequest(client: ControlWebSocketServer.ClientSession, payload: JSONObject) {
        val requestId = payload.optString("requestId")
        val windowsId = payload.optString("windowsDeviceId")
        val rawName = payload.optString("windowsDeviceName", "Windows PC")
            .replace(Regex("[\\x00-\\x1F\\x7F]"), "")
            .trim()
        val windowsName = (if (rawName.isEmpty()) "Windows PC" else rawName).take(64)

        if (requestId.isBlank() || !windowsId.matches(Regex("^[a-zA-Z0-9_-]{8,64}$"))) {
            client.sendJson(
                buildControlJson(
                    "pairResponse",
                    JSONObject().apply {
                        put("requestId", requestId)
                        put("accepted", false)
                        put("reason", "Yêu cầu kết nối không hợp lệ")
                    },
                ),
            )
            return
        }

        synchronized(stateLock) {
            if (sessionState != CompanionSessionState.IDLE) {
                client.sendJson(
                    buildControlJson(
                        "pairResponse",
                        JSONObject().apply {
                            put("requestId", requestId)
                            put("accepted", false)
                            put("reason", "Thiết bị Android đang bận hoặc đang chia sẻ màn hình")
                        },
                    ),
                )
                return
            }

            val now = System.currentTimeMillis()
            val req = PendingPairRequest(
                requestId = requestId,
                windowsDeviceId = windowsId,
                windowsDeviceName = windowsName,
                remoteIp = client.remoteIp,
                createdAtMs = now,
                expiresAtMs = now + PAIR_TIMEOUT_MS,
            )
            pendingRequest = req
            pendingClient = client
            sessionState = CompanionSessionState.PENDING_APPROVAL
            lastStatusMessage = "Nhận yêu cầu kết nối từ $windowsName"

            cancelPairTimeoutLocked()
            pairTimeoutFuture = scheduler.schedule({
                expirePendingRequest(requestId)
            }, PAIR_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        }

        emitLog("info", "Incoming connection request from $windowsName (${client.remoteIp})")
        notifyObservers()
        discoveryManager?.broadcastNow()
    }

    private fun handlePairCancel(client: ControlWebSocketServer.ClientSession, payload: JSONObject) {
        val requestId = payload.optString("requestId")
        synchronized(stateLock) {
            if (pendingRequest?.requestId == requestId && pendingClient === client) {
                cancelPairTimeoutLocked()
                pendingRequest = null
                pendingClient = null
                sessionState = CompanionSessionState.IDLE
                lastStatusMessage = payload.optString("reason", "Windows đã hủy yêu cầu")
                notifyObservers()
                discoveryManager?.broadcastNow()
            }
        }
    }

    private fun handleSessionStart(client: ControlWebSocketServer.ClientSession, payload: JSONObject) {
        val token = payload.optString("sessionToken")
        if (!isAuthorizedToken(token)) {
            sendUnauthorizedError(client)
            return
        }

        val winName: String
        synchronized(stateLock) {
            activeClient = client
            lastHeartbeatAtMs = System.currentTimeMillis()
            if (sessionState == CompanionSessionState.RECONNECTING) {
                sessionState = CompanionSessionState.STREAMING
                reconnectDeadlineMs = 0L
                lastStatusMessage = "Đã kết nối lại với ${connectedWindowsName ?: "Windows"}"
            }
            winName = connectedWindowsName ?: "Windows PC"
        }

        activeService?.updateNotification(isReconnecting = false, windowsName = winName)

        val accEnabled = appContext?.let { MirroringAccessibilityService.isServiceEnabled(it) } ?: false
        client.sendJson(
            buildControlJson(
                "sessionAck",
                JSONObject().apply {
                    put("sessionToken", token)
                    put("width", currentWidth)
                    put("height", currentHeight)
                    put("rotation", currentRotation)
                    put("streamPort", streamServer?.listeningPort ?: 0)
                    put("accessibilityEnabled", accEnabled)
                },
            ),
        )
        captureEncoder?.requestKeyFrame()
        notifyObservers()
    }

    private fun handleHeartbeat(client: ControlWebSocketServer.ClientSession, payload: JSONObject) {
        val token = payload.optString("sessionToken")
        if (!isAuthorizedToken(token)) {
            sendUnauthorizedError(client)
            return
        }

        val wasReconnecting: Boolean
        val winName: String
        synchronized(stateLock) {
            activeClient = client
            lastHeartbeatAtMs = System.currentTimeMillis()
            wasReconnecting = sessionState == CompanionSessionState.RECONNECTING
            if (wasReconnecting) {
                sessionState = CompanionSessionState.STREAMING
                reconnectDeadlineMs = 0L
                lastStatusMessage = "Đã khôi phục kết nối với ${connectedWindowsName ?: "Windows"}"
            }
            winName = connectedWindowsName ?: "Windows PC"
        }

        if (wasReconnecting) {
            activeService?.updateNotification(isReconnecting = false, windowsName = winName)
            notifyObservers()
        }

        client.sendJson(
            buildControlJson(
                "heartbeatAck",
                JSONObject().apply {
                    put("sessionToken", token)
                    put("seq", payload.optLong("seq", 0L))
                    put("timestampMs", System.currentTimeMillis())
                },
            ),
        )
    }

    private fun handleSessionStop(client: ControlWebSocketServer.ClientSession, payload: JSONObject) {
        val token = payload.optString("sessionToken")
        if (!isAuthorizedToken(token)) {
            sendUnauthorizedError(client)
            return
        }
        val reason = payload.optString("reason", "Windows đã kết thúc phiên trình chiếu")
        emitLog("info", "Received authenticated sessionStop: $reason")
        stopSession(reason, notifyPeer = false)
    }

    private fun handleClipboardPush(client: ControlWebSocketServer.ClientSession, payload: JSONObject) {
        val token = payload.optString("sessionToken")
        if (!isAuthorizedToken(token)) {
            sendUnauthorizedError(client)
            return
        }
        val text = payload.optString("text", "")
        if (text.isEmpty()) return
        val ctx = appContext ?: return

        mainHandler.post {
            try {
                val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                cm.setPrimaryClip(ClipData.newPlainText("Mirroring", text))
                emitLog("info", "Updated Android clipboard (${text.length} chars) from Windows")
            } catch (t: Throwable) {
                emitLog("warn", "Could not update clipboard: ${t.message}")
            }
        }
    }

    private fun handleInputGesture(client: ControlWebSocketServer.ClientSession, payload: JSONObject) {
        val token = payload.optString("sessionToken")
        if (!isAuthorizedToken(token)) {
            sendUnauthorizedError(client)
            return
        }
        val acc = MirroringAccessibilityService.instance
        if (acc == null) {
            sendAccessibilityMissingError(client, token)
            return
        }
        val arr = payload.optJSONArray("points") ?: return
        val points = mutableListOf<Pair<Float, Float>>()
        for (i in 0 until arr.length()) {
            val pt = arr.optJSONObject(i) ?: continue
            val x = pt.optDouble("x", Double.NaN).toFloat()
            val y = pt.optDouble("y", Double.NaN).toFloat()
            if (!x.isNaN() && !y.isNaN()) {
                points.add(x to y)
            }
        }
        val durationMs = payload.optLong("durationMs", 45L)
        acc.performTouchGesture(points, durationMs)
    }

    private fun handleInputAction(client: ControlWebSocketServer.ClientSession, payload: JSONObject) {
        val token = payload.optString("sessionToken")
        if (!isAuthorizedToken(token)) {
            sendUnauthorizedError(client)
            return
        }
        val acc = MirroringAccessibilityService.instance
        if (acc == null) {
            sendAccessibilityMissingError(client, token)
            return
        }
        val action = payload.optString("action")
        if (action.isNotBlank()) {
            acc.performNavigationAction(action)
        }
    }

    private fun handleInputText(client: ControlWebSocketServer.ClientSession, payload: JSONObject) {
        val token = payload.optString("sessionToken")
        if (!isAuthorizedToken(token)) {
            sendUnauthorizedError(client)
            return
        }
        val acc = MirroringAccessibilityService.instance
        if (acc == null) {
            sendAccessibilityMissingError(client, token)
            return
        }
        val text = payload.optString("text", "")
        if (text.isNotEmpty()) {
            acc.inputTextOnFocusedNode(text)
        }
    }

    private fun sendAccessibilityMissingError(client: ControlWebSocketServer.ClientSession, token: String) {
        client.sendJson(
            buildControlJson(
                "accessibilityStatus",
                JSONObject().apply {
                    put("sessionToken", token)
                    put("enabled", false)
                },
            ),
        )
    }

    private fun expirePendingRequest(requestId: String) {
        val client: ControlWebSocketServer.ClientSession?
        synchronized(stateLock) {
            val current = pendingRequest ?: return
            if (current.requestId != requestId) return
            client = pendingClient
            pendingRequest = null
            pendingClient = null
            sessionState = CompanionSessionState.IDLE
            lastStatusMessage = "Yêu cầu từ ${current.windowsDeviceName} đã hết hạn"
        }
        client?.sendJson(
            buildControlJson(
                "pairResponse",
                JSONObject().apply {
                    put("requestId", requestId)
                    put("accepted", false)
                    put("reason", "Yêu cầu xác nhận đã hết hạn (30 giây)")
                },
            ),
        )
        emitLog("warn", "Pending connection request $requestId expired")
        notifyObservers()
        discoveryManager?.broadcastNow()
    }

    private fun startSupervisorTimer() {
        supervisorFuture?.cancel(false)
        supervisorFuture = scheduler.scheduleAtFixedRate({
            checkHeartbeatAndReconnectTimeout()
        }, 2, 2, TimeUnit.SECONDS)
    }

    private fun checkHeartbeatAndReconnectTimeout() {
        val now = System.currentTimeMillis()
        when (sessionState) {
            CompanionSessionState.STREAMING -> {
                if (now - lastHeartbeatAtMs > HEARTBEAT_TIMEOUT_MS) {
                    handleUnexpectedConnectionLoss("Mất tín hiệu heartbeat từ Windows")
                }
            }
            CompanionSessionState.RECONNECTING -> {
                if (now >= reconnectDeadlineMs) {
                    stopSession("Mất kết nối với Windows quá thời gian chờ (${RECONNECT_WINDOW_MS / 1000}s)", notifyPeer = false)
                } else {
                    notifyObservers()
                }
            }
            else -> {}
        }
    }

    private fun handleUnexpectedConnectionLoss(reason: String) {
        val winName: String
        synchronized(stateLock) {
            if (sessionState != CompanionSessionState.STREAMING) return
            sessionState = CompanionSessionState.RECONNECTING
            reconnectDeadlineMs = System.currentTimeMillis() + RECONNECT_WINDOW_MS
            activeClient = null
            lastStatusMessage = "Mất kết nối ($reason). Đang chờ Windows kết nối lại..."
            winName = connectedWindowsName ?: "Windows PC"
        }
        activeService?.updateNotification(isReconnecting = true, windowsName = winName)
        emitLog("warn", "Entered reconnection state ($reason); timeout in ${RECONNECT_WINDOW_MS / 1000}s")
        notifyObservers()
        discoveryManager?.broadcastNow()
    }

    private fun cancelPairTimeoutLocked() {
        pairTimeoutFuture?.cancel(false)
        pairTimeoutFuture = null
    }

    private fun isAuthorizedToken(provided: String): Boolean {
        val expected = activeSessionToken
        if (expected.isNullOrBlank() || provided.isBlank()) return false
        return MessageDigest.isEqual(
            expected.toByteArray(Charsets.UTF_8),
            provided.toByteArray(Charsets.UTF_8),
        )
    }

    private fun sendUnauthorizedError(client: ControlWebSocketServer.ClientSession) {
        client.sendJson(
            buildControlJson(
                "error",
                JSONObject().apply {
                    put("code", "UNAUTHORIZED")
                    put("message", "Invalid or expired session token")
                },
            ),
        )
    }

    private fun generateSessionToken(): String {
        val bytes = ByteArray(32)
        secureRandom.nextBytes(bytes)
        return Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
    }

    private fun buildControlJson(type: String, payload: JSONObject): JSONObject {
        return JSONObject().apply {
            put("protocolVersion", PROTOCOL_VERSION)
            put("type", type)
            put("payload", payload)
        }
    }

    private fun notifyObservers() {
        val snapshot = buildStateSnapshot()
        mainHandler.post {
            for (obs in observers) {
                obs.onStateChanged(snapshot)
            }
        }
    }

    private fun emitLog(level: String, message: String) {
        Log.i(TAG, "[$level] $message")
        mainHandler.post {
            for (obs in observers) {
                obs.onLogMessage(level, message)
            }
        }
    }
}
