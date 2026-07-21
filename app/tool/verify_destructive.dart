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
///
/// This list is an ALLOWLIST, which is the wrong default for a safety rule:
/// anything not written down is unguarded, and silently so. importJson —
/// which replaces the profile, every child, every zone and the whole history in
/// one call, the most destructive action in the app — was missing from it and
/// therefore shipped with no confirmation at all.
///
/// The sweep below now reads app_controller.dart directly and fails when a
/// method whose NAME reads destructive is absent here, so the list can no
/// longer quietly fall behind the code.
const _destructive = <String>[
  'removeGeofence',
  'removeChild',
  'removeDevice',
  'clearKickSessions',
  'clearContractionSessions',
  'removeMedication',
  'removeAppointment',
  'removeWeightEntry',
  'removeGrowth',
  'removeNewbornEvent',
  'clearAlerts',
  'removeAlert',
  'resetKicksFor',
  'importJson', // replaces EVERYTHING
  'resetApp',
];

/// Verbs that make a method a candidate for the list above.
final _destructiveVerb = RegExp(
    r'^(remove|delete|clear|reset|wipe|erase|purge|import|replaceAll|forget)',
    caseSensitive: false);

/// Controller methods whose names match a destructive verb but which do not
/// destroy USER data, with the reason. Being explicit here is the point: the
/// alternative is a silent omission, which is the failure this whole check
/// exists to prevent.
const _notActuallyDestructive = <String, String>{
  'clearEmergency': 'dismisses a transient alert view; no stored data is touched',
  'resetOnboarding': 'test-only helper, not reachable from the UI',
};

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
  // ---- The list must keep up with the controller ----
  // Read the controller and flag any public method whose name reads
  // destructive but which nobody has classified. An allowlist that is only
  // updated when someone remembers is not a safety guarantee; this makes
  // forgetting a build failure instead of a silent hole.
  final controller = File.fromUri(Platform.script.resolve('../lib/app/app_controller.dart'));
  final declared = <String>{};
  final methodDecl = RegExp(r'^\s{2}(?:Future<[^>]*>|void|bool|int|String|double)\s+(\w+)\s*\(');
  for (final line in controller.readAsLinesSync()) {
    final m = methodDecl.firstMatch(line);
    if (m == null) continue;
    final name = m.group(1)!;
    if (name.startsWith('_')) continue; // private: not reachable from the UI
    if (_destructiveVerb.hasMatch(name)) declared.add(name);
  }
  final unclassified =
      declared.where((m) => !_destructive.contains(m) && !_notActuallyDestructive.containsKey(m));
  _chk('every destructive-sounding controller method is classified '
      '(${declared.length} found${unclassified.isEmpty ? '' : ' — unclassified: ${unclassified.join(", ")}'})',
      unclassified.isEmpty);

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

  // Is the scan actually working? The old form of this check was
  // `callSites >= _destructive.length`, a proxy that assumed exactly one UI
  // call site per listed method — so adding a method that the UI does not call
  // made it fail for a reason that had nothing to do with the scan.
  _chk('the scan found destructive call sites ($callSites)', callSites > 0);

  // Sharper: every listed method should be reachable from the UI, or be
  // recorded here as not wired up. resetApp is the reason this matters — its
  // own doc comment describes a "Settings → Reset" flow that does not exist,
  // and nothing would have told us.
  const _notWired = <String, String>{
    'resetApp': 'defined but called from nowhere; the Settings reset flow was never built',
  };
  final uiText = uiDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.readAsStringSync())
      .join('\n');
  final missing = _destructive
      .where((m) => !RegExp('[.]$m\\b').hasMatch(uiText) && !_notWired.containsKey(m));
  _chk('every destructive method is reachable from the UI or recorded as unwired'
      '${missing.isEmpty ? '' : ' — missing: ${missing.join(", ")}'}', missing.isEmpty);
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
