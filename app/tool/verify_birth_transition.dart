/// Pure-Dart verification of the end-of-pregnancy fork.
/// `dart run tool/verify_birth_transition.dart`
library;

import 'dart:io';
import '../lib/domain/birth_transition.dart';
import '../lib/domain/child_development.dart' show ageInMonths;
import '../lib/domain/family.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  final today = DateTime(2026, 7, 22);

  // ---- A birth carries forward ----
  {
    final t = birthTransition(
      childId: 'c1',
      name: 'Сұлтан',
      birthDate: DateTime(2026, 7, 20),
      today: today,
    );
    _chk('a birth creates a child', t.createdChild);
    _chk('with the name given', t.child!.name == 'Сұлтан');
    _chk('and the birth date', t.child!.dateOfBirth == DateTime(2026, 7, 20));
    _chk('which the age calculation can immediately use',
        ageInMonths(t.child!.dateOfBirth!, today) == 0);
    _chk('the outcome says what happened', t.outcome == PregnancyOutcome.born);
  }
  {
    // A baby often has no name for days. Blocking the handover on one would
    // mean the app stops working during the week it is most wanted.
    final t = birthTransition(childId: 'c1', name: '   ', birthDate: today, today: today);
    _chk('an unnamed baby still gets a record', t.createdChild);
    _chk('and the blank name is stored blank, not as whitespace', t.child!.name.isEmpty);
  }
  {
    // A future birth date would give a negative age on every screen downstream,
    // and each of them would then have to defend against it.
    final t = birthTransition(
      childId: 'c1',
      name: 'A',
      birthDate: DateTime(2026, 12, 1),
      today: today,
    );
    _chk('a birth date in the future is capped at today',
        t.child!.dateOfBirth == DateTime(2026, 7, 22));
    _chk('so the age is never negative', ageInMonths(t.child!.dateOfBirth!, today) == 0);
  }
  {
    // Time of day must not survive into the record: the date is compared and
    // keyed everywhere, and 03:40 would make two same-day dates unequal.
    final t = birthTransition(
      childId: 'c1',
      name: 'A',
      birthDate: DateTime(2026, 7, 20, 3, 40),
      today: today,
    );
    final d = t.child!.dateOfBirth!;
    _chk('the time of day is dropped', d.hour == 0 && d.minute == 0);
  }

  // ---- Every other ending ----
  {
    _chk('an ending creates no child', !endedTransition.createdChild);
    _chk('and says so', endedTransition.outcome == PregnancyOutcome.ended);
    _chk('with nothing to follow up', endedTransition.child == null);
  }

  // ---- The picker default ----
  {
    // The due date is the closest guess the app holds, and babies are usually
    // registered within days of arriving.
    _chk('a passed due date is the default',
        defaultBirthDate(dueDate: DateTime(2026, 7, 18), today: today) == DateTime(2026, 7, 18));
    // But a birth cannot be in the future.
    _chk('a due date still ahead defaults to today',
        defaultBirthDate(dueDate: DateTime(2026, 9, 1), today: today) == today);
    _chk('no due date defaults to today',
        defaultBirthDate(dueDate: null, today: today) == today);
    _chk('the due date itself is fine on the day',
        defaultBirthDate(dueDate: today, today: today) == today);
  }

  // ---- The fork is a fork ----
  {
    // One door for two entirely different events was the defect. A birth must
    // never be reachable by the path that handles a loss, and the loss path
    // must never offer to create a child.
    _chk('the two outcomes are distinct',
        PregnancyOutcome.values.length == 2 &&
            endedTransition.outcome != PregnancyOutcome.born);
    final born = birthTransition(childId: 'c', name: 'A', birthDate: today, today: today);
    _chk('only one of them creates a child',
        born.createdChild && !endedTransition.createdChild);
  }

  // ---- The record is usable by the child modules ----
  {
    final t = birthTransition(childId: 'c1', name: 'A', birthDate: today, today: today);
    final c = t.child!;
    _chk('it has an id', c.id.isNotEmpty);
    _chk('it has a date of birth, which is what the calendars key on', c.hasDateOfBirth);
    _chk('it starts with no zones rather than inheriting any', c.geofences.isEmpty);
    _chk('and no tracker attached', c.tagId == null);
  }
  {
    final t = birthTransition(
        childId: 'c1', name: 'A', birthDate: today, today: today, gender: Gender.girl);
    _chk('gender is carried when it is known', t.child!.gender == Gender.girl);
    final unknown = birthTransition(childId: 'c2', name: 'B', birthDate: today, today: today);
    _chk('and left null when it is not', unknown.child!.gender == null);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
