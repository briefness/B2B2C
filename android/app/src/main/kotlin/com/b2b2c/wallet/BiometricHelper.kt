package com.b2b2c.wallet

import android.content.Context
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.lang.reflect.Method

class BiometricHelper(private val context: Context) {
    private val TAG = "BiometricHelper"
    
    fun isDeviceSecured(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            context.getSystemService(Context.KEYGUARD_SERVICE)?.let { kg ->
                val method = kg.javaClass.getMethod("isDeviceSecure")
                method.invoke(kg) as Boolean
            } ?: false
        } else {
            false
        }
    }
    
    fun checkRooted(): Boolean {
        val paths = arrayOf(
            "/system/app/Superuser.apk",
            "/sbin/su",
            "/system/bin/su",
            "/system/xbin/su",
            "/data/local/xbin/su",
            "/data/local/bin/su",
            "/system/sd/xbin/su",
            "/system/bin/failsafe/su",
            "/data/local/su"
        )
        
        return paths.any { path ->
            try {
                File(path).exists()
            } catch (e: Exception) {
                false
            }
        }
    }
    
    fun checkDebuggable(): Boolean {
        return (context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }
    
    /// 增强的 Hook 检测
    fun checkHooks(): Map<String, Any> {
        return mapOf(
            "frida" to checkFrida(),
            "xposed" to checkXposed(),
            "substrate" to checkSubstrate(),
            "substrateNative" to checkSubstrateNative(),
            "fridaServer" to checkFridaServer()
        )
    }
    
    /// 检查 Frida
    private fun checkFrida(): Boolean {
        // 方法1: 检查常见 Frida 文件
        val fridaPaths = arrayOf(
            "/data/local/tmp/frida-server",
            "/data/local/tmp/re.frida.server",
            "/data/local/tmp/frida",
            "/sdcard/frida-server",
            "/system/xbin/frida-server"
        )
        
        if (fridaPaths.any { File(it).exists() }) {
            Log.w(TAG, "Frida file detected")
            return true
        }
        
        // 方法2: 检查 /proc/self/maps 中的 Frida 库
        try {
            val mapsFile = File("/proc/self/maps")
            if (mapsFile.canRead()) {
                val content = mapsFile.readText()
                val fridaIndicators = arrayOf(
                    "frida",
                    "FridaGadget",
                    "re.frida.server",
                    "frida-agent"
                )
                if (fridaIndicators.any { content.contains(it, ignoreCase = true) }) {
                    Log.w(TAG, "Frida library in maps")
                    return true
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error reading maps: $e")
        }
        
        // 方法3: 检查已加载的库
        try {
            val libs = Class.forName("java.lang.System")
            val getProperty = libs.getMethod("getProperty", String::class.java)
            
            val properties = arrayOf(
                "frida.version",
                "frida.version.number"
            )
            
            for (prop in properties) {
                val value = getProperty.invoke(null, prop) as? String
                if (value != null && value.isNotEmpty()) {
                    Log.w(TAG, "Frida property detected: $prop = $value")
                    return true
                }
            }
        } catch (e: Exception) {
            // 忽略
        }
        
        return false
    }
    
    /// 检查 Xposed Framework
    private fun checkXposed(): Boolean {
        // 检查 Xposed 相关类
        val xposedClasses = arrayOf(
            "de.robv.android.xposed.XposedBridge",
            "de.robv.android.xposed.XposedHelpers",
            "de.robv.android.xposed.XposedInit"
        )
        
        for (className in xposedClasses) {
            try {
                Class.forName(className)
                Log.w(TAG, "Xposed class detected: $className")
                return true
            } catch (e: ClassNotFoundException) {
                // 未找到，继续检查
            }
        }
        
        // 检查 Xposed 模块
        val xposedModules = arrayOf(
            "/data/data/de.robv.android.xposed.installer",
            "/system/lib/libxposed_modules.so"
        )
        
        if (xposedModules.any { File(it).exists() }) {
            Log.w(TAG, "Xposed module path detected")
            return true
        }
        
        return false
    }
    
    /// 检查 Substrate Framework
    private fun checkSubstrate(): Boolean {
        val substrateClasses = arrayOf(
            "com.saurik.substrate.MS\$2",
            "com.saurik.substrate.MS\$Method"
        )
        
        for (className in substrateClasses) {
            try {
                Class.forName(className)
                Log.w(TAG, "Substrate class detected: $className")
                return true
            } catch (e: ClassNotFoundException) {
                // 未找到
            }
        }
        
        return false
    }
    
    /// 检查 Substrate Native 库
    private fun checkSubstrateNative(): Boolean {
        val substrateLibs = arrayOf(
            "libsubstrate.so",
            "libsubstrate-dvm.so",
            "libxhook.so",
            "libhookzz.so"
        )
        
        try {
            val mapsFile = File("/proc/self/maps")
            if (mapsFile.canRead()) {
                val content = mapsFile.readText()
                if (substrateLibs.any { content.contains(it) }) {
                    Log.w(TAG, "Substrate native lib detected")
                    return true
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking substrate libs: $e")
        }
        
        return false
    }
    
    /// 检查 Frida Server 端口
    private fun checkFridaServer(): Boolean {
        // 检查常见 Frida 端口
        val fridaPorts = arrayOf(27042, 27043)
        
        for (port in fridaPorts) {
            try {
                val process = Runtime.getRuntime().exec("netstat -an")
                val reader = BufferedReader(InputStreamReader(process.inputStream))
                var line: String?
                
                while (reader.readLine().also { line = it } != null) {
                    if (line!!.contains(":$port") && line!!.contains("LISTEN")) {
                        Log.w(TAG, "Frida server port detected: $port")
                        return true
                    }
                }
            } catch (e: Exception) {
                // 忽略
            }
        }
        
        return false
    }
    
    /// 综合安全检查
    fun performSecurityCheck(): Map<String, Any> {
        return mapOf(
            "isRooted" to checkRooted(),
            "isDebuggable" to checkDebuggable(),
            "isDeviceSecured" to isDeviceSecured(),
            "hookDetection" to checkHooks()
        )
    }
}
