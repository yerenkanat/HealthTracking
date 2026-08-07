/// Grouping for a phone number as it is typed.
///
/// The field took a bare run of digits — `7071112233` — on the one form every
/// single user fills. Eleven unbroken digits cannot be checked at a glance,
/// which is exactly what somebody does before tapping a button that decides
/// where her account lives; a transposed pair reads the same as a correct one.
///
/// Kazakh mobiles are said and written in a fixed shape: `707 111 22 33`.
/// Anything else falls back to groups of three, which is still far easier to
/// scan than a single run and never wrong for a shape we do not know.
///
/// PURE Dart apart from the formatter base class, so the grouping is testable
/// without a widget.
library;

import 'package:flutter/services.dart';

/// `707 111 22 33` for a +7 number, groups of three otherwise.
String groupPhone(String raw, {String dial = '+7'}) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';

  // +7 covers Kazakhstan and Russia, and both are written the same way.
  final groups = dial == '+7' ? const [3, 3, 2, 2] : const [3, 3, 3, 3];
  final out = StringBuffer();
  var i = 0;
  for (final size in groups) {
    if (i >= digits.length) break;
    if (i > 0) out.write(' ');
    out.write(digits.substring(i, (i + size).clamp(0, digits.length)));
    i += size;
  }
  // Anything past the shape we know: keep it rather than silently dropping
  // what she typed. A number that is too long is her problem to see, not ours
  // to hide.
  if (i < digits.length) out..write(' ')..write(digits.substring(i));
  return out.toString();
}

/// Applies [groupPhone] as she types.
///
/// The caret goes to the end on every edit. That is right for a phone number —
/// they are typed left to right in one go — and it avoids the class of bug
/// where inserting a space moves the caret backwards over it and the next digit
/// lands in the wrong group.
class PhoneGroupFormatter extends TextInputFormatter {
  final String dial;
  const PhoneGroupFormatter({this.dial = '+7'});

  @override
  TextEditingValue formatEditUpdate(TextEditingValue _, TextEditingValue next) {
    final text = groupPhone(next.text, dial: dial);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
