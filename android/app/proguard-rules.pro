# B2B2C Wallet ProGuard Rules

# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Rust FFI JNI
-keep class com.b2b2c.wallet.** { *; }
-keepclassmembers class * {
    native <methods>;
}

# 保留 Kotlin 协程
-keepclassmembernames class kotlinx.** {
    volatile <fields>;
}
