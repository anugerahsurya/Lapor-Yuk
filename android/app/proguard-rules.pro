# flutter_local_notifications serialises scheduled notifications with Gson;
# keep its model classes and generic signatures so they survive R8.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# Our MethodChannel host (JPEG encoder, EXIF, media scan).
-keep class com.anugerahsurya.laporyuk.MainActivity { *; }

# Flutter deferred components reference Play Core classes we don't ship.
-dontwarn com.google.android.play.core.**
