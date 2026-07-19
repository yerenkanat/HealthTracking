/// Pure-Dart verification of backup freshness.
/// `dart run tool/verify_backup.dart`
library;

import 'dart:io';
import '../lib/domain/backup_status.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  final now = DateTime(2026, 7, 20, 12);
  DateTime ago(int days) => now.subtract(Duration(days: days));

  _chk('never exported', backupFreshness(null, now) == BackupFreshness.never);
  _chk('today → fresh', backupFreshness(now, now) == BackupFreshness.fresh);
  _chk('13 days → fresh', backupFreshness(ago(13), now) == BackupFreshness.fresh);
  _chk('14 days → aging', backupFreshness(ago(14), now) == BackupFreshness.aging);
  _chk('29 days → aging', backupFreshness(ago(29), now) == BackupFreshness.aging);
  _chk('30 days → stale', backupFreshness(ago(30), now) == BackupFreshness.stale);
  _chk('90 days → stale', backupFreshness(ago(90), now) == BackupFreshness.stale);
  _chk('future timestamp → fresh', backupFreshness(now.add(const Duration(days: 2)), now) == BackupFreshness.fresh);

  _chk('nudge when never', shouldNudgeBackup(BackupFreshness.never));
  _chk('nudge when stale', shouldNudgeBackup(BackupFreshness.stale));
  _chk('no nudge when fresh', !shouldNudgeBackup(BackupFreshness.fresh));
  _chk('no nudge when aging', !shouldNudgeBackup(BackupFreshness.aging));

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
