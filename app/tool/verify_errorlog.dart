/// Verifies the on-device error log: bounds, ordering, and what it keeps.
library;

import '../lib/domain/error_log.dart';

int _passed = 0, _failed = 0;

void _chk(String name, bool ok) {
  if (ok) {
    _passed++;
  } else {
    _failed++;
    print('  FAIL: $name');
  }
}

DateTime _at(int minute) => DateTime.utc(2026, 7, 21, 12, minute);

void main() {
  // ---- bounds ----
  final log = ErrorLog(capacity: 3);
  for (var i = 0; i < 10; i++) {
    log.add(source: AppErrorSource.app, error: 'error $i', at: _at(i));
  }
  _chk('never exceeds capacity', log.length == 3);
  _chk('keeps the NEWEST, not the oldest', log.records.first.message == 'error 9');
  _chk('drops the oldest', !log.records.any((r) => r.message == 'error 0'));

  // An app failing on every frame is the case this bound exists for; the log
  // must stay small no matter how hard it is hit.
  final hammered = ErrorLog(capacity: 5);
  for (var i = 0; i < 5000; i++) {
    hammered.add(source: AppErrorSource.widget, error: 'boom $i', at: _at(0));
  }
  _chk('a failure loop cannot grow the log', hammered.length == 5);

  // ---- ordering ----
  final ordered = ErrorLog();
  ordered.add(source: AppErrorSource.app, error: 'first', at: _at(1));
  ordered.add(source: AppErrorSource.app, error: 'second', at: _at(2));
  _chk('newest first', ordered.records.first.message == 'second');
  _chk('oldest last', ordered.records.last.message == 'first');

  // ---- truncation ----
  // Errors quote the values that caused them, and here those values are blood
  // pressure readings. The log can be exported, so an unbounded message is
  // health data leaving the device by accident.
  final long = ErrorLog();
  long.add(source: AppErrorSource.app, error: 'x' * 5000, at: _at(0));
  _chk('a huge message is clipped',
      long.records.first.message.length <= maxErrorMessageChars + 1);
  _chk('clipping is marked', long.records.first.message.endsWith('…'));

  final short = ErrorLog();
  short.add(source: AppErrorSource.app, error: 'brief', at: _at(0));
  _chk('a short message is untouched', short.records.first.message == 'brief');

  // ---- newlines ----
  final multi = ErrorLog();
  multi.add(source: AppErrorSource.app, error: 'line one\n  line two\n\nline three', at: _at(0));
  _chk('messages collapse to one line',
      !multi.records.first.message.contains('\n'));

  // ---- stacks ----
  final withStack = ErrorLog();
  withStack.add(
    source: AppErrorSource.widget,
    error: 'boom',
    stack: StackTrace.fromString('#0      foo (file:///a.dart:1:2)\n'
        '#1      bar (file:///b.dart:3:4)\n'
        '#2      baz (file:///c.dart:5:6)'),
    at: _at(0),
  );
  final where = withStack.records.first.where;
  _chk('keeps the top frames', where != null && where.contains('foo'));
  _chk('keeps the second frame', where != null && where.contains('bar'));
  _chk('drops the rest of the trace', where != null && !where.contains('baz'));

  final noStack = ErrorLog();
  noStack.add(source: AppErrorSource.async, error: 'boom', at: _at(0));
  _chk('no stack means null, not an empty string', noStack.records.first.where == null);

  final emptyStack = ErrorLog();
  emptyStack.add(source: AppErrorSource.async, error: 'boom', stack: StackTrace.fromString('   \n  '), at: _at(0));
  _chk('a blank stack is null too', emptyStack.records.first.where == null);

  // ---- shape ----
  final json = ordered.toJson();
  _chk('serializes every record', json.length == 2);
  _chk('json carries the source', json.first['source'] == 'app');
  _chk('json carries the time', json.first['at'] == _at(2).toIso8601String());
  _chk('json omits an absent stack', !json.first.containsKey('where'));

  // ---- clear ----
  ordered.clear();
  _chk('clear empties the log', ordered.isEmpty && ordered.length == 0);

  // ---- sources are distinguishable ----
  final sources = ErrorLog();
  for (final s in AppErrorSource.values) {
    sources.add(source: s, error: 'e', at: _at(0));
  }
  _chk('every source round-trips',
      sources.records.map((r) => r.source).toSet().length == AppErrorSource.values.length);

  print('$_passed passed, $_failed failed');
  if (_failed > 0) throw Exception('error log verification failed');
}
