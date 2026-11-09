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
