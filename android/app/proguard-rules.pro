# ============================================================
# === إعدادات ProGuard لـ LanPhone ===
# ============================================================

# WebRTC — مهم جدًا
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# permission_handler
-keep class com.baseflow.permissionhandler.** { *; }

# flutter_local_notifications
-keep class com.dexterous.** { *; }

# sqflite
-keep class com.tekartik.sqflite.** { *; }

# image_picker
-keep class io.flutter.plugins.imagepicker.** { *; }

# file_picker
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# Kotlin
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**

# إبقاء أسماء الـ Models
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}
