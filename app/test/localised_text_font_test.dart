/// A word can be drawn in two typefaces at once, and nothing looked.
///
/// On 2026-08-20 the language gate read every bundled font's cmap instead of
/// trusting the verifier, and found this:
///
///   Rubik            0/18 Kazakh letters missing
///   JetBrainsMono   12/18 missing (ә ғ қ ң ұ һ and their capitals)
///   Manrope         10/18 missing
///   Unbounded       16/18 missing
///
/// `week_detail_screen.dart` drew `bsize_length` — Kazakh «≈ {cm} см ұзындық» —
/// in JetBrainsMono. It never showed as tofu. `ThemeData.fontFamilyFallback` is
/// `[Rubik]`, and `TextStyle.merge` keeps that fallback when an inline style
/// sets only `fontFamily`, so ұ and қ were drawn FROM RUBIK: two proportional
/// glyphs inside a monospace word, in Kazakh only. Invisible in ru and en,
/// invisible in a widget test, and invisible to `tool/verify_l10n.dart`, which
/// checks RUBIK's cmap — the right question asked of the wrong artefact, the
/// same shape as `clinical_verdict_signals_test.dart` (a copy review that
/// hashed strings while the verdict was a colour).
///
/// So this file asks the question of the font that actually draws the string.
///
/// ─────────────────────────────────────────────────────────────────────────
/// WHAT IT CHECKS
///
/// For every place in `lib/` where a widget applies a NAMED FONT FAMILY to text
/// that comes out of the localisation table, every character of that string —
/// in ru, kk AND en — must exist in that family's own cmap. Coverage is read
/// from the .ttf files listed in pubspec.yaml, so a family added tomorrow is
/// covered without anyone registering it, and a font swapped for one with a
/// different repertoire is re-checked automatically.
///
/// A family covers a codepoint only when EVERY asset declared for it does.
/// JetBrainsMono ships Regular and Bold; a glyph in only one of them is still a
/// hole the moment the text is bold.
///
/// The fallback is deliberately NOT counted as a rescue. That the glyph arrives
/// from Rubik is the defect, not the mitigation — a word half-drawn from two
/// faces is what a reader sees.
///
/// ─────────────────────────────────────────────────────────────────────────
/// WHAT IT CANNOT SEE — read this before trusting a green run
///
/// It is a SOURCE-level guard, one file at a time. Precisely:
///
///  · A font family that is not a resolvable literal is skipped. `DsFont.x` IS
///    resolved, through the constants in design_system.dart; a computed one is
///    not. Today that leaves exactly two, both of them correct as written:
///    `span.cycleLength == null ? null : 'JetBrainsMono'` in
///    cycle_insights_screen.dart, which is mono only on the numeric branch, and
///    `DsFont.bodyFor(l.locale)` in the import sheet's `hintStyle`, which is
///    Rubik in Kazakh by construction. (`fontFamily: bodyFamily` in theme.dart
///    and `fontFamily: family` in design_system.dart are not sites at all —
///    they build a theme, not a widget, and design_system_test covers them.)
///  · Localised text that reaches a styled widget from ANOTHER FILE. Within one
///    file the text is followed properly — through local variables, through
///    file-local functions, and through the constructor call sites of the
///    widget that renders it, so `_Stat(value: l.duration(...))` two hundred
///    lines above its `Text` IS caught (that shape carried three of the six
///    defects below). Across a library boundary it is not: a shared widget
///    given its string by an importer is invisible here.
///  · A `TextStyle` held in a variable or a const and passed as `style:`. Only
///    an inline `fontFamily:` inside the styled widget's own call, and
///    `context.ds.mono()`, are recognised. `lib/` has no such const styles
///    today, which is the only reason this is a small hole.
///  · Text a widget builds from its own domain layer rather than from `L10n`,
///    and text the user types. `settings_screen.dart` prints a backup JSON in
///    mono; a Kazakh child's name inside it comes out of Rubik the same way,
///    and that is out of scope here.
///  · `TextField` is read for `hintText:` and `labelText:` only. Those two
///    inherit the field's `style:` through `InputDecorator._getInlineStyle`;
///    `errorText` and `helperText` do not, and flagging them would be wrong.
///
/// The floor assertions at the bottom exist because the failure mode of a
/// source guard is finding NOTHING and passing. If a refactor moves the app off
/// literal `fontFamily:` arguments, those fail and this file gets rewritten
/// rather than quietly retiring.
///
/// ─────────────────────────────────────────────────────────────────────────
/// WHAT IT FOUND, AND WHAT WAS DONE (2026-08-20)
///
/// Six sites, every one of them Kazakh-only. The gate reported one; this file
/// found the other five, which is the argument for deriving the rule from the
/// cmaps rather than fixing the site that was noticed:
///
///   week_detail_screen.dart      `bsize_length`    ұ қ   direct `l.t(...)`
///   sleep_card.dart              `l.duration()`    ғ     «7 сағ 40 мин»
///   settings_screen.dart         `set_import_hint` ұ қ ң a TextField hint
///   sleep_detail_screen.dart     `l.duration()`    ғ     via `_Stat.value`
///   health_dashboard_screen.dart `l.duration()`    ғ     via `_DigestStat`
///   newborn_log_screen.dart      `nb_dur_hm`       ғ     via `_StatTile`
///
/// The ruling was: a monospace face exists to keep columns of DIGITS aligned; a
/// word is not a column. Where a widget mixed a number with a localised unit,
/// the family was dropped rather than left half-drawn. The one place mono earns
/// its keep against prose — the JSON paste field — kept mono for the JSON and
/// gave the hint its own body-face style.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/l10n/l10n.dart';

