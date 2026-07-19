/// HealthDashboardView — the premium, reassuring health home. Top-to-bottom:
///   1. a "peace of mind" master banner that summarizes everything in one warm line
///      (green when steady, warm amber when something is worth watching),
///   2. a 2×2 grid of soft metric cards — heart rate, blood oxygen, a MERGED
///      blood-pressure card ("138 / 77 mmHg"), and temperature — each with a
///      smoothed spline chart and a distinct icon/colour,
///   3. a friendly advisor entry prompt that opens the data-driven advisor.
///
/// Pure presentation over the verified health_series + health_advisor logic.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../domain/appointment.dart';
import '../../domain/health_advisor.dart';
import '../../domain/health_series.dart';
import '../../domain/setup_checklist.dart';
import '../../domain/sleep.dart';
import '../../domain/weekly_digest.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/glass.dart';
import 'health_summary.dart';
import 'metric_detail_screen.dart';
import 'sleep_card.dart';
import 'sparkline.dart';
import 'water_card.dart';

class MetricSpec {
  final String key;
  final String unit;
  final IconData icon;
  final Gradient gradient;
  final Color color;
  const MetricSpec(this.key, this.unit, this.icon, this.gradient, this.color);
}

const _hrColor = Color(0xFFFF5A7A);
const _tempA = Color(0xFFF59E0B);
const _tempB = Color(0xFFFBBF24);

// The three single-value metrics shown as uniform grid cards; blood pressure is
// rendered separately (two values merged into one card).
const _specs = <MetricSpec>[
  MetricSpec('hr', 'bpm', Icons.favorite_rounded, LinearGradient(colors: [_hrColor, Palette.pink]), _hrColor),
  MetricSpec('spo2', '%', Icons.air_rounded, Palette.tealBlue, Palette.teal),
  MetricSpec('temp', '°C', Icons.thermostat_rounded, LinearGradient(colors: [_tempA, _tempB]), _tempA),
];

