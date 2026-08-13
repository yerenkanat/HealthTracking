/// Screen 05 — «Здоровье · браслета нет».
///
/// docs/CLAUDE-app-design.md: «карточка «Записывайте вручную» + 4 кнопки
/// (Давление, Вес, Сон, Пульс) → тёмная карточка «Сфотографировать тонометр» →
/// секция «Последние записи». **Апселла браслета здесь нет.**»
///
/// And §6: «Без устройства приложение полноценно. Экран «Здоровье без
/// браслета» — ручной дневник со сканом тонометра, а не заглушка с апселлом.»
///
/// What was here instead: a watch icon and «Наденьте браслет — и данные
/// появятся здесь». That is the upsell the spec forbids by name, on the screen
/// of a woman who has not bought one — and for most of them that is the
/// permanent state of this app, not a step on the way to buying.
///
/// The dark card is the one place in the light app where a dark surface is
/// allowed outside the night screens: it is the camera, and a camera control
/// reads as a viewfinder.
library;

import 'package:flutter/material.dart';

import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../theme.dart';

class NoBandCard extends StatelessWidget {
  final VoidCallback? onLogVitals;
  final VoidCallback? onLogWeight;
  final VoidCallback? onLogSleep;

  /// Opens the vitals sheet straight into its camera path. Null when there is
  /// no server to read the photo — the dark card then stays off the screen
  /// rather than offering something that cannot work.
  final VoidCallback? onScanMonitor;

  /// False when something directly above already offers «Вес» — the pregnancy
  /// hero's quick-action row does, wired to the same sheet, and two identical
  /// weight buttons one scroll apart is a duplicate control, not a shortcut.
  /// The spec's four entries are otherwise complete and stay that way.
  final bool showWeight;

  /// Whether she has already put readings in by hand.
  ///
  /// This card used to be shown only to someone with nothing logged, so its
  /// body could be an introduction: «приложение работает и без браслета». It
  /// now stays for as long as she has no band — which for most users is for
  /// ever — and that sentence is addressed to a decision she made months ago.
  /// It is not false, but it answers a question she has stopped asking, every
  /// day, above her own readings. Once there are readings, the true and useful
  /// sentence is where they went.
  ///
  /// The heading («Записывайте вручную») is true in both cases and does not
  /// change.
  final bool hasLoggedReadings;

  const NoBandCard({
    super.key,
    this.onLogVitals,
    this.onLogWeight,
    this.onLogSleep,
    this.onScanMonitor,
    this.showWeight = true,
    this.hasLoggedReadings = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DsCardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.t('noband_title'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15.5, color: Ds.ink)),
              const SizedBox(height: 4),
              Text(l.t(hasLoggedReadings ? 'noband_body_logging' : 'noband_body'),
                  style: const TextStyle(
                      color: Palette.textDim, fontSize: 13, height: 1.45)),
              const SizedBox(height: 14),
              // Four entries, the spec's own list. Pulse and blood pressure are
              // the same sheet — it takes both in one pass, and splitting them
              // into two journeys for one cuff reading is busywork.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Entry(
                      icon: Icons.favorite_outline,
                      label: l.t('noband_bp'),
                      onTap: onLogVitals),
                  _Entry(
                      icon: Icons.monitor_heart_outlined,
                      label: l.t('noband_pulse'),
                      onTap: onLogVitals),
                  if (showWeight)
                    _Entry(
                        icon: Icons.monitor_weight_outlined,
                        label: l.t('noband_weight'),
                        onTap: onLogWeight),
                  _Entry(
                      icon: Icons.bedtime_outlined,
                      label: l.t('noband_sleep'),
                      onTap: onLogSleep),
                ],
              ),
            ],
          ),
        ),
        if (onScanMonitor != null) ...[
          const SizedBox(height: 12),
          _ScanMonitorCard(onTap: onScanMonitor!),
        ],
      ],
    );
  }
}

/// One of the four manual-entry buttons.
class _Entry extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _Entry({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: DsShape.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Ds.pastelPink,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: Ds.coralText),
              const SizedBox(width: 7),
              Text(label,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: Ds.coralText)),
            ],
          ),
        ),
      ),
    );
  }
}

/// «Сфотографировать тонометр» — the dark card.
class _ScanMonitorCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ScanMonitorCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(DsShape.radiusCard),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Ds.ink,
            borderRadius: BorderRadius.circular(DsShape.radiusCard),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.photo_camera_outlined,
                    size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.t('noband_scan_title'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(l.t('noband_scan_body'),
                        style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: Colors.white.withValues(alpha: 0.78))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: Colors.white.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A plain white card at the system's radius — the shell the manual-entry block
/// sits in. Kept here rather than reaching for DsCard, which adds the ink
/// outline this block does not want next to the dark card below it.
class DsCardShell extends StatelessWidget {
  final Widget child;
  const DsCardShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(DsShape.radiusCard),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F3C1E2D),
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: child,
      );
}
