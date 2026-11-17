package com.chuonghoai.mirroring.service

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.graphics.Path
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class MirroringAccessibilityService : AccessibilityService() {
    companion object {
        private const val TAG = "MirroringAccessibility"

        @Volatile
        var instance: MirroringAccessibilityService? = null
            private set

        fun isServiceEnabled(context: Context): Boolean {
            if (instance != null) return true
            return try {
                val enabledServices = Settings.Secure.getString(
                    context.contentResolver,
                    Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
                ) ?: return false
                val expected = ComponentName(context, MirroringAccessibilityService::class.java)
                    .flattenToString()
                enabledServices.split(':').any {
                    it.equals(expected, ignoreCase = true)
                }
            } catch (_: Throwable) {
                false
            }
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.i(TAG, "MirroringAccessibilityService connected")
        MirroringSessionCoordinator.onAccessibilityStateChanged(true)
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        instance = null
        Log.i(TAG, "MirroringAccessibilityService unbound")
        MirroringSessionCoordinator.onAccessibilityStateChanged(false)
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        instance = null
        MirroringSessionCoordinator.onAccessibilityStateChanged(false)
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // No event logging or background inspection needed; used solely for explicit remote input.
    }

    override fun onInterrupt() {
        // Required override.
    }

    fun performTouchGesture(points: List<Pair<Float, Float>>, durationMs: Long): Boolean {
        if (points.isEmpty()) return false
        val (screenW, screenH) = readScreenSize()
        if (screenW <= 0 || screenH <= 0) return false

        val clampedPoints = points.map { (nx, ny) ->
            val px = (nx.coerceIn(0f, 1f) * (screenW - 1)).coerceIn(0f, (screenW - 1).toFloat())
            val py = (ny.coerceIn(0f, 1f) * (screenH - 1)).coerceIn(0f, (screenH - 1).toFloat())
            px to py
        }

        val path = Path()
        path.moveTo(clampedPoints.first().first, clampedPoints.first().second)
        if (clampedPoints.size == 1) {
            // Slight 1px micro-line ensures Android treats tap strokes reliably across OEMs.
            val p = clampedPoints.first()
            path.lineTo((p.first + 0.5f).coerceAtMost((screenW - 1).toFloat()), p.second)
        } else {
            for (pt in clampedPoints.drop(1)) {
                path.lineTo(pt.first, pt.second)
            }
        }

        val safeDuration = durationMs.coerceIn(30L, 2000L)
        val stroke = GestureDescription.StrokeDescription(path, 0L, safeDuration)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()

        mainHandler.post {
            try {
                dispatchGesture(gesture, null, null)
            } catch (t: Throwable) {
                Log.w(TAG, "dispatchGesture failed: ${t.message}")
            }
        }
        return true
    }

    fun performNavigationAction(action: String): Boolean {
        return when (action) {
            "back" -> performGlobalAction(GLOBAL_ACTION_BACK)
            "home" -> performGlobalAction(GLOBAL_ACTION_HOME)
            "recents" -> performGlobalAction(GLOBAL_ACTION_RECENTS)
            "notifications" -> performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)
            "backspace" -> performBackspaceOnFocusedNode()
            "enter" -> performEnterOnFocusedNode()
            else -> false
        }
    }

    fun inputTextOnFocusedNode(text: String): Boolean {
        if (text.isEmpty()) return false
        mainHandler.post {
            val node = findEditableFocusedNode()
            if (node == null) {
                Log.d(TAG, "No focused input node for inputText")
                return@post
            }
            try {
                val existing = readNodeActualText(node)
                val updated = existing + text
                val args = Bundle().apply {
                    putCharSequence(
                        AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                        updated,
                    )
                }
                val setOk = node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
                if (setOk) {
                    moveCursorToEnd(node, updated.length)
                } else {
                    pasteFallback(node, text)
                }
            } catch (t: Throwable) {
                Log.w(TAG, "inputText failed: ${t.message}")
            } finally {
                @Suppress("DEPRECATION")
                node.recycle()
            }
        }
        return true
    }

    private fun performBackspaceOnFocusedNode(): Boolean {
        mainHandler.post {
            val node = findEditableFocusedNode() ?: return@post
            try {
                val existing = readNodeActualText(node)
                if (existing.isEmpty()) return@post
                val updated = existing.substring(0, existing.length - 1)
                val args = Bundle().apply {
                    putCharSequence(
                        AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                        updated,
                    )
                }
                if (node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)) {
                    moveCursorToEnd(node, updated.length)
                }
            } catch (t: Throwable) {
                Log.w(TAG, "backspace failed: ${t.message}")
            } finally {
                @Suppress("DEPRECATION")
                node.recycle()
            }
        }
        return true
    }

    private fun performEnterOnFocusedNode(): Boolean {
        mainHandler.post {
            val node = findEditableFocusedNode() ?: return@post
            try {
                var handled = false
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    handled = node.performAction(
                        AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id,
                    )
                }
                if (!handled && node.isMultiLine) {
                    val existing = readNodeActualText(node)
                    val updated = "$existing\n"
                    val args = Bundle().apply {
                        putCharSequence(
                            AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                            updated,
                        )
                    }
                    if (node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)) {
                        moveCursorToEnd(node, updated.length)
                    }
                }
            } catch (t: Throwable) {
                Log.w(TAG, "enter failed: ${t.message}")
            } finally {
                @Suppress("DEPRECATION")
                node.recycle()
            }
        }
        return true
    }

    private fun findEditableFocusedNode(): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (focused != null && focused.isEditable) {
            return focused
        }
        @Suppress("DEPRECATION")
        focused?.recycle()
        return null
    }

    private fun readNodeActualText(node: AccessibilityNodeInfo): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && node.isShowingHintText) {
            return ""
        }
        return node.text?.toString() ?: ""
    }

    private fun moveCursorToEnd(node: AccessibilityNodeInfo, endPos: Int) {
        val selArgs = Bundle().apply {
            putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, endPos)
            putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, endPos)
        }
        node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, selArgs)
    }

    private fun pasteFallback(node: AccessibilityNodeInfo, text: String) {
        try {
            val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            cm.setPrimaryClip(ClipData.newPlainText("MirroringInput", text))
            node.performAction(AccessibilityNodeInfo.ACTION_PASTE)
        } catch (_: Throwable) {
        }
    }

    @Suppress("DEPRECATION")
    private fun readScreenSize(): Pair<Int, Int> {
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = wm.maximumWindowMetrics.bounds
            bounds.width() to bounds.height()
        } else {
            val metrics = DisplayMetrics()
            wm.defaultDisplay.getRealMetrics(metrics)
            metrics.widthPixels to metrics.heightPixels
        }
    }
}
