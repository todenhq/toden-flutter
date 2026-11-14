# Applied to every app that uses toden_flutter, in its own R8 pass.
#
# WorkManager keeps its jobs in a Room database and Room finds the generated
# implementation by class name (WorkDatabase -> WorkDatabase_Impl). Under R8
# in a release build the two were renamed apart and the app died on launch:
# "Failed to create an instance of class androidx.work.impl.WorkDatabase".
-keep class androidx.work.impl.WorkDatabase { *; }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keepnames class * extends androidx.work.ListenableWorker
-keep class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}

# ML Kit (document detection, the MRZ and text reads, face detection) starts
# from component registrars it builds by reflection, through their no-argument
# constructors. R8 in a release build removed those constructors ("Could not
# instantiate com.google.mlkit.vision.text.internal.TextRegistrar ...
# NoSuchMethodException <init> []"), ML Kit never started, and every scan found
# nothing while the camera ran: no document detected, no MRZ, no face.
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
-keep class com.google.mlkit.**.*Registrar { <init>(); }
