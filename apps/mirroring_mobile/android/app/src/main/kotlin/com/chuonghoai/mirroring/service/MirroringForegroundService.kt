package com.chuonghoai.mirroring.service

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.chuonghoai.mirroring.MainActivity
import com.chuonghoai.mirroring.R

class MirroringForegroundService : Service() {
    companion object {
        private const val TAG = "MirroringFgService"
        const val CHANNEL_ID = "mirroring_active_session"
        const val NOTIFICATION_ID = 45450

        const val ACTION_START_MIRRORING = "com.chuonghoai.mirroring.action.START_MIRRORING"
        const val ACTION_STOP_MIRRORING = "com.chuonghoai.mirroring.action.STOP_MIRRORING"

        const val EXTRA_RESULT_CODE = "extra_result_code"
        const val EXTRA_DATA_INTENT = "extra_data_intent"
        const val EXTRA_WINDOWS_NAME = "extra_windows_name"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP_MIRRORING -> {
                Log.i(TAG, "Stop action triggered from notification")
                MirroringSessionCoordinator.stopSession("Đã dừng chia sẻ màn hình từ thông báo", notifyPeer = true)
                stopServiceCleanly()
                return START_NOT_STICKY
            }

            ACTION_START_MIRRORING -> {
                val windowsName = intent.getStringExtra(EXTRA_WINDOWS_NAME) ?: "Windows PC"
                val notification = buildNotification(isReconnecting = false, windowsName = windowsName)

                // Android 14+ requires startForeground() with MEDIA_PROJECTION type BEFORE calling getMediaProjection()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
                    )
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }

                val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
                @Suppress("DEPRECATION")
                val dataIntent: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(EXTRA_DATA_INTENT, Intent::class.java)
                } else {
                    intent.getParcelableExtra(EXTRA_DATA_INTENT)
                }

                if (resultCode != Activity.RESULT_OK || dataIntent == null) {
                    Log.e(TAG, "Missing valid MediaProjection result in service start intent")
                    stopServiceCleanly()
                    return START_NOT_STICKY
                }

                MirroringSessionCoordinator.onForegroundServiceReady(this, resultCode, dataIntent)
                return START_NOT_STICKY
            }

            else -> {
                stopServiceCleanly()
                return START_NOT_STICKY
            }
        }
    }

    fun updateNotification(isReconnecting: Boolean, windowsName: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification(isReconnecting, windowsName))
    }

    fun stopServiceCleanly() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Throwable) {
        }
        stopSelf()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Deliberately do NOT stop foreground mirroring when the user swipes the Companion UI from Recents.
        Log.i(TAG, "App task removed from Recents; keeping MirroringForegroundService active")
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        Log.i(TAG, "MirroringForegroundService destroyed")
        super.onDestroy()
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val existing = manager.getNotificationChannel(CHANNEL_ID)
            if (existing == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Chia sẻ màn hình Mirroring",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Hiển thị trạng thái khi Mirroring đang truyền màn hình sang máy tính Windows."
                    setShowBadge(false)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
                manager.createNotificationChannel(channel)
            }
        }
    }

    private fun buildNotification(isReconnecting: Boolean, windowsName: String): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPendingIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val stopIntent = Intent(this, MirroringForegroundService::class.java).apply {
            action = ACTION_STOP_MIRRORING
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val contentText = if (isReconnecting) {
            "Mất kết nối với $windowsName — đang chờ kết nối lại..."
        } else {
            "Màn hình đang được chia sẻ với $windowsName"
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_mirroring)
            .setContentTitle("Mirroring")
            .setContentText(contentText)
            .setStyle(NotificationCompat.BigTextStyle().bigText(contentText))
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(openPendingIntent)
            .addAction(0, "Dừng chia sẻ", stopPendingIntent)
            .build()
    }
}
