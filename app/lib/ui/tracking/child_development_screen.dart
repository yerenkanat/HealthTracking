/// The child development calendar.
///
/// Answers "what is happening with my baby now, and what comes next" — the
/// question a parent asks constantly in the first two years.
///
/// The whole screen is built around one editorial decision: RANGES, never
/// dates. A parent whose 14-month-old is not walking should close this screen
/// reassured, not worried, because 14 months is squarely ordinary. The
/// "worth asking your doctor" section exists for the genuinely different case,
/// is separated from everything else, and is worded as a prompt to ask rather
/// than a finding.
library;

import 'package:flutter/material.dart';

import '../../domain/child_development.dart';
import '../../domain/family.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import 'teething_screen.dart';

class ChildDevelopmentScreen extends StatelessWidget {
  final ChildProfile child;
  final DateTime today;
  const ChildDevelopmentScreen({super.key, required this.child, required this.today});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final dob = child.dateOfBirth;

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Palette.bg,
        title: Text(l.t('dev_title')),
        actions: [
          if (dob != null)
            IconButton(
              icon: const Icon(Icons.sentiment_satisfied_outlined),
              tooltip: l.t('teeth_title'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => TeethingScreen(ageMonths: ageInMonths(dob, today)),
              )),
            ),
        ],
      ),
      body: dob == null
          ? _NoBirthdate(message: l.t('dev_no_birthdate'))
          : _Timeline(ageMonths: ageInMonths(dob, today), childName: child.name),
    );
  }
}

class _NoBirthdate extends StatelessWidget {
  final String message;
  const _NoBirthdate({required this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Palette.textDim, height: 1.4),
          ),
        ),
      );
}

class _Timeline extends StatelessWidget {
  final int ageMonths;
  final String childName;
  const _Timeline({required this.ageMonths, required this.childName});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final now = milestonesNow(ageMonths);
    final next = milestonesAhead(ageMonths, limit: 4);
    final ask = worthAsking(ageMonths);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _AgeHeader(ageMonths: ageMonths, name: childName),
        const SizedBox(height: 12),

        // Before the data, not after it. This sentence is how the whole screen
        // is meant to be read — that the ranges are where most children land
        // and not a schedule — and at the bottom of a long scroll it reached
        // nobody who needed it. A parent who is worried stops reading at the
        // first thing that worries her.
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
                child: Text(l.t('dev_spread'),
                    style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.45)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        if (now.isNotEmpty) ...[
          _SectionTitle(l.t('dev_now')),
          for (final m in now) _MilestoneCard(m: m, status: DevStatus.now),
          const SizedBox(height: 18),
        ],

        if (next.isNotEmpty) ...[
          _SectionTitle(l.t('dev_next')),
          for (final m in next) _MilestoneCard(m: m, status: DevStatus.ahead),
          const SizedBox(height: 18),
        ],

        // Last, and visually quietest. A parent who scrolls here is often
        // already worried; leading with it would make the screen a test.
        if (ask.isNotEmpty) ...[
          _SectionTitle(l.t('dev_ask')),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(l.t('dev_ask_note'),
                style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.4)),
          ),
          for (final m in ask) _MilestoneCard(m: m, status: DevStatus.worthAsking),
          const SizedBox(height: 18),
        ],

      ],
    );
  }
}

class _AgeHeader extends StatelessWidget {
  final int ageMonths;
  final String name;
  const _AgeHeader({required this.ageMonths, required this.name});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [Palette.lilac, Palette.blush],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.isEmpty ? l.t('dev_title') : name,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(l.childAge(ageMonths),
                    style: const TextStyle(color: Palette.textDim, fontSize: 13.5)),
              ],
            ),
          ),
          // Flexible, and capped. Unconstrained it overflowed the row by 39px
          // on a narrow phone — and a layout exception aborts the build, so
          // everything below this header silently stopped rendering.
          Flexible(
            child: Text(l.t('dev_sub'),
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Palette.textDim, fontSize: 11.5, height: 1.3)),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
        child: Text(text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
      );
}

/// One milestone.
///
/// The range is always on the card. A title alone — "First steps" — invites
/// the reading "this should have happened"; "9–15 months" cannot be read that
/// way.
class _MilestoneCard extends StatelessWidget {
  final DevMilestone m;
  final DevStatus status;
  const _MilestoneCard({required this.m, required this.status});

  Color get _accent => switch (status) {
        DevStatus.now => Palette.violet,
        DevStatus.worthAsking => Palette.amber,
        _ => Palette.textDim,
      };

  IconData get _icon => switch (m.area) {
        DevArea.motor => Icons.directions_run_rounded,
        DevArea.fine => Icons.back_hand_outlined,
        DevArea.speech => Icons.chat_bubble_outline_rounded,
        DevArea.social => Icons.favorite_outline_rounded,
        DevArea.teeth => Icons.sentiment_satisfied_alt_rounded,
        DevArea.feeding => Icons.restaurant_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final range = m.typicalFrom == m.typicalTo
        ? l.t('dev_age', {'n': m.typicalFrom})
        : l.t('dev_range', {'a': m.typicalFrom, 'b': m.typicalTo});

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status == DevStatus.now
              ? Palette.violet.withValues(alpha: 0.30)
              : Palette.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(_icon, size: 19, color: _accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(l.t('dev_${m.id}'),
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Text(range,
                        style: TextStyle(
                            color: _accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'JetBrainsMono')),
                  ],
                ),
                const SizedBox(height: 4),
                Text(l.t('dev_${m.id}_note'),
                    style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.4)),
                const SizedBox(height: 6),
                Text(l.t('dev_area_${m.area.name}'),
                    style: const TextStyle(color: Palette.textDim, fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
