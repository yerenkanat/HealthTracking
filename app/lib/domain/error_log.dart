/// A bounded record of the errors this install has hit.
///
/// There is no crash reporting service wired up (and no keys for one yet), so
/// without this an error in production leaves no trace at all: the user sees
/// something wrong, and nobody can ask them what. A short on-device log gives
/// support something to ask for, and gives the diagnostics screen something to
/// show.
///
/// Pure Dart, tested by tool/verify_errorlog.dart.
library;

/// Where an error came from. Kept coarse — the value is in telling a build
/// failure apart from a background one, not in a taxonomy.
enum AppErrorSource {
  /// Thrown while building or laying out a widget.
  widget,

  /// Thrown outside the widget tree: a timer, a stream, an await with no catch.
  async,

  /// Raised deliberately by app code that could not complete something.
  app,
}

class AppErrorRecord {
  final DateTime at;
  final AppErrorSource source;
  final String message;

  /// The first frame or two of the stack, when there was one. Full traces are
  /// not kept: they are long, they are the part most likely to carry incidental
  /// data, and the top frames are what identifies the fault.
  final String? where;

  const AppErrorRecord({
    required this.at,
    required this.source,
    required this.message,
    this.where,
  });

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'source': source.name,
        'message': message,
        if (where != null) 'where': where,
      };
}

/// Longest message kept.
///
/// Errors quote the values that caused them, and in this app those values are
/// blood pressure readings and locations. Truncating is not cosmetic: the log
/// is included in the diagnostics the user can export and send on.
const int maxErrorMessageChars = 300;

class ErrorLog {
  /// How many records to keep. Small on purpose — this is a tail for support,
  /// not an audit trail, and an app failing in a loop must not be able to fill
  /// the disk with its own complaints.
  final int capacity;

  final List<AppErrorRecord> _records = [];

  ErrorLog({this.capacity = 20}) : assert(capacity > 0);

  /// Newest first.
  List<AppErrorRecord> get records => List.unmodifiable(_records.reversed.toList());

  int get length => _records.length;
  bool get isEmpty => _records.isEmpty;

  void add({
    required AppErrorSource source,
    required Object error,
    StackTrace? stack,
    required DateTime at,
  }) {
    _records.add(AppErrorRecord(
      at: at,
      source: source,
      message: _clip(error.toString()),
      where: _topFrames(stack),
    ));
    // Drop from the front, so the newest survive. An app that throws on every
    // frame would otherwise push the ORIGINAL failure — the only informative
    // one — out of a log that keeps the oldest.
    while (_records.length > capacity) {
      _records.removeAt(0);
    }
  }

  void clear() => _records.clear();

  List<Map<String, dynamic>> toJson() => [for (final r in records) r.toJson()];
}

String _clip(String s) {
  final oneLine = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (oneLine.length <= maxErrorMessageChars) return oneLine;
  return '${oneLine.substring(0, maxErrorMessageChars)}…';
}

/// The first two frames of [stack], joined.
///
/// Returns null rather than an empty string when there is nothing usable, so
/// callers can distinguish "no stack" from "a stack that said nothing".
String? _topFrames(StackTrace? stack, {int frames = 2}) {
  if (stack == null) return null;
  final lines = stack
      .toString()
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .take(frames)
      .toList();
  if (lines.isEmpty) return null;
  return _clip(lines.join(' · '));
}
