/// The vaccination calendar.
///
/// Unlike the development calendar next door, this IS a schedule: the ages are
/// set by the health ministry, not by how a particular child is growing. So
/// the tone is different — "пора" rather than "most children around now", and
/// a passed date is worth catching up on rather than shrugging at.
///
/// What it deliberately does NOT do is claim to know what the child has had.
/// Nothing here reads a clinic record, and the disclaimer says so where it
/// cannot be missed.
///
/// The schedule and the catch-up window come from
/// data/vaccination_schedule_repository.dart, not from the compiled-in
/// constants: the back office can move a dose (admin frame 15) and until this
/// screen read the served copy, moving it meant a store rollout. The bundled
/// calendar is still the floor, so a phone with no signal draws the whole
/// screen — it is the repository, not this file, that decides which of the two
/// is in hand.
library;

import 'package:flutter/material.dart';

import '../../data/vaccination_schedule_repository.dart';
import '../../domain/child_development.dart' show ageInMonths;
import '../../domain/family.dart';
import '../../domain/vaccination.dart';
import '../../l10n/l10n.dart' show AppLocale, L10n;
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../theme.dart';

/// What to call a vaccine, and the line under it.
///
/// The back office's words win where somebody has written them, and the app's
/// own l10n fills in everywhere else. That order is the whole reason
/// [Vaccine.ru] and friends are nullable rather than empty strings: for a
/// shipped vaccine the app ships a Kazakh and an English name, and the server
/// carries a Russian one only — overwriting `vac_bcg` with a merge's fallback
/// would blank a row that reads perfectly well today.
///
/// A vaccine ADDED in the back office has no l10n key at all, so the server's
/// text is the only text it will ever have; the last fallback is its id, which
/// at least identifies the row instead of printing `vac_rota`.
///
/// ENGLISH IS NOT A FALLBACK POSITION FOR RUSSIAN. The back office writes ru
/// and kk and nothing else, so an English reader takes the l10n entry FIRST —
/// «БЦЖ» is not a better English label than «BCG» merely because it arrived
/// over the network. She only sees the Russian when this build has no word for
/// the vaccine at all, which is the case for one added in frame 15a.
String vaccineName(L10n l, Vaccine v) => _pick(
      l,
      own: l.locale == AppLocale.kk ? v.kk : (l.locale == AppLocale.ru ? v.ru : null),
      key: 'vac_${v.id}',
      last: v.ru ?? v.id,
    );

String vaccineNote(L10n l, Vaccine v) => _pick(
      l,
      own: l.locale == AppLocale.kk ? v.kkNote : (l.locale == AppLocale.ru ? v.ruNote : null),
      key: 'vac_${v.id}_note',
      last: v.ruNote ?? '',
    );

String _pick(L10n l, {required String? own, required String key, required String last}) {
  if (own != null && own.isNotEmpty) return own;
  return _l10nOr(l, key, last);
}

/// `l.t` answers with the key itself when there is no entry, which on screen is
/// the string `vac_rota`. That is a missing translation, not a label.
String _l10nOr(L10n l, String key, String fallback) {
  final s = l.t(key);
  return s == key ? fallback : s;
}

class VaccinationScreen extends StatelessWidget {
  final ChildProfile child;
  final DateTime today;

  /// The vaccine keys the parent has marked done, and a callback to toggle one.
  /// Her own record — see the disclaimer. Optional so the screen still renders
  /// read-only (e.g. in a preview) without a controller.
  final Set<String> doneKeys;
  final ValueChanged<String>? onToggleDone;

