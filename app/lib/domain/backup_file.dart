/// Naming for the exported backup file.
///
/// Pure so the name can be tested without a filesystem; used by the settings
/// export flow. Verified by tool/verify_backupfile.dart.
library;

/// File name for a backup taken at [at].
///
/// Date-stamped rather than sequential so that several backups sort naturally
/// and the user can tell at a glance which is current — the question she will
/// actually be asking when restoring is "which one is recent", not "which one
/// is the fourth".
///
/// [seq] disambiguates two exports on the same day: without it the second
/// silently replaces the first, which is precisely the wrong behaviour for the
/// only copy of someone's health record.
String backupFileName(DateTime at, {int seq = 0}) {
  final y = at.year.toString().padLeft(4, '0');
  final m = at.month.toString().padLeft(2, '0');
  final d = at.day.toString().padLeft(2, '0');
  final suffix = seq > 0 ? '-$seq' : '';
  return 'ana-bala-backup-$y-$m-$d$suffix.json';
}

/// Whether [name] is one of ours, used when cleaning up old exports.
///
/// Anchored at both ends: a loose match would let a cleanup routine delete a
/// file that merely mentioned the app's name.
///
/// Both prefixes are recognised. New exports are `ana-bala-backup-…`, but
/// `umay-backup-…` files are sitting in people's Downloads folders from every
/// version before the rename, and they are the only copy of a health record
/// some of them have. Forgetting the old name would not delete those files —
/// it would do something quieter and worse: stop offering to restore them.
bool isBackupFileName(String name) =>
    RegExp(r'^(ana-bala|umay)-backup-\d{4}-\d{2}-\d{2}(-\d+)?\.json$').hasMatch(name);
