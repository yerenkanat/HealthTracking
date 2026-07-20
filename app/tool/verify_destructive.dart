/// Every destructive action must confirm before it runs.
/// `dart run tool/verify_destructive.dart`
///
/// The rule is that no delete, remove, unpair, reset or clear may happen from a
/// single tap — one mis-tap must never silently destroy data. It held almost
/// everywhere by hand, but "Clear" on the alerts feed was wired straight to the
/// controller, so one tap erased the whole safety history including every SOS.
///
/// Reviewing this by eye does not scale: the check is per-call-site, and a new
/// screen only has to forget once. So this scans the UI source instead — for
/// each destructive controller method, every place it is referenced in lib/ui
/// must have a confirmDestructive() in the same enclosing function.
library;

import 'dart:io';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

/// Controller methods that destroy user data.
const _destructive = <String>[
  'removeGeofence',
  'removeChild',
  'removeDevice',
  'clearKickSessions',
  'clearContractionSessions',
  'removeMedication',
  'removeAppointment',
  'removeWeightEntry',
  'clearAlerts',
  'removeAlert',
  'resetKicksFor',
];

/// Sites that are allowed to mention a destructive method without confirming
/// beside it, because the confirmation demonstrably lives elsewhere. Each entry
/// records WHERE, so a stale exemption is obvious on review.
const _exempt = <String, String>{
  'womens_health_screen.dart:onDelete':
      'handed to WeightHistoryScreen, which wraps it in its own _confirmDelete',
  'logging_drawer.dart:onResetKicks':
      '_KickCounter confirms with confirm_reset_kicks_title before invoking it',
  'womens_health_screen.dart:onClear':
      '_clearHistory shows the confirmation, then runs the passed callback',
  'day_log_sheet.dart:onResetKicks':
      'forwards to the drawer, which confirms in _KickCounter',
};

/// Handed straight to a tap callback — `onPressed: controller.clearAlerts` —
/// with no wrapper that could possibly confirm anything first. This is the
/// exact shape of the bug that prompted this runner, and it is always wrong.
final _wiredDirectly = RegExp(r'on(Pressed|Tap|LongPress|Changed)\s*:\s*[\w.]*\.\w+\s*[,)]');

/// The lines just before [index]. The guarded shape is always
/// `final ok = await confirmDestructive(...); if (ok) controller.remove...()`,
/// often nested deep in a widget tree with no tidy enclosing declaration to
/// anchor on, so a short lookback matches it without parsing Dart.
///
/// Kept deliberately tight. At 30 lines this found a confirmDestructive
/// belonging to a DIFFERENT handler earlier in the same file and passed the
/// unguarded "Clear all" button — a false negative that hid the very bug this
/// exists to catch.
String _lookback(List<String> lines, int index, {int span = 12}) =>
    lines.sublist((index - span).clamp(0, lines.length), index + 1).join('\n');

void main() {
  final uiDir = Directory.fromUri(Platform.script.resolve('../lib/ui'));
  final unguarded = <String>[];
  var callSites = 0;

  for (final f in uiDir.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    final name = f.path.replaceAll(r'\', '/').split('/').last;
    final lines = f.readAsLinesSync();

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith('//')) continue;
      for (final method in _destructive) {
        // A call (`.method(`) or a torn-off reference (`: c.method,`).
        if (!RegExp('[.]$method\\b').hasMatch(line)) continue;
        callSites++;

        final exemptKey = _exempt.keys.firstWhere(
          (k) => name == k.split(':').first && line.contains(k.split(':').last),
          orElse: () => '',
        );
        if (exemptKey.isNotEmpty) continue;

        if (_wiredDirectly.hasMatch(line)) {
          unguarded.add(
              'lib/ui/.../$name:${i + 1}  $method  —  wired straight to a tap callback: ${line.trim()}');
          continue;
        }
        if (!_lookback(lines, i).contains('confirmDestructive')) {
          unguarded.add('lib/ui/.../$name:${i + 1}  $method  —  ${line.trim()}');
        }
      }
    }
  }

  _chk('destructive call sites were found at all', callSites >= _destructive.length);
  if (unguarded.isNotEmpty) {
    print('\n  Destructive actions with no confirmDestructive() beside them:');
    for (final u in unguarded) {
      print('    $u');
    }
    print('  Guard it with confirmDestructive(), or add an entry to _exempt');
    print('  here saying where the confirmation actually lives.\n');
  }
  _chk('every destructive action confirms first (${unguarded.length} unguarded)',
      unguarded.isEmpty);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
