/// How much of an advisory's approved body appears on the CARD, and how much
/// waits behind «Подробнее».
///
/// PURE Dart. No copy lives here — that is the whole design.
///
/// WHY THIS IS A COUNT AND NOT A SECOND STRING
///
/// `ADV_BP_ELEVATED_b` renders as eleven lines of solid body text on the screen
/// the app opens on, and a wall of text is read by nobody, which is a clinical
/// failure and not a cosmetic one. The obvious fix — author a short «summary»
/// key beside the long one — was REFUSED by the clinical gate on 2026-08-17:
/// three independently-authored claims per key per language is exactly how the
/// Kazakh of two approved cards came to concede something the Russian denied.
///
/// So there is ONE string per advisory, the reviewed one, and this file says
/// which of ITS SENTENCES the card shows. Every word on the card is a word the
/// gate approved, in the language it approved it in, and the detail screen
/// shows the same string whole.
///
/// WHY TWO COUNTS AND NOT ONE
///
/// docs/CLAUDE-app-design.md, ЧАСТЬ 4, rule 6: «Красные флаги отдельным блоком,
/// не под "читать дальше". 103 внизу.» The clinically load-bearing sentence of
/// these cards is the LAST one — «звоните 103 и назовите срок беременности» —
/// so a plain prefix would put exactly the sentence that must never be hidden
/// behind the control. The card therefore shows a subset that is deliberately
/// NOT contiguous:
///
///   [lead] sentences from the front   → the card, as body text
///   … the procedure in the middle …   → «Подробнее» only
///   [flags] sentences from the back   → the card, as the amber red-flag block
///
/// `flags: 0` gives a plain prefix, for a card with no red-flag tail.
///
/// WHAT IS DELIBERATELY EMPTY
///
/// [advisoryLayouts] is empty. Which sentences stay and which may move is a
/// clinical ruling, being made now; inventing the numbers here would ship a
/// split nobody approved and then have to be thrown away. Applying the gate's
/// verdict is one line per key in the map below — no code changes, no new
/// strings, no new l10n keys, and therefore nothing for
/// reviewed_medical_copy_test to be told about. Until then every card renders
/// its whole body exactly as it does today, which is the honest default: too
/// long, but complete.
library;

/// The card's share of one advisory body, in sentences.
class AdvisoryLayout {
  /// Sentences from the START of the body that appear on the card.
  final int lead;

  /// Sentences from the END of the body that appear on the card as their own
  /// amber block — the red flags and «звоните 103», which rule 6 forbids
  /// putting behind a "read more" control. Zero for a card with no such tail.
  final int flags;

  const AdvisoryLayout({required this.lead, this.flags = 0});

  int get onCard => lead + flags;
}

/// Keyed by the BODY key (`ADV_BP_ELEVATED_b`), not the advisory code: the body
/// is the string being divided, and naming it removes the guess about which of
/// the two strings a number refers to.
///
/// EMPTY UNTIL THE CLINICAL GATE RULES. See the library note above.
const advisoryLayouts = <String, AdvisoryLayout>{
  // Example of the shape a verdict takes, deliberately commented out rather
  // than guessed at:
  //
  //   'ADV_BP_ELEVATED_b': AdvisoryLayout(lead: 1, flags: 1),
  //
  // …which would put the first sentence on the card as body text, the last one
  // in the amber block below it, and the three in between behind «Подробнее».
};

/// The pieces of [body] that a card shows, and whether anything was held back.
class AdvisoryBodyParts {
  /// Body text on the card. Never empty: with no layout it is the whole body.
  final String lead;

  /// The red-flag block, or empty when this advisory has no flagged tail.
  final String flags;

  /// True when at least one sentence appears ONLY on the detail screen — i.e.
  /// when a «Подробнее» control has something to open.
  final bool hasMore;

  const AdvisoryBodyParts(
      {required this.lead, required this.flags, required this.hasMore});
}

/// Split [body] the way [layout] says, or hand back the whole thing.
///
/// Defensive about a layout that over-reaches its own string: a translator can
/// merge two sentences into one, and a card that then silently dropped the 103
/// line would be the worst possible failure of this mechanism. If the counts do
/// not fit, the WHOLE body goes on the card — long, complete, and visibly
/// wrong to anyone looking, rather than short and quietly missing a red flag.
/// advisory_layout_test.dart is what catches it before a user does.
AdvisoryBodyParts advisoryBodyParts(String body, AdvisoryLayout? layout) {
  if (layout == null || layout.lead < 1) {
    return AdvisoryBodyParts(lead: body, flags: '', hasMore: false);
  }
  final sentences = splitSentences(body);
  if (sentences.length <= layout.onCard) {
    return AdvisoryBodyParts(lead: body, flags: '', hasMore: false);
  }
  final lead = sentences.take(layout.lead).join(' ');
  final flags = layout.flags == 0
      ? ''
      : sentences.sublist(sentences.length - layout.flags).join(' ');
  return AdvisoryBodyParts(lead: lead, flags: flags, hasMore: true);
}

/// The same split applied to the DETAIL screen: everything, with the flagged
/// tail still in its own block so the red flags are not demoted to a paragraph
/// on the one screen that shows them in full.
///
/// `body` here is the complete string, so nothing is lost — the middle that the
/// card held back is in [lead].
AdvisoryBodyParts advisoryDetailParts(String body, AdvisoryLayout? layout) {
  if (layout == null || layout.flags == 0) {
    return AdvisoryBodyParts(lead: body, flags: '', hasMore: false);
  }
  final sentences = splitSentences(body);
  if (sentences.length <= layout.flags) {
    return AdvisoryBodyParts(lead: body, flags: '', hasMore: false);
  }
  return AdvisoryBodyParts(
    lead: sentences.sublist(0, sentences.length - layout.flags).join(' '),
    flags: sentences.sublist(sentences.length - layout.flags).join(' '),
    hasMore: false,
  );
}

/// Sentences of a reviewed medical string, in ru / kk / en.
///
/// Breaks after `.`, `!` or `?` followed by whitespace — but ONLY when what
/// comes next starts a sentence (a capital letter or a digit). That condition
/// is not fussiness: this catalogue writes units as «мм рт. ст.», and a naive
/// split would tear a unit off the number it belongs to and could put half of
/// it on a different screen from the other half. Decimal points («37.5») have
/// no space after them and are never a boundary.
///
/// Returns a single-element list for a string with no internal boundary, so a
/// caller always gets at least one sentence back.
List<String> splitSentences(String body) {
  final out = <String>[];
  final buf = StringBuffer();
  final runes = body.runes.toList();
  for (var i = 0; i < runes.length; i++) {
    final ch = String.fromCharCode(runes[i]);
    buf.write(ch);
    if (ch != '.' && ch != '!' && ch != '?') continue;
    // Trailing punctuation ends the last sentence.
    if (i == runes.length - 1) break;
    var j = i + 1;
    while (j < runes.length &&
        String.fromCharCode(runes[j]).trim().isEmpty) {
      j++;
    }
    if (j == i + 1) continue; // no space after it: «37.5», not a boundary
    if (j >= runes.length) break;
    final next = String.fromCharCode(runes[j]);
    final startsSentence =
        next.toUpperCase() == next && next.toLowerCase() != next ||
            RegExp(r'[0-9«"]').hasMatch(next);
    if (!startsSentence) continue; // «рт. ст.» — an abbreviation, not an end
    out.add(buf.toString().trim());
    buf.clear();
    i = j - 1;
  }
  final tail = buf.toString().trim();
  if (tail.isNotEmpty) out.add(tail);
  return out.isEmpty ? [body] : out;
}