  const VaccinationScreen({
    super.key,
    required this.child,
    required this.today,
    this.doneKeys = const {},
    this.onToggleDone,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final dob = child.dateOfBirth;

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Palette.bg,
        title: Text(l.t('vac_title')),
      ),
      body: dob == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(l.t('dev_no_birthdate'),
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: Palette.textDim, height: 1.4)),
              ),
            )
          : _Schedule(
              ageMonths: ageInMonths(dob, today),
              // The date the OS reminder is armed for, or null when there is no
              // future visit to remind about. The card promises a reminder only
              // when one truly exists — the app schedules it the moment a child
              // with a birth date is added.
              //
              // Computed over the SERVED schedule: a dose moved in the back
              // office moves the next visit, and a reminder armed off the
              // compiled-in calendar would fire on a date this screen no longer
              // shows.
              reminderAt: nextVaccinationReminderAt(
                  dob: dob, now: today, schedule: servedVaccines()),
              done: doneKeys,
              onToggle: onToggleDone,
            ),
    );
  }
}

class _Schedule extends StatelessWidget {
  final int ageMonths;
  final DateTime? reminderAt;
  final Set<String> done;
  final ValueChanged<String>? onToggle;
  const _Schedule(
      {required this.ageMonths,
      required this.reminderAt,
      required this.done,
      required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    // The calendar and the window the back office actually published — or the
    // bundled ones, when this phone has never reached the server. Read ONCE per
    // build so every list below is computed against the same schedule.
    final schedule = servedVaccines();
    final window = servedDueWindowMonths();
    final due = vaccinesDue(ageMonths, schedule, window);
    final next = nextVisit(ageMonths, schedule);
    final untilNext = monthsUntilNextVisit(ageMonths, schedule);
    final byAge = scheduleByAge(schedule);
    // Passed but not recorded done — the real catch-up list. The window decides
    // where «пора» ends and «стоит наверстать» begins, so it has to be the
    // served one: the admin panel's coverage denominator is drawn on exactly
    // the same boundary, and staff chasing parents whose own screen still says
    // «пора» is what a one-month disagreement looks like.
    final catchUp = vaccinesToCatchUp(ageMonths, done, schedule, window);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // First, because it changes how everything below is read.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
            color: Palette.glass,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 17, color: Palette.textDim),
              const SizedBox(width: 10),
              Expanded(
                child: Text(l.t('vac_disclaimer'),
                    style: const TextStyle(
                        color: Palette.textDim, fontSize: 12.5, height: 1.45)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Worth catching up: past its age and not recorded done. Warm, because
        // this is the one thing on the screen that might need action.
        if (catchUp.isNotEmpty) ...[
          _Title(l.t('vac_catchup')),
          for (final v in catchUp)
            _VaccineRow(
                v: v,
                status: VaccineStatus.passed,
                catchUp: true,
                done: done.contains(vaccineKey(v)),
                onToggle: onToggle),
          const SizedBox(height: 16),
        ],

        if (due.isNotEmpty) ...[
          _Title(l.t('vac_due')),
          for (final v in due)
            _VaccineRow(
                v: v,
                status: VaccineStatus.due,
                done: done.contains(vaccineKey(v)),
                onToggle: onToggle),
          const SizedBox(height: 16),
        ],

        if (next.isNotEmpty) ...[
          _Title(
              '${l.t('vac_next')} · ${l.t('vac_in_months', {'n': untilNext})}'),
          for (final v in next)
            _VaccineRow(
                v: v,
                status: VaccineStatus.upcoming,
                done: done.contains(vaccineKey(v)),
                onToggle: onToggle),
          if (reminderAt != null) _ReminderNote(at: reminderAt!),
          const SizedBox(height: 16),
        ],

        if (next.isEmpty && due.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(l.t('vac_complete'),
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),

        // The whole calendar, so a parent can look ahead or check what was
        // scheduled when — the question they actually bring to a visit.
        _Title(l.t('vac_sub')),
        for (final entry in byAge.entries)
          _AgeGroup(
              months: entry.key,
              vaccines: entry.value,
              ageMonths: ageMonths,
              windowMonths: window,
              done: done,
              onToggle: onToggle),

        const SizedBox(height: 8),
        // Where this calendar came from, said out loud. A schedule changes by
        // order of the health ministry, and a parent using a two-year-old build
        // that has never reached the server should be able to find out that she
        // is reading a two-year-old table — which is exactly the state
        // `vac_revision` alone could not distinguish.
        Text(
            vaccinationScheduleIsFromServer()
                ? l.t('vac_source_server')
                : l.t('vac_revision', {'d': scheduleRevision}),
            style: const TextStyle(color: Palette.textDim, fontSize: 11.5)),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
      );
}

/// A quiet line under the next visit telling the parent the app will remind
/// them. Only shown when a reminder is actually armed, so it never promises
/// something that will not arrive.
class _ReminderNote extends StatelessWidget {
  final DateTime at;
  const _ReminderNote({required this.at});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final date = MaterialLocalizations.of(context).formatMediumDate(at);
    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 2, bottom: 2),
      child: Row(
        children: [
          const Icon(Icons.notifications_active_outlined,
              size: 15, color: Palette.textDim),
          const SizedBox(width: 8),
          Expanded(
            child: Text(l.t('vac_reminder_on', {'d': date}),
                style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

class _AgeGroup extends StatelessWidget {
  final int months;
  final List<Vaccine> vaccines;
  final int ageMonths;
  final int windowMonths;
  final Set<String> done;
  final ValueChanged<String>? onToggle;
  const _AgeGroup(
      {required this.months,
      required this.vaccines,
      required this.ageMonths,
      required this.windowMonths,
      required this.done,
      required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final label =
        months == 0 ? l.t('vac_at_birth') : l.t('vac_at_month', {'n': months});
    final reached = ageMonths >= months;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: reached ? Palette.violet : Palette.border,
              ),
            ),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: reached ? Palette.text : Palette.textDim,
                )),
          ]),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 17),
            child: Column(
              children: [
                for (final v in vaccines)
                  _VaccineRow(
                      v: v,
                      status: vaccineStatus(v, ageMonths, windowMonths),
                      compact: true,
                      done: done.contains(vaccineKey(v)),
                      onToggle: onToggle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VaccineRow extends StatelessWidget {
  final Vaccine v;
  final VaccineStatus status;
  final bool compact;
  final bool done;
  final bool catchUp;
  final ValueChanged<String>? onToggle;
  const _VaccineRow({
    required this.v,
    required this.status,
    this.compact = false,
    this.done = false,
    this.catchUp = false,
    this.onToggle,
  });

  Color get _accent => done
      ? Palette.teal
      : switch (status) {
          VaccineStatus.due => Palette.watch,
          VaccineStatus.upcoming => Palette.violet,
          VaccineStatus.passed => Palette.textDim,
        };

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final dose = v.dose == null ? '' : ' · ${l.t('vac_dose', {'n': v.dose})}';
    final key = vaccineKey(v);

    final borderColor = done
        ? Palette.teal.withValues(alpha: 0.35)
        : catchUp
            ? Palette.roseDeep.withValues(alpha: 0.35)
            : status == VaccineStatus.due
                ? Palette.watch.withValues(alpha: 0.35)
                : Palette.border;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(compact ? 11 : 14),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tappable done-mark, when the screen is interactive.
          if (onToggle != null)
            GestureDetector(
              onTap: () => onToggle!(key),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(right: 10, top: 1),
                child: Icon(
                  done
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: compact ? 18 : 21,
                  color: done ? Palette.teal : Palette.border,
                ),
              ),
            )
          else ...[
            Icon(Icons.vaccines_outlined,
                size: compact ? 17 : 19, color: _accent),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${vaccineName(l, v)}$dose',
                    style: TextStyle(
                        fontSize: compact ? 13.5 : 14.5,
                        fontWeight: FontWeight.w700,
                        color: done ? Palette.textDim : Palette.text,
                        decoration: done ? TextDecoration.lineThrough : null,
                        decorationColor: Palette.textDim)),
                if (!compact && vaccineNote(l, v).isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(vaccineNote(l, v),
                      style: const TextStyle(
                          color: Palette.textDim, fontSize: 12.5, height: 1.4)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
