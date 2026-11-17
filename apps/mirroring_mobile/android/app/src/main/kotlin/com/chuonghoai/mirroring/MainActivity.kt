package com.chuonghoai.mirroring

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.chuonghoai.mirroring.service.CompanionUiObserver
import com.chuonghoai.mirroring.service.MirroringSessionCoordinator
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), CompanionUiObserver {
    companion object {
        private const val METHOD_CHANNEL = "com.chuonghoai.mirroring/native"
        private const val EVENT_CHANNEL = "com.chuonghoai.mirroring/events"
        private const val REQ_MEDIA_PROJECTION = 4501
        private const val REQ_POST_NOTIFICATIONS = 4502
    }

    private var eventSink: EventChannel.EventSink? = null
    private var pendingProjectionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        MirroringSessionCoordinator.init(applicationContext)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MirroringSessionCoordinator.init(applicationContext)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                handleMethodCall(call, result)
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    MirroringSessionCoordinator.addObserver(this@MainActivity)
                }

                override fun onCancel(arguments: Any?) {
                    MirroringSessionCoordinator.removeObserver(this@MainActivity)
                    eventSink = null
                }
            })
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getSnapshot" -> {
                result.success(MirroringSessionCoordinator.buildStateSnapshot())
            }

            "refreshDiscovery" -> {
                MirroringSessionCoordinator.refreshDiscovery()
                result.success(true)
            }

            "hasNotificationPermission" -> {
                val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.POST_NOTIFICATIONS,
                    ) == PackageManager.PERMISSION_GRANTED
                } else {
                    true
                }
                result.success(granted)
            }

            "requestNotificationPermission" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    val granted = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.POST_NOTIFICATIONS,
                    ) == PackageManager.PERMISSION_GRANTED
                    if (!granted) {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            REQ_POST_NOTIFICATIONS,
                        )
                    }
                    result.success(granted)
                } else {
                    result.success(true)
                }
            }

            "respondToRequest" -> {
                val requestId = call.argument<String>("requestId").orEmpty()
                val accepted = call.argument<Boolean>("accepted") ?: false
                val reason = call.argument<String>("reason")
                val ok = MirroringSessionCoordinator.respondToPendingRequest(requestId, accepted, reason)
                result.success(ok)
            }

            "requestMediaProjectionAndStart" -> {
                if (pendingProjectionResult != null) {
                    result.error("BUSY", "MediaProjection request already in progress", null)
                    return
                }
                pendingProjectionResult = result
                val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                @Suppress("DEPRECATION")
                startActivityForResult(mpm.createScreenCaptureIntent(), REQ_MEDIA_PROJECTION)
            }

            "stopSession" -> {
                val reason = call.argument<String>("reason") ?: "Người dùng đã dừng chia sẻ trên điện thoại"
                MirroringSessionCoordinator.stopSession(reason, notifyPeer = true)
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_MEDIA_PROJECTION) {
            val callback = pendingProjectionResult
            pendingProjectionResult = null
            if (resultCode == Activity.RESULT_OK && data != null) {
                MirroringSessionCoordinator.launchForegroundMirroringService(this, resultCode, data)
                callback?.success(true)
            } else {
                MirroringSessionCoordinator.onMediaProjectionDenied()
                callback?.success(false)
            }
        }
    }

    override fun onDestroy() {
        MirroringSessionCoordinator.removeObserver(this)
        eventSink = null
        // Deliberately do NOT stop MirroringForegroundService here so active mirroring continues in background.
        super.onDestroy()
    }

    override fun onStateChanged(snapshot: Map<String, Any?>) {
        eventSink?.success(
            mapOf(
                "type" to "state",
                "data" to snapshot,
            ),
        )
    }

    override fun onLogMessage(level: String, message: String) {
        eventSink?.success(
            mapOf(
                "type" to "log",
                "level" to level,
                "message" to message,
            ),
        )
    }
}
