# R8 keep rules for the release build.
#
# The Flutter Gradle plugin contributes the engine's own rules; these cover the
# plugins this app uses that look classes up reflectively, which R8 cannot see
# and therefore strips — producing a build that passes CI and crashes on a
# customer's phone the first time the feature is touched.

# Google Maps + location. The platform view is instantiated by name.
-keep class com.google.android.gms.maps.** { *; }
-keep interface com.google.android.gms.maps.** { *; }

# flutter_local_notifications: schedules are restored through reflection after
# a reboot, so the receivers must survive.
-keep class com.dexterous.** { *; }

# Firebase messaging: the service is named in the manifest and resolved at run
# time. Without this an SOS push arrives at a class that no longer exists.
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Kotlin metadata, used by several plugins' generated code.
-keep class kotlin.Metadata { *; }
