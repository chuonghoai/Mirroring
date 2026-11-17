package com.chuonghoai.mirroring.core

import android.content.Context
import android.os.Build
import android.provider.Settings
import java.net.Inet4Address
import java.net.InetAddress
import java.net.NetworkInterface
import java.security.SecureRandom

object DeviceIdentity {
    private const val PREFS_NAME = "mirroring_companion_prefs"
    private const val KEY_DEVICE_ID = "stable_device_id"
    private val secureRandom = SecureRandom()

    fun getOrCreateDeviceId(context: Context): String {
        val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val existing = prefs.getString(KEY_DEVICE_ID, null)
        if (!existing.isNullOrBlank() && existing.matches(Regex("^[a-zA-Z0-9_-]{8,64}$"))) {
            return existing
        }
        val bytes = ByteArray(12)
        secureRandom.nextBytes(bytes)
        val hex = bytes.joinToString("") { "%02x".format(it) }
        val generated = "android_$hex"
        prefs.edit().putString(KEY_DEVICE_ID, generated).apply()
        return generated
    }

    fun getDeviceName(context: Context): String {
        val customName = try {
            Settings.Global.getString(context.contentResolver, "device_name")
        } catch (_: Throwable) {
            null
        }
        val raw = if (!customName.isNullOrBlank()) {
            customName
        } else {
            val manufacturer = Build.MANUFACTURER?.trim().orEmpty()
            val model = Build.MODEL?.trim().orEmpty()
            if (manufacturer.isNotEmpty() && !model.lowercase().startsWith(manufacturer.lowercase())) {
                "${manufacturer.replaceFirstChar { it.uppercase() }} $model"
            } else {
                model.ifEmpty { "Android Device" }
            }
        }
        val cleaned = raw.replace(Regex("[\\x00-\\x1F\\x7F]"), "").trim()
        return if (cleaned.length > 64) cleaned.substring(0, 64) else cleaned.ifEmpty { "Android Device" }
    }

    fun getLocalIpv4Addresses(): List<String> {
        val result = mutableListOf<String>()
        try {
            val interfaces = NetworkInterface.getNetworkInterfaces() ?: return result
            for (iface in interfaces) {
                if (!iface.isUp || iface.isLoopback || iface.isVirtual) continue
                for (addr in iface.inetAddresses) {
                    if (addr is Inet4Address && !addr.isLoopbackAddress && addr.isSiteLocalAddress) {
                        addr.hostAddress?.let { result.add(it) }
                    }
                }
            }
        } catch (_: Throwable) {
        }
        return result.distinct()
    }

    fun getBroadcastAddresses(): List<InetAddress> {
        val result = linkedSetOf<InetAddress>()
        try {
            result.add(InetAddress.getByName("255.255.255.255"))
            val interfaces = NetworkInterface.getNetworkInterfaces() ?: return result.toList()
            for (iface in interfaces) {
                if (!iface.isUp || iface.isLoopback) continue
                for (ifaceAddr in iface.interfaceAddresses) {
                    val addr = ifaceAddr.address
                    if (addr is Inet4Address && !addr.isLoopbackAddress) {
                        ifaceAddr.broadcast?.let { result.add(it) }
                    }
                }
            }
        } catch (_: Throwable) {
        }
        return result.toList()
    }
}