class HealthDashboardView extends StatelessWidget {
  final List<HealthSample> samples;
  final List<SleepSummary> sleepNights;
  final String greetingName;
  final String? photoPath;
  final AppLocale? currentLocale;
  final void Function(AppLocale)? onLocaleChange;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenAdvisor;
  final String summaryStatus; // pregnancy/cycle status line for the shared summary
  // Quick status chip: cycle day / pregnancy week (empty = hidden).
  final String statusChip;
  final bool statusChipPregnancy;
  final bool statusChipLate; // period overdue → amber, not routine rose
  final VoidCallback? onOpenStatus;
  final WeeklyDigest? weeklyDigest; // this-week roll-up (null/no-data = hidden)
  final SetupProgress? setupProgress; // first-run checklist (null/complete = hidden)
  final VoidCallback? onOpenSetup; // where "finish setting up" leads
  final Appointment? nextAppointment; // soonest upcoming (null = hidden)
  final DateTime? nowForAppointment; // anchor for the countdown
  final VoidCallback? onOpenAppointments;
  final VoidCallback? onLogVitals; // hand-entered reading (no band required)
  // Hydration (optional — the card shows only when wired up).
  final int waterCount;
  final int waterGoal;
  final VoidCallback? onAddWater;
  final VoidCallback? onRemoveWater;
  final ValueChanged<int>? onSetWaterGoal;
  final VoidCallback? onOpenWaterHistory;
  const HealthDashboardView({
    super.key,
    required this.samples,
    this.sleepNights = const [],
    this.greetingName = '',
    this.photoPath,
    this.currentLocale,
    this.onLocaleChange,
    this.onOpenProfile,
    this.onOpenAdvisor,
    this.summaryStatus = '',
    this.statusChip = '',
    this.statusChipPregnancy = false,
    this.statusChipLate = false,
    this.onOpenStatus,
    this.weeklyDigest,
    this.setupProgress,
    this.onOpenSetup,
    this.nextAppointment,
    this.nowForAppointment,
    this.onOpenAppointments,
    this.onLogVitals,
    this.waterCount = 0,
    this.waterGoal = 8,
    this.onAddWater,
    this.onRemoveWater,
    this.onSetWaterGoal,
    this.onOpenWaterHistory,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leadingWidth: onOpenProfile == null ? null : 60,
          leading: onOpenProfile == null ? null : _AvatarButton(name: greetingName, photoPath: photoPath, onTap: onOpenProfile!),
          title: Text(greetingName.isEmpty ? l.t('db_title') : l.t('db_greeting', {'name': greetingName})),
          actions: [
            if (onLogVitals != null)
              IconButton(
                icon: const Icon(Icons.add_chart_rounded, color: Palette.textDim),
                tooltip: l.t('vitals_log'),
                onPressed: onLogVitals,
              ),
            if (samples.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.ios_share_rounded, color: Palette.textDim),
                tooltip: l.t('db_share'),
                onPressed: () => _shareSummary(context, l),
              ),
            if (onLocaleChange != null)
              PopupMenuButton<AppLocale>(
                icon: const Icon(Icons.language, color: Palette.textDim),
                color: Palette.surfaceHi,
                initialValue: currentLocale,
                onSelected: onLocaleChange,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: AppLocale.ru, child: Text('Русский')),
                  PopupMenuItem(value: AppLocale.kk, child: Text('Қазақша')),
                  PopupMenuItem(value: AppLocale.en, child: Text('English')),
                ],
              ),
            const SizedBox(width: 4),
          ],
        ),
        // With no readings there's nothing to chart — but a half-configured app
        // still owes the user its setup guidance, so the checklist shows here
        // too rather than being stranded behind the populated dashboard.
        body: samples.isEmpty
            ? ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  if (setupProgress != null && !setupProgress!.complete) ...[
                    _SetupCard(progress: setupProgress!, onTap: onOpenSetup),
                    const SizedBox(height: 20),
                  ],
                  _EmptyState(onLogVitals: onLogVitals),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                children: [
                  if (statusChip.isNotEmpty && onOpenStatus != null) ...[
                    _StatusChip(label: statusChip, pregnancy: statusChipPregnancy, late: statusChipLate, onTap: onOpenStatus!),
                    const SizedBox(height: 12),
                  ],
                  // Setup guidance outranks ambient status: an unfinished app
                  // shouldn't hide "add a child" below a 2x2 grid of metrics.
                  if (setupProgress != null && !setupProgress!.complete) ...[
                    _SetupCard(progress: setupProgress!, onTap: onOpenSetup),
                    const SizedBox(height: 14),
                  ],
                  _PeaceOfMindBanner(samples: samples, name: greetingName),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.94,
                    children: [
                      for (final spec in _specs) _MetricCard(spec: spec, samples: samples),
                      _BloodPressureCard(samples: samples),
                    ],
                  ),
                  if (nextAppointment != null) ...[
                    const SizedBox(height: 14),
                    _NextAppointmentCard(
                      appt: nextAppointment!,
                      now: nowForAppointment ?? DateTime.now(),
                      onTap: onOpenAppointments,
                    ),
                  ],
                  if (weeklyDigest?.hasData ?? false) ...[
                    const SizedBox(height: 14),
                    _WeeklyDigestCard(digest: weeklyDigest!),
                  ],
                  if (onAddWater != null) ...[
                    const SizedBox(height: 14),
                    WaterCard(
                      count: waterCount,
                      goal: waterGoal,
                      onAdd: onAddWater!,
                      onRemove: onRemoveWater ?? () {},
                      onSetGoal: onSetWaterGoal ?? (_) {},
                      onOpenHistory: onOpenWaterHistory,
                    ),
                  ],
                  if (latestNight(sleepNights) != null) ...[
                    const SizedBox(height: 14),
                    SleepCard(nights: sleepNights),
                  ],
                  if (onOpenAdvisor != null) ...[
                    const SizedBox(height: 18),
                    _AdvisorEntry(onTap: onOpenAdvisor!),
                  ],
                ],
              ),
      ),
    );
  }

  Future<void> _shareSummary(BuildContext context, L10n l) async {
    final text = buildHealthSummary(l, samples, nights: sleepNights, name: greetingName, status: summaryStatus);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.t('db_share_copied')), behavior: SnackBarBehavior.floating),
    );
  }
}

/// The reassuring master component: one ambient status block that summarizes
/// every metric in a single warm line. Green ring + check when everything is
/// steady; warm amber ring + the top concern when something is worth watching.
class _PeaceOfMindBanner extends StatelessWidget {
  final List<HealthSample> samples;
  final String name;
  const _PeaceOfMindBanner({required this.samples, required this.name});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final status = overallStatus(samples);
    final (accent, icon, gradient) = switch (status.tone) {
      AdviceTone.positive => (Palette.good, Icons.check_rounded, const LinearGradient(colors: [Palette.good, Palette.teal])),
      AdviceTone.watch => (Palette.amber, Icons.spa_rounded, const LinearGradient(colors: [Palette.amber, Palette.rose])),
      AdviceTone.info => (Palette.violet, Icons.hourglass_bottom_rounded, Palette.roseViolet),
    };

