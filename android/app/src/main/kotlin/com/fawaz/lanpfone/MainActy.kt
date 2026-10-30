package com.fawaz.lanphone

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "lan_phone/native"
        private const val EXTRA_CALL_ID = "call_id"
        private const val EXTRA_CALL_ACTION = "call_action"
    }

    private var pendingCallAction: Map<String, String>? = null
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // ✅ السماح بعرض الواجهة فوق شاشة القفل
        showWhenLockedOn()
        // ✅ إبقاء الشاشة مضاءة أثناء المكالمة
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        // ✅ استقبال Intent من CallKit
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ✅ قناة للتواصل مع Dart
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialCallAction" -> {
                    result.success(pendingCallAction)
                    pendingCallAction = null
                }
                "setShowWhenLocked" -> {
                    val enable = call.argument<Boolean>("enable") ?: true
                    if (enable) showWhenLockedOn() else showWhenLockedOff()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // إذا كان هناك intent معلق، أرسله للـ Flutter بعد الجاهزية
        pendingCallAction?.let { action ->
            methodChannel?.invokeMethod("onCallActionFromNotification", action)
            pendingCallAction = null
        }
    }

    private fun handleIntent(intent: Intent?) {
        val callId = intent?.getStringExtra(EXTRA_CALL_ID)
        val action = intent?.getStringExtra(EXTRA_CALL_ACTION)

        if (callId != null && action != null) {
            val data = mapOf(
                "callId" to callId,
                "action" to action
            )
            if (methodChannel != null) {
                methodChannel?.invokeMethod("onCallActionFromNotification", data)
            } else {
                pendingCallAction = data
            }
        }
    }

    private fun showWhenLockedOn() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
    }

    private fun showWhenLockedOff() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(false)
            setTurnScreenOn(false)
        } else {
            @Suppress("DEPRECATION")
            window.clearFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
    }
}
