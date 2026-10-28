# Flutter Wrapper and Core
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep JNI native methods and reflection
-keepclasseswithmembers class * {
    native <methods>;
}

# Network, Dio & OkHttp / Okio (İndirme Akışı Kalkanı)
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-keepattributes Signature
-keepattributes *Annotation*

# Galeri ve Medya Kaydı (photo_manager - İndirilenleri Galeriye Aktarma)
-keep class com.fluttercandies.photo_manager.** { *; }

# Güvenli Depolama & Keystore (flutter_secure_storage)
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Medya Oynatıcılar (Video Player & Audioplayers)
-keep class io.flutter.plugins.videoplayer.** { *; }
-keep class xyz.luan.audioplayers.** { *; }

# FFmpeg Kit (Video/MP3 Dönüştürme & Birleştirme)
-keep class com.arthenica.ffmpegkit.** { *; }

# Flutter Local Notifications (İndirme Bildirimleri)
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Google Mobile Ads (AdMob)
-keep public class com.google.android.gms.ads.** { public *; }
-keep public class com.google.ads.** { public *; }

# Firebase & Google Play Services
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# In-App Purchase & Google Play Billing
-keep class com.android.billingclient.** { *; }

# Desugaring ve Java 8+ API Uyumluluğu
-dontwarn java.lang.invoke.**
-dontwarn **Compat**