import '../tool/font_cmap.dart';

// ---------------------------------------------------------------------------
// A very small Dart reader
//
// Enough of a lexer to know code from string from comment, and enough of a
// parser to know which call encloses which. Not the `analyzer` package: it is a
// transitive dependency here, not a declared one, and a guard that stops
// compiling on an unrelated `pub upgrade` is a guard that gets deleted.
// ---------------------------------------------------------------------------

const _kCode = 1;
const _kString = 2;
const _kComment = 0;

/// A bracketed run of source. For `(` the callee name is captured, which is
/// what makes "the nearest enclosing Text(...)" answerable.
class _Node {
  final String bracket;
  final String name;
  final int open;
  int close;
  final _Node? parent;
  _Node(this.bracket, this.name, this.open, this.parent) : close = -1;

  bool contains(int off) => off > open && (close < 0 || off < close);
}

class _Source {
  final String path;
  final String text;
  final List<int> kind;

  /// In the order their opening bracket appears.
  final List<_Node> nodes;
  final Map<int, _Node> byOpen;

  _Source(this.path, this.text, this.kind, this.nodes)
      : byOpen = {for (final n in nodes) n.open: n};

  bool isCode(int off) => off >= 0 && off < kind.length && kind[off] == _kCode;

  int lineAt(int off) {
    var line = 1;
    for (var i = 0; i < off && i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) line++;
    }
    return line;
  }

  /// The innermost node containing [off]. Nodes are stored in opening order, so
  /// walking back from [off] the first container found is the innermost one.
  _Node? _innermost(int off) {
    var lo = 0, hi = nodes.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (nodes[mid].open < off) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    for (var i = lo - 1; i >= 0; i--) {
      if (nodes[i].contains(off)) return nodes[i];
    }
    return null;
  }

  /// The innermost enclosing node that matches, walking out through parents.
  _Node? enclosing(int off, {String? bracket, bool Function(_Node)? where}) {
    for (var n = _innermost(off); n != null; n = n.parent) {
      if (bracket != null && n.bracket != bracket) continue;
      if (where != null && !where(n)) continue;
      return n;
    }
    return null;
  }

  /// [inner] is nested somewhere inside [outer].
  bool encloses(_Node outer, _Node inner) => outer.contains(inner.open);
}

