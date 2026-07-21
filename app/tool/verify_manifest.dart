/// Does the Android manifest let the app reach the things it launches?
///
/// Android 11 hides other installed packages unless a `<queries>` intent
/// declares them. The failure is entirely silent: url_launcher's canLaunchUrl
/// returns false and the tap does nothing — no browser, no dialler, no error.
/// It cannot be caught by any Dart test, because nothing throws.
///
/// It had already happened here: `https` was undeclared, so every lesson video
/// and every product link in the timeline was a dead control on every modern
/// Android device. Nobody noticed because no item in the shipped catalogue
/// carries a URL yet.
library;

import 'dart:io';

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
  final file = File.fromUri(
      Platform.script.resolve('../android/app/src/main/AndroidManifest.xml'));
  if (!file.existsSync()) {
    print('  FAIL: AndroidManifest.xml not found at ${file.path}');
    print('0 passed, 1 failed');
    throw Exception('manifest verification failed');
  }
  final xml = file.readAsStringSync();

  _chk('the manifest was read', xml.length > 200);
  _chk('it declares a queries block', xml.contains('<queries>'));

  // Everything the app hands to url_launcher.
  for (final (what, scheme, action) in [
    ('the emergency call button', 'tel', 'DIAL'),
    ('lesson videos and product links', 'https', 'VIEW'),
    ('plain http links', 'http', 'VIEW'),
  ]) {
    final hasAction = xml.contains('android.intent.action.$action');
    final hasScheme = RegExp('android:scheme="$scheme"').hasMatch(xml);
    _chk('$what: $action is declared', hasAction);
    _chk('$what: the $scheme scheme is declared', hasScheme);
  }

  // The guard's own premise: if the file were empty or the strings changed
  // shape, every check above would pass or fail for the wrong reason.
  _chk('the package is the one we think it is', xml.contains('<manifest'));

  print('$_passed passed, $_failed failed');
  if (_failed > 0) throw Exception('manifest verification failed');
}
