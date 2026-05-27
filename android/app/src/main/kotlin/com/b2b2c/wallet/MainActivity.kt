package com.b2b2c.wallet

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    
    private lateinit var methodChannel: WalletMethodChannel
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setupSecurityFlags()
        methodChannel = WalletMethodChannel(this)
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel.registerWith(flutterEngine)
    }
    
    private fun setupSecurityFlags() {
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }
    
    fun secureExit() {
        finishAffinity()
        System.exit(0)
    }
    
    fun handleSecurityThreat(threatType: String) {
        when (threatType) {
            "rooted" -> { /* 警告用户 */ }
            "debugger" -> secureExit()
            "hook" -> secureExit()
        }
    }
}
