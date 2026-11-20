# Flutter & Kotlin rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Ignore missing optional Google Play Services and Play Core classes
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.**
-dontwarn com.google.android.gms.**
-dontwarn com.baseflow.geolocator.location.FusedLocationClient
-dontwarn com.baseflow.geolocator.**

# Local on-device LLM (llama.cpp) JNI and Pigeon bridge
-keep class com.write4me.llama_flutter_android.** { *; }
-keep class kotlin.jvm.functions.Function1
-keepclassmembers class * implements kotlin.jvm.functions.Function1 {
    public java.lang.Object invoke(java.lang.Object);
}
-keepclasseswithmembernames class * {
    native <methods>;
}
