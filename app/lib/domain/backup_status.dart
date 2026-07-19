/// Backup freshness — how long ago the user last exported their data, and
/// whether that's stale enough to nudge about. PURE Dart → unit-testable via
/// verify_backup.dart. Export is the app's only backup path, so "last export"
/// IS "last backup".
library;

/// How fresh the last backup is.
enum BackupFreshness { never, fresh, aging, stale }

/// Days after which a backup starts feeling old / clearly stale.
const int backupAgingDays = 14;
const int backupStaleDays = 30;

/// Classify the backup age. Null [lastExportAt] → never backed up. A future
/// timestamp (clock skew) is treated as fresh.
BackupFreshness backupFreshness(DateTime? lastExportAt, DateTime now) {
  if (lastExportAt == null) return BackupFreshness.never;
  final days = now.difference(lastExportAt).inDays;
  if (days < backupAgingDays) return BackupFreshness.fresh;
  if (days < backupStaleDays) return BackupFreshness.aging;
  return BackupFreshness.stale;
}

/// Whether the UI should actively nudge the user to back up.
bool shouldNudgeBackup(BackupFreshness f) =>
    f == BackupFreshness.never || f == BackupFreshness.stale;
