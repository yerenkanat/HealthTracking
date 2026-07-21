/// Verifies backup file naming.
library;

import '../lib/domain/backup_file.dart';

int _passed = 0, _failed = 0;

void _chk(String name, bool ok) {
  if (ok) {
    _passed++;
  } else {
    _failed++;
    print('  FAIL: $name');
  }
}

void main() {
  _chk('names by date', backupFileName(DateTime(2026, 7, 21)) == 'umay-backup-2026-07-21.json');
  _chk('pads single-digit months and days',
      backupFileName(DateTime(2026, 1, 5)) == 'umay-backup-2026-01-05.json');
  _chk('the first backup of a day has no suffix',
      !backupFileName(DateTime(2026, 7, 21), seq: 0).contains('-0.json'));
  _chk('a second backup the same day gets a distinct name',
      backupFileName(DateTime(2026, 7, 21), seq: 1) == 'umay-backup-2026-07-21-1.json');
  _chk('two same-day backups never collide',
      backupFileName(DateTime(2026, 7, 21)) != backupFileName(DateTime(2026, 7, 21), seq: 1));
  _chk('the time of day does not change the name',
      backupFileName(DateTime(2026, 7, 21, 3)) == backupFileName(DateTime(2026, 7, 21, 23)));

  // Dates sort as text, which is the point of this format: the share sheet and
  // the file manager both list by name.
  final names = [
    backupFileName(DateTime(2026, 1, 5)),
    backupFileName(DateTime(2025, 12, 31)),
    backupFileName(DateTime(2026, 7, 21)),
  ]..sort();
  _chk('names sort chronologically as plain text',
      names.first.contains('2025-12-31') && names.last.contains('2026-07-21'));

  // ---- recognition ----
  _chk('recognises its own names', isBackupFileName(backupFileName(DateTime(2026, 7, 21))));
  _chk('recognises a sequenced name', isBackupFileName('umay-backup-2026-07-21-2.json'));
  _chk('rejects a different app\'s file', !isBackupFileName('other-backup-2026-07-21.json'));
  _chk('rejects a prefix match', !isBackupFileName('not-umay-backup-2026-07-21.json'));
  _chk('rejects a suffix match', !isBackupFileName('umay-backup-2026-07-21.json.bak'));
  _chk('rejects a malformed date', !isBackupFileName('umay-backup-2026-7-1.json'));
  _chk('rejects the bare stem', !isBackupFileName('umay-backup.json'));

  print('$_passed passed, $_failed failed');
  if (_failed > 0) throw Exception('backup file verification failed');
}
