/// Metric detail — opened by tapping a dashboard card. Shows the full series in a
/// large chart (line + area + danger band + min/max guides) plus summary stats.
/// Pure presentation over the verified health_series logic.
library;

import 'package:flutter/material.dart';
import '../../domain/health_series.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/glass.dart';

enum _Range { d1, d7, all }

class MetricDetailScreen extends StatefulWidget {
  final String metricKey;
  final String unit;
  final IconData icon;
  final Color color;
  final List<HealthSample> samples;

  const MetricDetailScreen({
    super.key,
    required this.metricKey,
    required this.unit,
    required this.icon,
    required this.color,
    required this.samples,
  });

  @override
  State<MetricDetailScreen> createState() => _MetricDetailScreenState();
}

class _MetricDetailScreenState extends State<MetricDetailScreen> {
  _Range _range = _Range.all;

  List<HealthSample> _filtered() {
    if (_range == _Range.all) return widget.samples;
    final now = DateTime.now();
    final cutoff = now.subtract(_range == _Range.d1 ? const Duration(hours: 24) : const Duration(days: 7));
    return widget.samples.where((s) => s.at.isAfter(cutoff)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final metricKey = widget.metricKey;
    final unit = widget.unit;
    final icon = widget.icon;
    final color = widget.color;
    final label = l.metricLabel(metricKey);
    final series = buildSeries(_filtered(), metricKey);
    final stats = statsFor(series);
    final band = bandFor(metricKey);
    final danger = latestInDanger(metricKey, stats);

    String fmt(double v) => metricKey == 'temp' ? v.toStringAsFixed(1) : v.round().toString();

    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(label)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // Current value
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.7)]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Text(stats == null ? '—' : fmt(stats.latest),
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      color: danger ? Palette.danger : Palette.text,
                    )),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(unit, style: const TextStyle(color: Palette.textDim, fontSize: 15)),
                ),
                const Spacer(),
                if (stats != null) _TrendChip(stats.trend),
              ],
            ),
            const SizedBox(height: 18),
            _RangeSelector(range: _range, onChanged: (r) => setState(() => _range = r)),
            const SizedBox(height: 14),

            // Chart
            GlassCard(
              padding: const EdgeInsets.fromLTRB(10, 18, 16, 12),
              child: series.length < 2
                  ? SizedBox(
                      height: 200,
                      child: Center(
                        child: Text(l.t('detail_no_data'),
                            style: const TextStyle(color: Palette.textDim)),
                      ),
                    )
                  : SizedBox(
                      height: 220,
                      child: CustomPaint(
                        painter: _LargeChartPainter(series, band, color, danger),
                        child: const SizedBox.expand(),
                      ),
                    ),
            ),
            const SizedBox(height: 14),

            // Stats
            if (stats != null)
              Row(
                children: [
                  _Stat(l.t('stat_latest'), fmt(stats.latest), color),
                  _Stat(l.t('stat_min'), fmt(stats.min), Palette.textDim),
                  _Stat(l.t('stat_max'), fmt(stats.max), Palette.textDim),
                  _Stat(l.t('stat_avg'), fmt(stats.mean), Palette.textDim),
                ],
              ),

            if (band.warnAbove != null || band.warnBelow != null) ...[
              const SizedBox(height: 14),
              Row(children: [
                Container(width: 12, height: 12,
                    decoration: BoxDecoration(color: Palette.danger.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 8),
                Text(l.t('detail_safe_range'), style: const TextStyle(color: Palette.textDim, fontSize: 13)),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _RangeSelector extends StatelessWidget {
  final _Range range;
  final ValueChanged<_Range> onChanged;
  const _RangeSelector({required this.range, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final items = [(_Range.d1, l.t('range_24h')), (_Range.d7, l.t('range_7d')), (_Range.all, l.t('range_all'))];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Palette.glass, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          for (final (r, lbl) in items)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(r),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: r == range ? Palette.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: r == range ? Palette.cardShadow : null,
                  ),
                  child: Text(lbl,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: r == range ? Palette.text : Palette.textDim,
                      )),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Stat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 18, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Palette.textDim, fontSize: 11.5)),
        ],
      ),
    );
  }
}

class _TrendChip extends StatelessWidget {
  final Trend trend;
  const _TrendChip(this.trend);
  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (trend) {
      Trend.up => (Icons.north_east, Palette.watch),
      Trend.down => (Icons.south_east, Palette.blue),
      Trend.flat => (Icons.trending_flat, Palette.textDim),
    };
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

class _LargeChartPainter extends CustomPainter {
  final List<SeriesPoint> points;
  final MetricBand band;
  final Color color;
  final bool danger;
  _LargeChartPainter(this.points, this.band, this.color, this.danger);

  @override
  void paint(Canvas canvas, Size size) {
    var lo = points.first.value, hi = points.first.value;
    for (final p in points) {
      lo = p.value < lo ? p.value : lo;
      hi = p.value > hi ? p.value : hi;
    }
    if (band.warnAbove != null) hi = hi > band.warnAbove! ? hi : band.warnAbove!;
    if (band.warnBelow != null) lo = lo < band.warnBelow! ? lo : band.warnBelow!;
    final pad = (hi - lo) * 0.15 + 0.5;
    lo -= pad;
    hi += pad;
    final range = (hi - lo).abs() < 1e-6 ? 1.0 : hi - lo;

    double x(int i) => size.width * i / (points.length - 1);
    double y(double v) => size.height - ((v - lo) / range) * size.height;

    // Horizontal grid lines (4).
    final grid = Paint()
      ..color = Palette.border
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final gy = size.height * i / 3;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
    }

    // Danger band shading.
    final bandPaint = Paint()..color = Palette.danger.withValues(alpha: 0.10);
    if (band.warnAbove != null) {
      final yb = y(band.warnAbove!).clamp(0.0, size.height);
      canvas.drawRect(Rect.fromLTRB(0, 0, size.width, yb), bandPaint);
    }
    if (band.warnBelow != null) {
      final yb = y(band.warnBelow!).clamp(0.0, size.height);
      canvas.drawRect(Rect.fromLTRB(0, yb, size.width, size.height), bandPaint);
    }

    // Line path.
    final path = Path()..moveTo(x(0), y(points[0].value));
    for (var i = 1; i < points.length; i++) {
      path.lineTo(x(i), y(points[i].value));
    }
    // Area fill.
    final area = Path.from(path)
      ..lineTo(x(points.length - 1), size.height)
      ..lineTo(x(0), size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.20), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );
    // Line.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    // Latest dot.
    final last = Offset(x(points.length - 1), y(points.last.value));
    canvas.drawCircle(last, 6, Paint()..color = color.withValues(alpha: 0.2));
    canvas.drawCircle(last, 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LargeChartPainter old) => old.points != points;
}
