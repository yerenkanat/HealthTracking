/// Health dashboard — premium light UI. A 2-column grid of soft white metric
/// cards, each with a distinct icon + color, a mono readout, trend, and an
/// area-fill sparkline; danger readings turn red.
/// Pure presentation over the verified health_series logic.
library;

import 'package:flutter/material.dart';
import '../../domain/health_series.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import 'sparkline.dart';

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

const _specs = <MetricSpec>[
  MetricSpec('hr', 'bpm', Icons.favorite_rounded, LinearGradient(colors: [_hrColor, Palette.pink]), _hrColor),
  MetricSpec('spo2', '%', Icons.air_rounded, Palette.tealBlue, Palette.teal),
  MetricSpec('systolic', 'mmHg', Icons.speed_rounded, LinearGradient(colors: [Palette.violet, Palette.pink]), Palette.violet),
  MetricSpec('diastolic', 'mmHg', Icons.compress_rounded, LinearGradient(colors: [Palette.blue, Palette.violet]), Palette.blue),
  MetricSpec('temp', '°C', Icons.thermostat_rounded, LinearGradient(colors: [_tempA, _tempB]), _tempA),
];

class HealthDashboardScreen extends StatelessWidget {
  final List<HealthSample> samples;
  final String greetingName;
  final AppLocale? currentLocale;
  final void Function(AppLocale)? onLocaleChange;
  const HealthDashboardScreen({
    super.key,
    required this.samples,
    this.greetingName = '',
    this.currentLocale,
    this.onLocaleChange,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(greetingName.isEmpty ? l.t('db_title') : l.t('db_greeting', {'name': greetingName})),
          actions: [
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
          ],
        ),
        body: samples.isEmpty
            ? _EmptyState()
            : GridView.count(
                crossAxisCount: 2,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.92,
                children: [for (final spec in _specs) _MetricCard(spec: spec, samples: samples)],
              ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(gradient: spec.gradient, borderRadius: BorderRadius.circular(10)),
                child: Icon(spec.icon, size: 17, color: Colors.white),
              ),
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

class _EmptyState extends StatelessWidget {
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
            ],
          ),
        ),
      ),
    );
  }
}
