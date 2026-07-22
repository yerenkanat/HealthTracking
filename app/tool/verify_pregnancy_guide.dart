/// Pure-Dart verification of the pregnancy "what to expect / when to call"
/// guide. `dart run tool/verify_pregnancy_guide.dart`
///
/// As with the postpartum guide, the windows and the warning list are the
/// things that matter: a wrong window tells a woman a normal symptom is
/// arriving late, and an empty warning list is a safety failure.
library;

import 'dart:io';
import '../lib/domain/pregnancy_guide.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  // ---- The table is coherent ----
  {
    _chk('there are stage notes', stageNotes.length >= 10);
    _chk('every note has a non-empty id', stageNotes.every((n) => n.id.trim().isNotEmpty));
    _chk('no window is inside-out', stageNotes.every((n) => n.fromWeek <= n.toWeek));
    _chk('no window runs past term', stageNotes.every((n) => n.toWeek <= 40));
    _chk('no window starts before week four', stageNotes.every((n) => n.fromWeek >= 4));

    final ids = stageNotes.map((n) => n.id).toList();
    _chk('note ids are unique', ids.toSet().length == ids.length);

    for (final area in PregnancyArea.values) {
      _chk('the ${area.name} thread has at least one note',
          stageNotes.any((n) => n.area == area));
    }
  }

  // ---- Warning signs ----
  {
    _chk('the warning list is not empty', pregnancyWarnings.isNotEmpty);
    _chk('warning ids are unique', pregnancyWarnings.toSet().length == pregnancyWarnings.length);
    _chk('reduced movement is present', pregnancyWarnings.contains('movement'));
    _chk('bleeding is present', pregnancyWarnings.contains('bleeding'));
    _chk('the pre-eclampsia sign is present', pregnancyWarnings.contains('headache'));
    _chk('waters breaking early is present', pregnancyWarnings.contains('fluid'));
  }

  // ---- Which notes are "now" ----
  {
    // Week 8 (first trimester): nausea and tiredness, not the third-trimester
    // notes.
    final w8 = notesForWeek(8).map((n) => n.id).toSet();
    _chk('week 8 shows nausea', w8.contains('nausea'));
    _chk('week 8 does NOT show Braxton Hicks', !w8.contains('braxton'));
    _chk('week 8 does NOT show first movements yet', !w8.contains('first_movements'));

    // Week 20 (second trimester): first movements and energy, not early nausea.
    final w20 = notesForWeek(20).map((n) => n.id).toSet();
    _chk('week 20 shows first movements', w20.contains('first_movements'));
    _chk('week 20 shows returning energy', w20.contains('energy'));
    _chk('week 20 no longer shows deep first-trimester tiredness', !w20.contains('tired'));

    // Week 34 (third trimester): the late notes.
    final w34 = notesForWeek(34).map((n) => n.id).toSet();
    _chk('week 34 shows Braxton Hicks', w34.contains('braxton'));
    _chk('week 34 shows the movement-pattern note', w34.contains('movement_pattern'));
    _chk('week 34 shows the hospital bag', w34.contains('hospital_bag'));

    // Every week from 4 to term shows at least one note.
    _chk('every week 4..40 has at least one note',
        List.generate(37, (i) => notesForWeek(i + 4).isNotEmpty).every((x) => x));
  }

  // ---- The emotional thread spans the whole pregnancy ----
  {
    _chk('mood is addressed early', notesForWeek(6).any((n) => n.area == PregnancyArea.mind));
    _chk('and still late', notesForWeek(38).any((n) => n.area == PregnancyArea.mind));
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
