/// The child's growth chart.
///
/// Her child against her child's own history. No percentile bands — see
/// domain/child_growth.dart for why that is a decision rather than a gap, and
/// docs/INTEGRATION_STATUS.md for what adding them properly involves.
library;

import 'package:flutter/material.dart';

import '../../domain/child_growth.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

class ChildGrowthScreen extends StatelessWidget {
  final String childName;
  final List<GrowthPoint> points;
  final VoidCallback? onAdd;

  /// Delete the measurement recorded on this day. Null makes the list
  /// read-only — a mistaken entry must be removable, so the wired screen always
  /// passes it.
  final void Function(DateTime day)? onDelete;

  const ChildGrowthScreen({
    super.key,
    required this.childName,
    required this.points,
    this.onAdd,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final weights = weightSeries(points);
    final heights = heightSeries(points);

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(backgroundColor: Palette.bg, title: Text(l.t('grw_title'))),
      floatingActionButton: onAdd == null
          ? null
          : FloatingActionButton.extended(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(l.t('grw_add')),
            ),
      body: points.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(l.t('grw_empty'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Palette.textDim, height: 1.45)),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                if (weights.isNotEmpty)
                  _GrowthCard(
                    title: l.t('grw_weight'),
                    unit: l.t('grw_kg'),
                    values: [for (final p in weights) p.weightKg!],
                    dates: [for (final p in weights) p.at],
                    change: weightChange(points),
                    colour: Palette.violet,
                  ),
                if (heights.isNotEmpty)
                  _GrowthCard(
                    title: l.t('grw_height'),
                    unit: l.t('grw_cm'),
                    values: [for (final p in heights) p.heightCm!],
                    dates: [for (final p in heights) p.at],
                    change: heightChange(points),
                    colour: Palette.teal,
                  ),
                // Every recorded visit, newest first. Also where a mistaken
                // entry is removed — long-press, then confirm.
                _Title(l.t('grw_history')),
                for (final p in points.reversed)
                  _VisitRow(point: p, onDelete: onDelete),
                const SizedBox(height: 8),

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
                        child: Text(l.t('grw_no_percentiles'),
                            style: const TextStyle(
                                color: Palette.textDim, fontSize: 12.5, height: 1.45)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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

/// One recorded visit. Long-press to remove it — the delete path a mistaken
/// entry needs, and the reason removeGrowth is reachable rather than defined
/// and orphaned.
class _VisitRow extends StatelessWidget {
  final GrowthPoint point;
  final void Function(DateTime day)? onDelete;
  const _VisitRow({required this.point, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final ml = MaterialLocalizations.of(context);
    final parts = <String>[
      if (point.weightKg != null) '${point.weightKg!.toStringAsFixed(1)} ${l.t('grw_kg')}',
      if (point.heightCm != null) '${point.heightCm!.toStringAsFixed(1)} ${l.t('grw_cm')}',
    ];

    return InkWell(
      onLongPress: onDelete == null ? null : () => onDelete!(point.at),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(ml.formatMediumDate(point.at),
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
            Text(parts.join(' · '),
                style: const TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Palette.textDim)),
          ],
        ),
      ),
    );
  }
}

class _GrowthCard extends StatelessWidget {
  final String title;
  final String unit;
  final List<double> values;
  final List<DateTime> dates;
  final ({double delta, int days})? change;
  final Color colour;

  const _GrowthCard({
    required this.title,
    required this.unit,
    required this.values,
    required this.dates,
    required this.change,
    required this.colour,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final latest = values.last;
    final c = change;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(title.toUpperCase(),
                    style: const TextStyle(
                        color: Palette.textDim,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6)),
              ),
              Text('${latest.toStringAsFixed(1)} $unit',
                  style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: colour)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            // A loss is shown as a loss. Babies do lose weight in the first
            // days and after illness, and hiding it would make the one figure
            // a parent came to check the one figure the app will not show.
            c == null
                ? l.t('grw_first')
                : '${c.delta >= 0 ? '+' : '−'}${c.delta.abs().toStringAsFixed(1)} $unit '
                    '· ${l.t('grw_since', {'n': c.days})}',
            style: TextStyle(
                color: c == null
                    ? Palette.textDim
                    : (c.delta >= 0 ? Palette.good : Palette.watch),
                fontSize: 12.5,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: CustomPaint(
              size: Size.infinite,
              painter: _LinePainter(values: values, colour: colour),
            ),
          ),
        ],
      ),
    );
  }
}

/// A plain line through the measurements.
class _LinePainter extends CustomPainter {
  final List<double> values;
  final Color colour;
  const _LinePainter({required this.values, required this.colour});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final axis = axisFor(values);
    final span = axis.max - axis.min;

    double x(int i) => values.length == 1
        ? size.width / 2
        : size.width * i / (values.length - 1);
    double y(double v) => size.height - ((v - axis.min) / span) * size.height;

    final grid = Paint()
      ..color = Palette.border
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final gy = size.height * i / 3;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
    }

    final dot = Paint()..color = colour;

    // A single measurement is a dot, not a line — drawing a line through one
    // point suggests a trend that has not been measured yet.
    if (values.length == 1) {
      canvas.drawCircle(Offset(x(0), y(values.first)), 4.5, dot);
      return;
    }

    final path = Path()..moveTo(x(0), y(values.first));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(x(i), y(values[i]));
    }

    final fill = Path.from(path)
      ..lineTo(x(values.length - 1), size.height)
      ..lineTo(x(0), size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colour.withValues(alpha: 0.22), colour.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );

    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(Offset(x(i), y(values[i])), 3.2, dot);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.colour != colour || !identical(old.values, values);
}