bool _isIdChar(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    c == 0x5F ||
    c == 0x24;

_Source _read(String path, String src) {
  final n = src.length;
  final kind = List<int>.filled(n, _kCode);
  final nodes = <_Node>[];
  final stack = <_Node>[];

  // The string literal currently being read, if any. `'${l.t('k')}'` is code
  // inside a string inside code, so an interpolation parks its string frame and
  // takes it back at the '}' that closes it.
  final strings = <List<Object>>[]; // [quote, triple, raw]
  final parked = <List<Object>>[];
  final interpAtDepth = <int>[]; // node-stack depth each '${' was opened at

  var i = 0;
  while (i < n) {
    if (strings.isNotEmpty) {
      final top = strings.last;
      final q = top[0] as String;
      final triple = top[1] as bool;
      final raw = top[2] as bool;
      kind[i] = _kString;
      final c = src[i];
      if (!raw && src.codeUnitAt(i) == 0x5C) {
        // a backslash escape
        if (i + 1 < n) kind[i + 1] = _kString;
        i += 2;
        continue;
      }
      if (!raw && c == r'$' && i + 1 < n && src[i + 1] == '{') {
        kind[i] = _kString;
        kind[i + 1] = _kString;
        interpAtDepth.add(stack.length);
        parked.add(strings.removeLast());
        i += 2;
        continue;
      }
      if (triple && c == q && i + 2 < n && src[i + 1] == q && src[i + 2] == q) {
        kind[i + 1] = _kString;
        kind[i + 2] = _kString;
        strings.removeLast();
        i += 3;
        continue;
      }
      if (!triple && c == q) {
        strings.removeLast();
        i++;
        continue;
      }
      i++;
      continue;
    }

    // ---- code ----
    final c = src[i];
    if (c == '/' && i + 1 < n && src[i + 1] == '/') {
      while (i < n && src[i] != '\n') {
        kind[i] = _kComment;
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < n && src[i + 1] == '*') {
      while (i < n && !(src[i] == '*' && i + 1 < n && src[i + 1] == '/')) {
        kind[i] = _kComment;
        i++;
      }
      if (i < n) kind[i] = _kComment;
      if (i + 1 < n) kind[i + 1] = _kComment;
      i += 2;
      continue;
    }
    if (c == "'" || c == '"') {
      final triple =
          i + 2 < n && src[i + 1] == c && src[i + 2] == c;
      final raw = i > 0 && src[i - 1] == 'r' && (i < 2 || !_isIdChar(src.codeUnitAt(i - 2)));
      kind[i] = _kString;
      if (triple) {
        kind[i + 1] = _kString;
        kind[i + 2] = _kString;
      }
      strings.add([c, triple, raw]);
      i += triple ? 3 : 1;
      continue;
    }
    if (c == '}' && parked.isNotEmpty && interpAtDepth.isNotEmpty &&
        stack.length == interpAtDepth.last) {
      // closes a '${'
      kind[i] = _kString;
      interpAtDepth.removeLast();
      strings.add(parked.removeLast());
      i++;
      continue;
    }
    if (c == '(' || c == '{' || c == '[') {
      var name = '';
      if (c == '(') {
        var j = i - 1;
        while (j >= 0 && (src[j] == ' ' || src[j] == '\n' || src[j] == '\r' || src[j] == '\t')) {
          j--;
        }
        final e = j + 1;
        while (j >= 0 && (_isIdChar(src.codeUnitAt(j)) || src[j] == '.')) {
          j--;
        }
        name = src.substring(j + 1, e);
      }
      final node = _Node(c, name, i, stack.isEmpty ? null : stack.last);
      nodes.add(node);
      stack.add(node);
      i++;
      continue;
    }
    if (c == ')' || c == '}' || c == ']') {
      if (stack.isNotEmpty) {
        stack.removeLast().close = i;
      }
      i++;
      continue;
    }
    i++;
  }
  return _Source(path, src, kind, nodes);
}

// ---------------------------------------------------------------------------
// Arguments
// ---------------------------------------------------------------------------

class _Arg {
  final String? name;
  final int start;
  final int end;
  const _Arg(this.name, this.start, this.end);
}

/// Split a bracketed run into top-level arguments, as source ranges.
List<_Arg> _args(_Source s, _Node call) {
  if (call.close < 0) return const [];
  final out = <_Arg>[];
  var depth = 0;
  var start = call.open + 1;
  for (var i = call.open + 1; i < call.close; i++) {
    if (!s.isCode(i)) continue;
    final c = s.text[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') depth--;
    if (c == ',' && depth == 0) {
      out.add(_mkArg(s, start, i));
      start = i + 1;
    }
  }
  if (start < call.close) {
    final tail = _mkArg(s, start, call.close);
    if (s.text.substring(tail.start, tail.end).trim().isNotEmpty) out.add(tail);
  }
  return out;
}

final _namedArgRe = RegExp(r'^\s*(\w+)\s*:');

_Arg _mkArg(_Source s, int start, int end) {
  final raw = s.text.substring(start, end);
  final m = _namedArgRe.firstMatch(raw);
  if (m != null && s.isCode(start + m.end - 1)) {
    return _Arg(m.group(1), start + m.end, end);
  }
  return _Arg(null, start, end);
}

_Arg? _named(List<_Arg> args, String name) {
  for (final a in args) {
    if (a.name == name) return a;
  }
  return null;
}

List<_Arg> _positional(List<_Arg> args) =>
    args.where((a) => a.name == null).toList();

// ---------------------------------------------------------------------------
// The localisation table, and what each L10n helper can return
// ---------------------------------------------------------------------------

/// `l.t('key')`, and the receiverless `t('key')` that L10n's own helpers use.
final _tKeyRe = RegExp(r"\bt\(\s*'(\w+)'");

/// `t('metric_$metricKey')` — a family of keys behind one prefix. Only l10n.dart
/// writes these, and only for keys it composes itself.
final _tPrefixRe = RegExp(r"\bt\(\s*'(\w+?)\$");

/// A method on `L10n` called on the conventional receivers. `ml.` is
/// MaterialLocalizations and deliberately not in the list.
final _helperCallRe = RegExp(r'\b(?:l|loc|l10n)\.(\w+)\(');

final _identRe = RegExp(r'\b[_a-zA-Z]\w*\b');

// ---------------------------------------------------------------------------
// Definitions visible from a point in a file
// ---------------------------------------------------------------------------

final _varDefRe = RegExp(r'\b(?:final|const|var)\s[^=;{}()\n]*?(\w+)\s*=[^=]');
final _classRe = RegExp(r'\bclass\s+(\w+)');
final _fieldRe = RegExp(r'\bfinal\s+[\w<>?,\s]*?(\w+)\s*;');

const _notCallable = {
  'if', 'for', 'while', 'switch', 'catch', 'return', 'assert', 'else', 'super',
  'this', 'new', 'await', 'is', 'as', 'in', 'do', 'try',
};

class _Def {
  /// The `{`/`(` node the definition sits inside, or null at file level.
  final _Node? scope;
  final int start;
  final int end;
  const _Def(this.scope, this.start, this.end);
}

class _ClassInfo {
  final String name;
  final _Node body;
  final fields = <String>{};
  final positional = <String>[];
  final named = <String>{};
  _ClassInfo(this.name, this.body);
}

/// Everything one file declares, indexed for lookup by name.
class _FileIndex {
  final _Source s;
  final defs = <String, List<_Def>>{};
  final classes = <String, _ClassInfo>{};

  _FileIndex(this.s) {
    // variables and getters: `final x = <expr>;`
    for (final m in _varDefRe.allMatches(s.text)) {
      if (!s.isCode(m.start)) continue;
      final end = _statementEnd(s, m.end);
      if (end < 0) continue;
      defs.putIfAbsent(m.group(1)!, () => []).add(
            _Def(s.enclosing(m.start, bracket: '{'), m.end, end),
          );
    }
    // functions and methods: `name(...) => expr;` or `name(...) { … }`
    for (final node in s.nodes) {
      if (node.bracket != '(' || node.name.isEmpty || node.close < 0) continue;
      final name = node.name;
      if (name.contains('.') || _notCallable.contains(name)) continue;
      var j = node.close + 1;
      while (j < s.text.length && (s.text[j] == ' ' || s.text[j] == '\n' || s.text[j] == '\r' || s.text[j] == '\t')) {
        j++;
      }
      if (j + 1 < s.text.length && s.text[j] == '=' && s.text[j + 1] == '>') {
        final end = _statementEnd(s, j + 2);
        if (end < 0) continue;
        defs.putIfAbsent(name, () => []).add(
              _Def(s.enclosing(node.open, bracket: '{'), j + 2, end),
            );
      } else if (j < s.text.length && s.text[j] == '{') {
        final body = s.byOpen[j];
        if (body == null || body.bracket != '{' || body.close < 0) continue;
        defs.putIfAbsent(name, () => []).add(
              _Def(s.enclosing(node.open, bracket: '{'), body.open + 1, body.close),
            );
      }
    }
    // classes, their fields, and how their constructor names them
    for (final m in _classRe.allMatches(s.text)) {
      if (!s.isCode(m.start)) continue;
      _Node? body;
      for (final node in s.nodes) {
        if (node.bracket != '{' || node.open < m.end) continue;
        if (body == null || node.open < body.open) body = node;
      }
      if (body == null || body.close < 0) continue;
      final info = _ClassInfo(m.group(1)!, body);
      classes[info.name] = info;
      for (final f in _fieldRe.allMatches(s.text.substring(body.open, body.close))) {
        final abs = body.open + f.start;
        if (!s.isCode(abs)) continue;
        if (s.enclosing(abs, bracket: '{') != body) continue;
        info.fields.add(f.group(1)!);
      }
      // the constructor: a call node named after the class, inside its body
      for (final node in s.nodes) {
        if (node.bracket != '(' || node.name != info.name) continue;
        if (!body.contains(node.open)) continue;
        for (final a in _args(s, node)) {
          final raw = s.text.substring(a.start, a.end).trim();
          if (raw.startsWith('{') || raw.startsWith('[')) {
            for (final t in RegExp(r'this\.(\w+)').allMatches(raw)) {
              info.named.add(t.group(1)!);
            }
          } else {
            final t = RegExp(r'this\.(\w+)').firstMatch(raw);
            info.positional.add(t?.group(1) ?? '');
          }
        }
        break;
      }
    }
  }

  /// Definitions of [name] whose scope encloses [use].
  List<_Def> visible(String name, int use) {
    final all = defs[name];
    if (all == null) return const [];
    return all
        .where((d) => d.scope == null || d.scope!.contains(use))
        .toList();
  }

  _ClassInfo? classAt(int off) {
    _ClassInfo? best;
    for (final c in classes.values) {
      if (!c.body.contains(off)) continue;
      if (best == null || c.body.open > best.body.open) best = c;
    }
    return best;
  }
}

int _statementEnd(_Source s, int from) {
  var depth = 0;
  for (var i = from; i < s.text.length; i++) {
    if (!s.isCode(i)) continue;
    final c = s.text[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') {
      if (depth == 0) return i;
      depth--;
    }
    if (c == ';' && depth == 0) return i;
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Which l10n keys can reach a source range
// ---------------------------------------------------------------------------

class _Resolver {
  final _FileIndex index;
  final Map<String, Set<String>> helperKeys;
  final Set<String> allKeys;
  _Resolver(this.index, this.helperKeys, this.allKeys);

  Set<String> keysIn(int start, int end, {int depth = 0, Set<String>? seen}) {
    final s = index.s;
    if (depth > 5 || start < 0 || end <= start || end > s.text.length) {
      return const {};
    }
    final visited = seen ?? <String>{};
    final out = <String>{};
    final range = s.text.substring(start, end);

    for (final m in _tKeyRe.allMatches(range)) {
      if (!s.isCode(start + m.start)) continue;
      out.add(m.group(1)!);
    }
    for (final m in _tPrefixRe.allMatches(range)) {
      if (!s.isCode(start + m.start)) continue;
      final prefix = m.group(1)!;
      out.addAll(allKeys.where((k) => k.startsWith(prefix)));
    }
    for (final m in _helperCallRe.allMatches(range)) {
      if (!s.isCode(start + m.start)) continue;
      final keys = helperKeys[m.group(1)!];
      if (keys != null) out.addAll(keys);
    }

    for (final m in _identRe.allMatches(range)) {
      final abs = start + m.start;
      if (!s.isCode(abs)) continue;
      final name = m.group(0)!;
      if (_notCallable.contains(name)) continue;
      final tag = '$name@$abs';
      if (!visited.add(tag)) continue;

      final defs = index.visible(name, abs);
      if (defs.isNotEmpty) {
        for (final d in defs) {
          out.addAll(keysIn(d.start, d.end, depth: depth + 1, seen: visited));
        }
        continue;
      }
      // A field of the widget this code lives in: follow it to the call sites
      // that construct the widget, in this file.
      final cls = index.classAt(abs);
      if (cls != null && cls.fields.contains(name)) {
        out.addAll(_fromConstruction(cls, name, depth, visited));
      }
    }
    return out;
  }

  Set<String> _fromConstruction(
      _ClassInfo cls, String field, int depth, Set<String> visited) {
    final s = index.s;
    final out = <String>{};
    for (final node in s.nodes) {
      if (node.bracket != '(' || node.name != cls.name || node.close < 0) {
        continue;
      }
      if (cls.body.contains(node.open)) continue; // the declaration itself
      final args = _args(s, node);
      final named = _named(args, field);
      if (named != null) {
        out.addAll(keysIn(named.start, named.end, depth: depth + 1, seen: visited));
        continue;
      }
      final idx = cls.positional.indexOf(field);
      if (idx >= 0) {
        final pos = _positional(args);
        if (idx < pos.length) {
          out.addAll(
              keysIn(pos[idx].start, pos[idx].end, depth: depth + 1, seen: visited));
        }
      }
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// Where a font is applied, and to what
// ---------------------------------------------------------------------------

/// Widgets that put a `TextStyle` onto characters.
const _renderers = {
  'Text',
  'Text.rich',
  'SelectableText',
  'SelectableText.rich',
  'RichText',
  'TextSpan',
  'TextField',
  'TextFormField',
};

/// The arguments of each renderer that ARE the text.
///
/// [fontOffset] is where the family being asked about was written. It only
/// matters for `TextField`, which has more than one style slot: a family named
/// in `hintStyle:` draws the hint, and the field's own `style:` draws whatever
/// no slot has claimed.
List<_Arg> _contentArgs(_Source s, _Node call, {int? fontOffset}) {
  final args = _args(s, call);
  switch (call.name) {
    case 'Text':
    case 'Text.rich':
    case 'SelectableText':
    case 'SelectableText.rich':
      final pos = _positional(args);
      return pos.isEmpty ? const [] : [pos.first];
    case 'RichText':
    case 'TextSpan':
      final t = _named(args, 'text');
      return t == null ? const [] : [t];
    case 'TextField':
    case 'TextFormField':
      // Only the two decoration slots that inherit the field's own `style:`:
      // `InputDecorator` merges the field style into the hint and the floating
      // label, and into nothing else. `errorText` and `helperText` take their
      // family from the theme, and flagging them would be wrong.
      //
      // A slot that names its own family in `hintStyle:`/`labelStyle:` wins the
      // merge and is therefore no longer drawn in the field's face — that is
      // how the import sheet was fixed rather than de-monospaced, and the
      // exclusion below is what keeps this guard from re-reporting it.
      if (call.close < 0) return const [];
      final out = <_Arg>[];
      final slotStyles = <_Arg>[
        for (final slot in const ['hintStyle', 'labelStyle'])
          if (_slotArg(s, call, slot) case final a?) a,
      ];
      final inSomeSlotStyle = fontOffset != null &&
          slotStyles.any((a) => fontOffset > a.start && fontOffset < a.end);
      for (final slot in const ['hint', 'label']) {
        final textArg = _slotArg(s, call, '${slot}Text');
        if (textArg == null) continue;
        final styleArg = _slotArg(s, call, '${slot}Style');
        final thisSlotsStyle = styleArg != null &&
            fontOffset != null &&
            fontOffset > styleArg.start &&
            fontOffset < styleArg.end;
        if (thisSlotsStyle) {
          out.add(textArg);
          continue;
        }
        if (inSomeSlotStyle) continue; // drawn by a different slot's style
        final claimed = styleArg != null &&
            s.text.substring(styleArg.start, styleArg.end).contains('fontFamily');
        if (!claimed) out.add(textArg);
      }
      return out;
    default:
      return const [];
  }
}

/// The value of a decoration slot such as `hintText:` or `hintStyle:`, wherever
/// inside the field's call it was written.
_Arg? _slotArg(_Source s, _Node call, String slot) {
  final span = s.text.substring(call.open, call.close);
  for (final m in RegExp('\\b$slot\\s*:').allMatches(span)) {
    if (!s.isCode(call.open + m.start)) continue;
    final abs = call.open + m.end;
    final end = _argEnd(s, abs);
    if (end > abs) return _Arg(slot, abs, end);
  }
  return null;
}

int _argEnd(_Source s, int from) {
  var depth = 0;
  for (var i = from; i < s.text.length; i++) {
    if (!s.isCode(i)) continue;
    final c = s.text[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') {
      if (depth == 0) return i;
      depth--;
    }
    if (c == ',' && depth == 0) return i;
  }
  return -1;
}

/// One `fontFamily:` (or `ds.mono()`) applied to a renderer.
class _FontSite {
  final _Source s;
  final _Node renderer;
  final int offset;
  final String familyExpr;
  final String? family; // resolved literal, null when not statically knowable
  _FontSite(this.s, this.renderer, this.offset, this.familyExpr, this.family);

  String get where => '${s.path}:${s.lineAt(offset)}';
}

final _fontFamilyRe = RegExp(r'\bfontFamily\s*:');
final _dsMonoRe = RegExp(r'\bstyle\s*:[^,)]*\bds\.mono\s*\(');
final _dsConstRe = RegExp(r"static const (\w+) = '([^']+)'");

/// `DsFont.mono` → 'JetBrainsMono', read from the design system rather than
/// repeated here.
Map<String, String> _familyConstants(String designSystemSource) {
  final out = <String, String>{};
  for (final m in _dsConstRe.allMatches(designSystemSource)) {
    out['DsFont.${m.group(1)}'] = m.group(2)!;
  }
  return out;
}

/// A file worth opening at all.
bool _worthReading(String text) =>
    text.contains('fontFamily') || text.contains('ds.mono');

/// One file, read: every place a font is applied, and every l10n key that can
/// reach the characters it is applied to.
class _Scan {
  final _Source s;
  final _Resolver resolver;
  final sites = <_FontSite>[];

  _Scan(
    this.s, {
    required Map<String, Set<String>> helperKeys,
    required Set<String> allKeys,
    required Map<String, String> constants,
  }) : resolver = _Resolver(_FileIndex(s), helperKeys, allKeys) {
    void add(int offset, String expr) {
      final renderer = s.enclosing(offset,
          bracket: '(', where: (n) => _renderers.contains(n.name));
      if (renderer == null) return;
      final trimmed = expr.trim();
      String? family;
      if (RegExp(r"^'[^']+'$").hasMatch(trimmed)) {
        family = trimmed.substring(1, trimmed.length - 1);
      } else if (constants.containsKey(trimmed)) {
        family = constants[trimmed];
      }
      sites.add(_FontSite(s, renderer, offset, trimmed, family));
    }

    for (final m in _fontFamilyRe.allMatches(s.text)) {
      if (!s.isCode(m.start)) continue;
      final end = _argEnd(s, m.end);
      add(m.start, s.text.substring(m.end, end < 0 ? m.end : end));
    }
    for (final m in _dsMonoRe.allMatches(s.text)) {
      if (!s.isCode(m.start)) continue;
      add(m.start, 'DsFont.mono');
    }
  }

  /// A renderer nested inside a styled one inherits its family unless it names
  /// one of its own, so its text is drawn in the outer face too.
  List<_Arg> contentOf(_FontSite site) {
    final out = <_Arg>[
      ..._contentArgs(s, site.renderer, fontOffset: site.offset)
    ];
    for (final n in s.nodes) {
      if (n.bracket != '(' || !_renderers.contains(n.name)) continue;
      if (!s.encloses(site.renderer, n)) continue;
      final overridden = sites
          .any((o) => identical(o.renderer, n) && o.family != null);
      if (overridden) continue;
      out.addAll(_contentArgs(s, n));
    }
    return out;
  }

  Set<String> keysFor(_FontSite site) {
    final out = <String>{};
    for (final arg in contentOf(site)) {
      out.addAll(resolver.keysIn(arg.start, arg.end));
    }
    return out;
  }
}

// ---------------------------------------------------------------------------

String _u(int c) =>
    'U+${c.toRadixString(16).toUpperCase().padLeft(4, '0')}';

void main() {
  final appRoot = Directory.current;
  final coverage = bundledFontCoverage(appRoot);
  final l10nSource = _read('lib/l10n/l10n.dart',
      File('lib/l10n/l10n.dart').readAsStringSync());
  final constants = _familyConstants(
      File('lib/ui/design_system.dart').readAsStringSync());

  // Every catalogue key, in all three languages, with {placeholders} filled in
  // by a digit — the brace is not drawn, the number is.
  final catalogue = <String, Map<AppLocale, String>>{
    for (final k in allL10nKeys)
      k: {
        for (final loc in AppLocale.values)
          loc: L10n(loc).t(k).replaceAll(RegExp(r'\{\w+\}'), '0'),
      }
  };

  // What each helper on L10n can return, derived from its own body rather than
  // from a list somebody maintains: `duration` → dur_hm|dur_h|dur_m, and so on.
  final l10nIndex = _FileIndex(l10nSource);
  final helperKeys = <String, Set<String>>{};
  {
    final l10nClass = l10nIndex.classes['L10n'];
    final bootstrap = _Resolver(l10nIndex, const {}, catalogue.keys.toSet());
    if (l10nClass != null) {
      for (final entry in l10nIndex.defs.entries) {
        if (entry.key == 't') continue;
        for (final d in entry.value) {
          if (d.scope != l10nClass.body) continue;
          final keys = bootstrap.keysIn(d.start, d.end);
          if (keys.isNotEmpty) {
            helperKeys.putIfAbsent(entry.key, () => <String>{}).addAll(keys);
          }
        }
      }
    }
  }

  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.path.replaceAll(r'\', '/'))
      .toList()
    ..sort();

  final scans = <_Scan>[];
  for (final path in libFiles) {
    final text = File(path).readAsStringSync();
    if (!_worthReading(text)) continue;
    scans.add(_Scan(_read(path, text),
        helperKeys: helperKeys,
        allKeys: catalogue.keys.toSet(),
        constants: constants));
  }
  final sites = [for (final scan in scans) ...scan.sites];

  group('a localised string is drawn in a face that has its letters', () {
    test('every bundled family parses, and Rubik is the one that covers Kazakh',
        () {
      // The premise. If this fails, everything below is checking nothing.
      expect(coverage.keys, containsAll(<String>['Rubik', 'JetBrainsMono']),
          reason: 'pubspec.yaml no longer declares the families this guard '
              'was written against — re-read it before trusting a green run');
      for (final e in coverage.entries) {
        expect(e.value.length, greaterThan(300),
            reason: '${e.key} parsed to almost no codepoints — the cmap reader '
                'is broken, not the font');
      }
      final rubikMisses = kazakhOnlyLetters.runes
          .where((r) => !coverage['Rubik']!.contains(r))
          .map(String.fromCharCode)
          .join();
      expect(rubikMisses, isEmpty,
          reason: 'Rubik is the fallback for every family; it must carry the '
              'whole Kazakh alphabet');
      expect(
        kazakhOnlyLetters.runes
            .where((r) => !coverage['JetBrainsMono']!.contains(r))
            .length,
        greaterThan(0),
        reason: 'JetBrainsMono grew the Kazakh letters — good news, but this '
            'guard was written because it lacked them; re-read it',
      );
    });

    test('no widget applies a font to l10n text that font cannot draw', () {
      final failures = <String>[];

      for (final scan in scans) {
        for (final site in scan.sites) {
        final family = site.family;
        if (family == null) continue; // not statically knowable — see the header
        final glyphs = coverage[family];
        if (glyphs == null) continue; // 'monospace' etc: a system face

        final keys = scan.keysFor(site);

        for (final key in keys.toList()..sort()) {
          final row = catalogue[key];
          if (row == null) continue;
          for (final loc in AppLocale.values) {
            final text = row[loc]!;
            final missing = text.runes
                .where((r) => r != 0x0A && !glyphs.contains(r))
                .toSet();
            if (missing.isEmpty) continue;
            failures.add(
              '${site.where}  ${site.renderer.name}(…) fontFamily: '
              '${site.familyExpr}\n'
              "      key '$key' (${loc.name}): «$text»\n"
              '      $family has no '
              '${missing.map((c) => '${String.fromCharCode(c)} (${_u(c)})').join(', ')}\n'
              '      → those letters come from fontFamilyFallback (Rubik), so '
              'the word is drawn in two faces.',
            );
          }
        }
        }
      }

      expect(
        failures,
        isEmpty,
        reason: 'A font is being applied to text it cannot draw. The missing '
            'letters do not show as boxes — the theme fallback supplies them '
            'from Rubik — so this is only ever visible as a word rendered in '
            'two typefaces, and only in one language.\n\n'
            'The fix is to DROP the family from anything that renders a '
            'localised word. Monospace exists to line up columns of digits; a '
            'word is not a column. Where a widget mixes a number with a '
            'localised unit, split the two rather than leaving the unit half '
            'drawn.\n\n${failures.join('\n\n')}',
      );
    });

    test('the scan still finds the code it is meant to be reading', () {
      // The failure mode of a source guard is matching nothing and passing.
      final resolved = sites.where((s) => s.family != null).length;
      expect(sites.length, greaterThanOrEqualTo(50),
          reason: 'the font scan found only ${sites.length} styled widgets in '
              'lib/ — the reader is broken, or the app stopped setting '
              'fontFamily inline');
      expect(resolved, greaterThanOrEqualTo(50),
          reason: 'only $resolved of ${sites.length} families resolved to a '
              'literal; if the app has moved to computed families this guard '
              'needs rewriting, not relaxing');
      expect(helperKeys['duration'], contains('dur_hm'),
          reason: 'L10n.duration no longer resolves to its keys, so any font '
              'applied to l.duration(...) is no longer checked');
      expect(helperKeys.length, greaterThanOrEqualTo(5),
          reason: 'only ${helperKeys.length} L10n helpers resolved to keys — '
              'the derivation from l10n.dart has stopped working');
    });

    test('the reader follows every hop it claims to follow', () {
      // Checked against source written here rather than against the app, so
      // that fixing a screen cannot quietly retire a resolution path. Every
      // shape below carried one of the six live defects on 2026-08-20.
      final scan = _Scan(
        _read('fixture.dart', _fixture),
        helperKeys: helperKeys,
        allKeys: catalogue.keys.toSet(),
        constants: constants,
      );
      final found = <int, Set<String>>{
        for (final site in scan.sites)
          scan.s.lineAt(site.offset): scan.keysFor(site),
      };
      Set<String> at(int line) =>
          found[line] ??
          fail('no font site on fixture line $line — the reader stopped '
              'seeing one of the shapes this guard is built on');

      // 1. Through a widget field, to the constructor call that fills it, to a
      //    local variable, into an L10n helper, and out to that helper's keys.
      expect(at(7), containsAll(<String>['dur_hm', 'dur_h', 'dur_m']),
          reason: 'a duration reaching a styled Text through _Stat(value:) is '
              'no longer followed');
      // 2. …and NOT to the sibling Text that carries no font.
      expect(at(7), isNot(contains('sleep_deep')),
          reason: 'keys are leaking from an unstyled sibling into a styled '
              'widget — this guard would start crying wolf');
      // 3. A direct l.t(...) inside the styled call.
      expect(at(21), equals(<String>{'bsize_length'}));
      // 4. An l.t(...) inside a string interpolation.
      expect(at(24), equals(<String>{'unit_kg'}));
      // 5. A TextField hint, which inherits the field's own style.
      expect(at(26), contains('set_import_hint'));
      // 6. …unless the hint names its own family, in which case the hint
      //    belongs to THAT family and not to the field's.
      expect(at(30), isEmpty,
          reason: 'the field style is being credited with a hint that has its '
              'own family — the import sheet fix would be reported forever');
      expect(at(33), contains('set_import_hint'),
          reason: 'the hint is drawn in the family hintStyle names, and that '
              'family has to be checked too');
    });
  });
}

/// Source the reader is checked against. Line numbers are load-bearing; the
/// assertions name them.
const _fixture = r'''
class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value, style: const TextStyle(fontFamily: 'JetBrainsMono')),
        Text(label),
      ]);
}

class _Panel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final headline = l.duration(495);
    return Column(children: [
      _Stat(value: headline, label: l.t('sleep_deep')),
      Text(
        l.t('bsize_length', {'cm': '4.2'}),
        style: const TextStyle(fontFamily: 'JetBrainsMono'),
      ),
      Text('${l.t('unit_kg')} ok',
          style: const TextStyle(fontFamily: 'JetBrainsMono')),
      TextField(
        style: const TextStyle(fontFamily: 'JetBrainsMono'),
        decoration: InputDecoration(hintText: l.t('set_import_hint')),
      ),
      TextField(
        style: const TextStyle(fontFamily: 'JetBrainsMono'),
        decoration: InputDecoration(
          hintText: l.t('set_import_hint'),
          hintStyle: TextStyle(fontFamily: 'Rubik'),
        ),
      ),
    ]);
  }
}
''';
