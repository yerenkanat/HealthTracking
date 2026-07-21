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
library;

import 'package:flutter/material.dart';

import '../../domain/child_development.dart' show ageInMonths;
import '../../domain/family.dart';
import '../../domain/vaccination.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

class VaccinationScreen extends StatelessWidget {
  final ChildProfile child;
  final DateTime today;
  const VaccinationScreen({super.key, required this.child, required this.today});

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
                    style: const TextStyle(color: Palette.textDim, height: 1.4)),
              ),
            )
          : _Schedule(ageMonths: ageInMonths(dob, today)),
    );
  }
}

class _Schedule extends StatelessWidget {
  final int ageMonths;
  const _Schedule({required this.ageMonths});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final due = vaccinesDue(ageMonths);
    final next = nextVisit(ageMonths);
    final untilNext = monthsUntilNextVisit(ageMonths);
    final byAge = scheduleByAge();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // First, because it changes how everything below is read.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
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
                    style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.45)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (due.isNotEmpty) ...[
          _Title(l.t('vac_due')),
          for (final v in due) _VaccineRow(v: v, status: VaccineStatus.due),
          const SizedBox(height: 16),
        ],

        if (next.isNotEmpty) ...[
          _Title('${l.t('vac_next')} · ${l.t('vac_in_months', {'n': untilNext})}'),
          for (final v in next) _VaccineRow(v: v, status: VaccineStatus.upcoming),
          const SizedBox(height: 16),
        ],

        if (next.isEmpty && due.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(l.t('vac_complete'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),

        // The whole calendar, so a parent can look ahead or check what was
        // scheduled when — the question they actually bring to a visit.
        _Title(l.t('vac_sub')),
        for (final entry in byAge.entries) _AgeGroup(months: entry.key, vaccines: entry.value, ageMonths: ageMonths),

        const SizedBox(height: 8),
        Text(l.t('vac_revision', {'d': scheduleRevision}),
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
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
      );
}

class _AgeGroup extends StatelessWidget {
  final int months;
  final List<Vaccine> vaccines;
  final int ageMonths;
  const _AgeGroup({required this.months, required this.vaccines, required this.ageMonths});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final label = months == 0 ? l.t('vac_at_birth') : l.t('vac_at_month', {'n': months});
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
                  _VaccineRow(v: v, status: vaccineStatus(v, ageMonths), compact: true),
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
  const _VaccineRow({required this.v, required this.status, this.compact = false});

  Color get _accent => switch (status) {
        VaccineStatus.due => Palette.watch,
        VaccineStatus.upcoming => Palette.violet,
        VaccineStatus.passed => Palette.textDim,
      };

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final dose = v.dose == null ? '' : ' · ${l.t('vac_dose', {'n': v.dose})}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(compact ? 11 : 14),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: status == VaccineStatus.due
              ? Palette.watch.withValues(alpha: 0.35)
              : Palette.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.vaccines_outlined, size: compact ? 17 : 19, color: _accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${l.t('vac_${v.id}')}$dose',
                    style: TextStyle(
                        fontSize: compact ? 13.5 : 14.5, fontWeight: FontWeight.w700)),
                if (!compact) ...[
                  const SizedBox(height: 3),
                  Text(l.t('vac_${v.id}_note'),
                      style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.4)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
