package com.chuonghoai.mirroring.network

import android.content.Context
import android.net.wifi.WifiManager
import android.util.Log
import com.chuonghoai.mirroring.core.DeviceIdentity
import org.json.JSONObject
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.net.SocketTimeoutException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

data class DiscoveredWindowsHost(
    val deviceId: String,
    val deviceName: String,
    val ipAddress: String,
    val controlPort: Int,
    val availability: String,
    val lastSeenAtMs: Long,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "deviceId" to deviceId,
        "deviceName" to deviceName,
        "ipAddress" to ipAddress,
        "controlPort" to controlPort,
        "availability" to availability,
        "lastSeenAtMs" to lastSeenAtMs,
    )
}

class LanDiscoveryManager(
    private val context: Context,
    private val controlPortProvider: () -> Int,
    private val availabilityProvider: () -> String,
    private val onHostsChanged: (List<DiscoveredWindowsHost>) -> Unit,
) {
    companion object {
        private const val TAG = "LanDiscoveryManager"
        private const val DISCOVERY_PORT = 45454
        private const val PROTOCOL_VERSION = 1
        private const val MAGIC = "MIRRORING_LAN_V1"
        private const val BEACON_INTERVAL_MS = 2000L
        private const val OFFLINE_TIMEOUT_MS = 7000L
    }

    private val running = AtomicBoolean(false)
    private var socket: DatagramSocket? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var listenThread: Thread? = null
    private var beaconThread: Thread? = null

    private val discoveredHosts = ConcurrentHashMap<String, DiscoveredWindowsHost>()
    private val deviceId: String by lazy { DeviceIdentity.getOrCreateDeviceId(context) }

    fun start() {
        if (!running.compareAndSet(false, true)) return
        acquireMulticastLock()

        try {
            socket = DatagramSocket(null).apply {
                reuseAddress = true
                broadcast = true
                soTimeout = 1500
                bind(InetSocketAddress(DISCOVERY_PORT))
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to bind discovery UDP port $DISCOVERY_PORT: ${t.message}")
            // Fallback to ephemeral socket for sending beacons if port is busy
            try {
                socket = DatagramSocket().apply {
                    broadcast = true
                    soTimeout = 1500
                }
            } catch (inner: Throwable) {
                Log.e(TAG, "Failed to open fallback UDP socket: ${inner.message}")
                running.set(false)
                releaseMulticastLock()
                return
            }
        }

        listenThread = Thread({ listenLoop() }, "MirroringDiscoveryListen").apply {
            isDaemon = true
            start()
        }
        beaconThread = Thread({ beaconLoop() }, "MirroringDiscoveryBeacon").apply {
            isDaemon = true
            start()
        }
    }

    fun stop() {
        if (!running.compareAndSet(true, false)) return
        try {
            socket?.close()
        } catch (_: Throwable) {
        }
        socket = null
        listenThread?.interrupt()
        beaconThread?.interrupt()
        listenThread = null
        beaconThread = null
        discoveredHosts.clear()
        releaseMulticastLock()
        onHostsChanged(emptyList())
    }

    fun broadcastNow() {
        if (!running.get()) return
        Thread({ sendBeaconOnce() }, "MirroringBeaconBurst").apply {
            isDaemon = true
            start()
        }
    }

    private fun listenLoop() {
        val buf = ByteArray(4096)
        while (running.get()) {
            val s = socket ?: break
            try {
                val packet = DatagramPacket(buf, buf.size)
                s.receive(packet)
                val senderIp = packet.address?.hostAddress ?: continue
                val payload = String(packet.data, packet.offset, packet.length, Charsets.UTF_8)
                handleIncomingPacket(payload, senderIp)
            } catch (_: SocketTimeoutException) {
                pruneOfflineHosts()
            } catch (t: Throwable) {
                if (running.get()) {
                    Log.w(TAG, "Discovery receive error: ${t.message}")
                }
            }
        }
    }

    private fun beaconLoop() {
        while (running.get()) {
            sendBeaconOnce()
            pruneOfflineHosts()
            try {
                Thread.sleep(BEACON_INTERVAL_MS)
            } catch (_: InterruptedException) {
                break
            }
        }
    }

    private fun sendBeaconOnce() {
        val s = socket ?: return
        val port = controlPortProvider()
        if (port <= 0) return

        try {
            val json = JSONObject().apply {
                put("magic", MAGIC)
                put("protocolVersion", PROTOCOL_VERSION)
                put("deviceId", deviceId)
                put("deviceName", DeviceIdentity.getDeviceName(context))
                put("deviceType", "androidCompanion")
                put("controlPort", port)
                put("availability", availabilityProvider())
                put("timestampMs", System.currentTimeMillis())
            }
            val bytes = json.toString().toByteArray(Charsets.UTF_8)
            val targets = DeviceIdentity.getBroadcastAddresses()
            for (addr in targets) {
                try {
                    val packet = DatagramPacket(bytes, bytes.size, addr, DISCOVERY_PORT)
                    s.send(packet)
                } catch (_: Throwable) {
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "Error building discovery beacon: ${t.message}")
        }
    }

    private fun handleIncomingPacket(raw: String, senderIp: String) {
        val json = try {
            JSONObject(raw)
        } catch (_: Throwable) {
            return
        }

        if (json.optString("magic") != MAGIC) return
        if (json.optInt("protocolVersion", -1) != PROTOCOL_VERSION) return

        val remoteId = json.optString("deviceId")
        if (!remoteId.matches(Regex("^[a-zA-Z0-9_-]{8,64}$"))) return
        if (remoteId == deviceId) return

        val deviceType = json.optString("deviceType")
        if (deviceType != "windowsHost") return

        val rawName = json.optString("deviceName", "Windows PC")
            .replace(Regex("[\\x00-\\x1F\\x7F]"), "")
            .trim()
        val deviceName = (if (rawName.isEmpty()) "Windows PC" else rawName).take(64)
        val controlPort = json.optInt("controlPort", 0)
        val availability = json.optString("availability", "available")
        val now = System.currentTimeMillis()

        val host = DiscoveredWindowsHost(
            deviceId = remoteId,
            deviceName = deviceName,
            ipAddress = senderIp,
            controlPort = controlPort,
            availability = availability,
            lastSeenAtMs = now,
        )

        val previous = discoveredHosts.put(remoteId, host)
        if (previous == null ||
            previous.ipAddress != host.ipAddress ||
            previous.deviceName != host.deviceName ||
            previous.availability != host.availability
        ) {
            emitHosts()
        }
    }

    private fun pruneOfflineHosts() {
        val now = System.currentTimeMillis()
        var removed = false
        val iterator = discoveredHosts.entries.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            if (now - entry.value.lastSeenAtMs > OFFLINE_TIMEOUT_MS) {
                iterator.remove()
                removed = true
            }
        }
        if (removed) {
            emitHosts()
        }
    }

    private fun emitHosts() {
        val list = discoveredHosts.values.sortedBy { it.deviceName.lowercase() }
        onHostsChanged(list)
    }

    private fun acquireMulticastLock() {
        try {
            val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            multicastLock = wifiManager?.createMulticastLock("MirroringDiscoveryLock")?.apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (t: Throwable) {
            Log.w(TAG, "Could not acquire MulticastLock: ${t.message}")
        }
    }

    private fun releaseMulticastLock() {
        try {
            if (multicastLock?.isHeld == true) {
                multicastLock?.release()
            }
        } catch (_: Throwable) {
        } finally {
            multicastLock = null
        }
    }
}