    // Data-driven ring: fraction of metrics currently in a healthy range.
    var withData = 0, healthy = 0;
    for (final k in metricKeys) {
      final s = statsFor(buildSeries(samples, k));
      if (s == null) continue;
      withData++;
      if (!latestInDanger(k, s)) healthy++;
    }
    final fraction = withData == 0 ? 1.0 : healthy / withData;

    final headline = switch (status.tone) {
      AdviceTone.positive => name.isEmpty ? l.t('db_peace_stable_noname') : l.t('db_peace_stable', {'name': name}),
      AdviceTone.info => l.t(status.code),
      AdviceTone.watch => l.t(status.code),
    };
    final sub = switch (status.tone) {
      AdviceTone.positive => l.t('db_peace_stable_b'),
      AdviceTone.info => l.t('${status.code}_b'),
      AdviceTone.watch => l.t('${status.code}_b'),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.10), accent.withValues(alpha: 0.03)],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          MetricRing(
            fraction: fraction,
            gradient: gradient,
            size: 74,
            stroke: 8,
            center: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(gradient: gradient, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(headline,
                      style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w700, height: 1.2, color: Palette.text)),
                  const SizedBox(height: 5),
                  Text(sub,
                      style: const TextStyle(color: Palette.textDim, fontSize: 13, height: 1.35)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final MetricSpec spec;
  final List<HealthSample> samples;
  const _MetricCard({required this.spec, required this.samples});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final label = l.metricLabel(spec.key);
    final series = downsampleMean(buildSeries(samples, spec.key), 40);
    final stats = statsFor(series);
    final danger = latestInDanger(spec.key, stats);
    final value = stats == null ? '—' : _fmt(spec.key, stats.latest);

    return Semantics(
      label: '$label: $value ${spec.unit}${danger ? l.t('db_outside_range') : ''}',
      child: GlassCard(
        glow: danger ? Palette.danger : spec.color,
        padding: const EdgeInsets.all(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MetricDetailScreen(
            metricKey: spec.key,
            unit: spec.unit,
            icon: spec.icon,
            color: spec.color,
            samples: samples,
          ),
        )),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _IconBadge(spec.icon, spec.gradient),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Palette.textDim, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
                if (stats != null) _trend(stats.trend),
              ],
            ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value,
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      color: danger ? Palette.danger : Palette.text,
                    )),
                const SizedBox(width: 4),
                Text(spec.unit, style: const TextStyle(color: Palette.textDim, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: Sparkline(
                points: series,
                band: bandFor(spec.key),
                color: danger ? Palette.danger : spec.color,
                inDanger: danger,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trend(Trend t) {
    final (icon, color) = switch (t) {
      Trend.up => (Icons.north_east, Palette.watch),
      Trend.down => (Icons.south_east, Palette.blue),
      Trend.flat => (Icons.trending_flat, Palette.textDim),
    };
    return Icon(icon, size: 16, color: color);
  }

  String _fmt(String key, double v) => key == 'temp' ? v.toStringAsFixed(1) : v.round().toString();
}

/// Blood pressure, presented the way clinics do: systolic / diastolic together
/// ("138 / 77 mmHg"). Danger if EITHER value is out of range. The mini chart
/// layers the diastolic wave faintly behind the systolic one.
class _BloodPressureCard extends StatelessWidget {
  final List<HealthSample> samples;
  const _BloodPressureCard({required this.samples});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final sysSeries = downsampleMean(buildSeries(samples, 'systolic'), 40);
    final diaSeries = downsampleMean(buildSeries(samples, 'diastolic'), 40);
    final sys = statsFor(sysSeries);
    final dia = statsFor(diaSeries);
    final danger = latestInDanger('systolic', sys) || latestInDanger('diastolic', dia);
    final sysV = sys == null ? '—' : sys.latest.round().toString();
    final diaV = dia == null ? '—' : dia.latest.round().toString();

    return Semantics(
      label: '${l.t('metric_bp')}: $sysV / $diaV mmHg${danger ? l.t('db_outside_range') : ''}',
      child: GlassCard(
        glow: danger ? Palette.danger : Palette.violet,
        padding: const EdgeInsets.all(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MetricDetailScreen(
            metricKey: 'systolic',
            unit: 'mmHg',
            icon: Icons.monitor_heart_rounded,
            color: Palette.violet,
            samples: samples,
          ),
        )),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _IconBadge(Icons.monitor_heart_rounded, LinearGradient(colors: [Palette.violet, Palette.pink])),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l.t('metric_bp'),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Palette.textDim, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
                if (sys != null) _trendIcon(sys.trend),
              ],
            ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(sysV,
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono', fontSize: 27, fontWeight: FontWeight.w700, height: 1,
                      color: danger ? Palette.danger : Palette.text,
                    )),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 3),
                  child: Text('/', style: TextStyle(color: Palette.textDim, fontSize: 22, fontWeight: FontWeight.w400)),
                ),
                Text(diaV,
                    style: const TextStyle(
                      fontFamily: 'JetBrainsMono', fontSize: 27, fontWeight: FontWeight.w700, height: 1, color: Palette.text,
                    )),
                const SizedBox(width: 4),
                const Text('mmHg', style: TextStyle(color: Palette.textDim, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: Stack(
                children: [
                  if (diaSeries.length >= 2)
                    Sparkline(points: diaSeries, band: const MetricBand(), color: Palette.blue.withValues(alpha: 0.45)),
                  Sparkline(
                    points: sysSeries,
                    band: bandFor('systolic'),
                    color: danger ? Palette.danger : Palette.violet,
                    inDanger: danger,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trendIcon(Trend t) {
    final (icon, color) = switch (t) {
      Trend.up => (Icons.north_east, Palette.watch),
      Trend.down => (Icons.south_east, Palette.blue),
      Trend.flat => (Icons.trending_flat, Palette.textDim),
    };
    return Icon(icon, size: 16, color: color);
  }
}

/// The friendly, conversational entry to the data-driven advisor — a rounded
/// prompt row rather than a buried tab.
class _AdvisorEntry extends StatelessWidget {
  final VoidCallback onTap;
  const _AdvisorEntry({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Palette.violet.withValues(alpha: 0.10), Palette.rose.withValues(alpha: 0.08)],
            ),
            border: Border.all(color: Palette.violet.withValues(alpha: 0.18)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: const BoxDecoration(gradient: Palette.roseViolet, shape: BoxShape.circle),
                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.t('db_advisor_cta'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Palette.text)),
                    const SizedBox(height: 2),
                    Text(l.t('db_advisor_sub'),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(color: Palette.violet.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: const Icon(Icons.arrow_forward_rounded, color: Palette.violet, size: 17),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact, tappable pill showing the current cycle day or pregnancy week,
/// opening the women's-health tab. Rose for cycle, violet for pregnancy.
class _StatusChip extends StatelessWidget {
  final String label;
  final bool pregnancy;
  final bool late;
  final VoidCallback onTap;
  const _StatusChip({required this.label, required this.pregnancy, required this.onTap, this.late = false});

  @override
  Widget build(BuildContext context) {
    // Amber for a late period — "worth a look", never an alarm red.
    final accent = pregnancy
        ? Palette.violet
        : late
            ? Palette.amber
            : Palette.roseDeep;
    final icon = pregnancy
        ? Icons.pregnant_woman_rounded
        : late
            ? Icons.schedule_rounded
            : Icons.spa_rounded;
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              color: accent.withValues(alpha: 0.10),
              border: Border.all(color: accent.withValues(alpha: 0.22)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: accent),
                const SizedBox(width: 7),
                Text(label, style: TextStyle(color: accent, fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right_rounded, size: 18, color: accent.withValues(alpha: 0.8)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Finish setting up" — a progress bar plus the next outstanding step, so a
/// half-configured app tells you what's missing instead of feeling empty.
/// Disappears entirely once every step is done.
class _SetupCard extends StatelessWidget {
  final SetupProgress progress;
  final VoidCallback? onTap;
  const _SetupCard({required this.progress, this.onTap});

  static String _key(SetupStep s) => switch (s) {
        SetupStep.profileName => 'setup_name',
        SetupStep.healthMode => 'setup_health',
        SetupStep.child => 'setup_child',
        SetupStep.zone => 'setup_zone',
        SetupStep.backup => 'setup_backup',
      };

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final next = progress.next!;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(color: Palette.violet.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
                child: const Icon(Icons.rocket_launch_rounded, size: 18, color: Palette.violet),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(l.t('setup_title'),
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Palette.text)),
              ),
              Text('${progress.done.length}/${progress.total}',
                  style: const TextStyle(fontFamily: 'JetBrainsMono', color: Palette.violet, fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress.fraction,
              minHeight: 7,
              backgroundColor: Palette.glass,
              valueColor: const AlwaysStoppedAnimation(Palette.violet),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.arrow_forward_rounded, size: 15, color: Palette.textDim),
            const SizedBox(width: 6),
            Expanded(
              child: Text(l.t(_key(next)),
                  style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.3)),
            ),
          ]),
        ],
      ),
    );
  }
}

/// The soonest upcoming appointment with a friendly countdown ("Tomorrow",
/// "in 5 days"), tappable to open the full appointments list.
class _NextAppointmentCard extends StatelessWidget {
  final Appointment appt;
  final DateTime now;
  final VoidCallback? onTap;
  const _NextAppointmentCard({required this.appt, required this.now, this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final ml = MaterialLocalizations.of(context);
    final days = daysUntil(appt, now);
    final when = appointmentWhen(days);
    final (accent, badge) = switch (when) {
      ApptWhen.today => (Palette.roseDeep, l.t('appt_today')),
      ApptWhen.tomorrow => (Palette.roseDeep, l.t('appt_tomorrow')),
      ApptWhen.soon => (Palette.violet, l.t('appt_in_days', {'n': days})),
      ApptWhen.later => (Palette.textDim, l.t('appt_in_days', {'n': days})),
    };
    final time = TimeOfDay.fromDateTime(appt.at).format(context);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(13)),
            child: Icon(Icons.event_rounded, color: accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('appt_next').toUpperCase(),
                    style: const TextStyle(color: Palette.textDim, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                const SizedBox(height: 3),
                Text(appt.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Palette.text)),
                const SizedBox(height: 2),
                Text('${ml.formatMediumDate(appt.at)} · $time',
                    style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
            child: Text(badge, style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// This-week roll-up: days logged, water glasses (+ goal days), and average
/// sleep — a friendly weekly recap card.
class _WeeklyDigestCard extends StatelessWidget {
  final WeeklyDigest digest;
  const _WeeklyDigestCard({required this.digest});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final sleepLabel = digest.sleepNights == 0
        ? '—'
        : '${digest.avgSleepMin ~/ 60}h ${digest.avgSleepMin % 60}m';
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(gradient: Palette.roseViolet, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.calendar_view_week_rounded, size: 17, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Text(l.t('db_week_title'),
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Palette.text)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _DigestStat(value: '${digest.daysLogged}', label: l.t('db_week_logged'), color: Palette.violet),
              _digestDivider(),
              _DigestStat(
                value: '${digest.waterGlasses}',
                label: l.t('db_week_water', {'n': digest.waterGoalDays}),
                color: Palette.blue,
              ),
              _digestDivider(),
              _DigestStat(value: sleepLabel, label: l.t('db_week_sleep'), color: Palette.teal),
            ],
          ),
        ],
      ),
    );
  }

  Widget _digestDivider() => Container(width: 1, height: 34, color: Palette.border);
}

class _DigestStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _DigestStat({required this.value, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(value, style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 20, fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 3),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Palette.textDim, fontSize: 11, height: 1.2)),
          ],
        ),
      );
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Gradient gradient;
  const _IconBadge(this.icon, this.gradient);
  @override
  Widget build(BuildContext context) => Container(
        width: 30, height: 30,
        decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 17, color: Colors.white),
      );
}

class _AvatarButton extends StatelessWidget {
  final String name;
  final String? photoPath;
  final VoidCallback onTap;
  const _AvatarButton({required this.name, required this.onTap, this.photoPath});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: PhotoAvatar(photoPath: photoPath, name: name, size: 38),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback? onLogVitals;
  const _EmptyState({this.onLogVitals});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: GlassCard(
          glow: Palette.violet,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64, height: 64,
                decoration: const BoxDecoration(gradient: Palette.violetPink, shape: BoxShape.circle),
                child: const Icon(Icons.watch_outlined, size: 30, color: Colors.white),
              ),
              const SizedBox(height: 16),
              Text(l.t('db_empty_title'),
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Palette.text)),
              const SizedBox(height: 8),
              Text(l.t('db_empty_body'),
                  textAlign: TextAlign.center, style: const TextStyle(color: Palette.textDim, height: 1.4)),
              // Without a band this is the only way in — so offer it here
              // rather than leaving the screen a dead end.
              if (onLogVitals != null) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onLogVitals,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l.t('vitals_log')),
                  style: FilledButton.styleFrom(
                    backgroundColor: Palette.violet,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
