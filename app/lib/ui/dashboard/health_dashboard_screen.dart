/// Health dashboard — calm, glanceable FemTech overview of the mother's vitals.
/// Pure presentation over the verified health_series logic. Each tile shows the
/// latest value, trend, a sparkline with its danger band, and switches to an
/// alert style only when the latest reading is actually in the danger zone.
/// Strings come from L10nScope (English fallback keeps widget tests valid).
library;

import 'package:flutter/material.dart';
import '../../domain/health_series.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import 'sparkline.dart';

class MetricSpec {
  final String key; // also the l10n label key suffix (metric_<key>)
  final String unit;
  final Color color;
  const MetricSpec(this.key, this.unit, this.color);
}

// Distinct, accessible hues — one per series (dataviz: color by series).
const _specs = <MetricSpec>[
  MetricSpec('hr', 'bpm', Color(0xFF4C6EF5)),
  MetricSpec('spo2', '%', Color(0xFF12B886)),
  MetricSpec('systolic', 'mmHg', Color(0xFFF06595)),
  MetricSpec('diastolic', 'mmHg', Color(0xFFAE3EC9)),
  MetricSpec('temp', '°C', Color(0xFFFD7E14)),
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
    return Scaffold(
      appBar: AppBar(
        title: Text(greetingName.isEmpty ? l.t('db_title') : l.t('db_greeting', {'name': greetingName})),
        elevation: 0,
        actions: [
          if (onLocaleChange != null)
            PopupMenuButton<AppLocale>(
              icon: const Icon(Icons.language),
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
          ? const _EmptyState()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final spec in _specs) _MetricTile(spec: spec, samples: samples),
              ],
            ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final MetricSpec spec;
  final List<HealthSample> samples;
  const _MetricTile({required this.spec, required this.samples});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final label = l.metricLabel(spec.key);
    final series = downsampleMean(buildSeries(samples, spec.key), 60);
    final stats = statsFor(series);
    final danger = latestInDanger(spec.key, stats);
    final band = bandFor(spec.key);

    final valueText = stats == null ? '—' : _fmt(spec.key, stats.latest);
    final borderColor = danger ? const Color(0xFFE5484D) : Colors.transparent;

    return Semantics(
      label: '$label: $valueText ${spec.unit}${danger ? l.t('db_outside_range') : ''}',
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor, width: danger ? 1.5 : 0),
        ),
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 10, height: 10,
                      decoration: BoxDecoration(color: spec.color, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  const Spacer(),
                  if (stats != null) _TrendChip(stats.trend),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(valueText,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: danger ? const Color(0xFFE5484D) : null,
                      )),
                  const SizedBox(width: 4),
                  Text(spec.unit, style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
              const SizedBox(height: 8),
              Sparkline(points: series, band: band, color: spec.color, inDanger: danger),
              if (stats != null) ...[
                const SizedBox(height: 6),
                Text(
                  l.t('db_stats', {
                    'min': _fmt(spec.key, stats.min),
                    'max': _fmt(spec.key, stats.max),
                    'avg': _fmt(spec.key, stats.mean),
                  }),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(String key, double v) => key == 'temp' ? v.toStringAsFixed(1) : v.round().toString();
}

class _TrendChip extends StatelessWidget {
  final Trend trend;
  const _TrendChip(this.trend);
  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (trend) {
      Trend.up => (Icons.trending_up, Colors.orange),
      Trend.down => (Icons.trending_down, Colors.blue),
      Trend.flat => (Icons.trending_flat, Colors.grey),
    };
    return Icon(icon, size: 20, color: color);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.watch_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(l.t('db_empty_title'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(l.t('db_empty_body'),
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}
