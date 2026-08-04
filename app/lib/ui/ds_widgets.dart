/// The recurring components of the Ana-Bala design system.
///
/// One widget per pattern named in `docs/design-system-app.md` § "Screen
/// patterns", so a screen is assembled from the same pieces the spec describes
/// rather than each screen re-deriving a 2px border and a 4px shadow by hand.
///
/// Everything here reads its colours from [Ds] and its type from `context.ds`
/// ([DsTypography]), which is what keeps the Kazakh font rule automatic — see
/// `design_system.dart`.
///
/// Two rules worth stating once, because they are what make the style read as
/// one system rather than a pile of borders:
///
///  * The **border is structural**. Almost every surface carries the same 2px
///    ink outline; that is the elevation model. Do not swap it for a shadow.
///  * The **shadow is a hard 4px offset with no blur**, and it means "this one
///    is primary or selected". Most cards do not have it. A blurred shadow
///    anywhere reads as a different product.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'design_system.dart';

// ---------------------------------------------------------------------------
// Surfaces
// ---------------------------------------------------------------------------

/// A white content card with the ink outline.
///
/// [raised] adds the hard offset shadow — for the one card on a screen that is
/// the primary thing, not for every card.
class DsCard extends StatelessWidget {
  const DsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = Colors.white,
    this.radius = DsShape.radiusCard,
    this.raised = false,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final double radius;
  final bool raised;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        // A raised card must be opaque: the hard shadow is an unblurred ink
        // rectangle behind it, and a translucent pastel would let it read
        // through and turn the card near-black.
        color: raised ? DsShape.opaque(color) : color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
        boxShadow: raised ? DsShape.hardShadow : null,
      ),
      child: child,
    );
    if (onTap == null) return body;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: body,
    );
  }
}

/// The "nothing here yet" state: a dashed ink outline, a ＋, and one line of
/// explanation. The spec calls for dashed specifically — it is how an empty
/// slot is told apart from a card that failed to load.
class DsEmptyState extends StatelessWidget {
  const DsEmptyState(
      {super.key, required this.label, this.onTap, this.glyph = '＋'});

  final String label;
  final VoidCallback? onTap;
  final String glyph;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: DsShape.card,
      child: CustomPaint(
        painter: const _DashedBorderPainter(radius: DsShape.radiusCard),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(glyph,
                  style:
                      context.ds.heroMetric(size: 30, color: Ds.textSecondary)),
              const SizedBox(height: 6),
              Text(label,
                  textAlign: TextAlign.center,
                  style: context.ds.caption().copyWith(fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.radius});
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Ds.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = DsShape.borderWidth;
    final rrect =
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    // Walk the rounded rect and draw 7-on/5-off, which is what reads as
    // "dashed" at this stroke width without turning into a dotted line.
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = (d + 7).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d = end + 5;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.radius != radius;
}

// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------

/// The primary call to action: a coral pill with an ink outline and the hard
/// offset shadow.
///
/// Not a themed [FilledButton] because a `ButtonStyle` cannot express the
/// offset shadow — the theme gets the pill and the outline, this gets the step.
class DsPrimaryButton extends StatelessWidget {
  const DsPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.fill = Ds.coralCta,
    this.foreground = Colors.white,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Defaults to the CTA coral, which is the one white text is legible on.
  final Color fill;
  final Color foreground;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final button = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: DsShape.pill,
        // A disabled control keeps the outline and loses the step: it still
        // looks like a button, just not like one waiting to be pressed.
        boxShadow: disabled ? null : DsShape.hardShadow,
      ),
      child: Material(
        color: disabled ? Ds.chevron : fill,
        shape: RoundedRectangleBorder(
            borderRadius: DsShape.pill, side: DsShape.border),
        child: InkWell(
          onTap: onPressed,
          customBorder: RoundedRectangleBorder(borderRadius: DsShape.pill),
          child: Container(
            constraints: const BoxConstraints(minHeight: 54),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Text(label,
                style: context.ds.button(size: 17, color: foreground)),
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// The quieter partner: white (or yellow) fill, ink outline, no step.
class DsSecondaryButton extends StatelessWidget {
  const DsSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.fill = Colors.white,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color fill;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: fill,
      shape: RoundedRectangleBorder(
          borderRadius: DsShape.pill, side: DsShape.border),
      child: InkWell(
        onTap: onPressed,
        customBorder: RoundedRectangleBorder(borderRadius: DsShape.pill),
        child: Container(
          constraints: const BoxConstraints(minHeight: 50),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Text(label, style: context.ds.button(size: 16, color: Ds.ink)),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// A solid accent square with a single white glyph. The spec is explicit that
/// these are text glyphs (◎ ♥ ▶ ✿ ☺), not custom artwork.
class DsIconTile extends StatelessWidget {
  const DsIconTile(
      {super.key,
      required this.glyph,
      this.color = Ds.coralCta,
      this.size = 42});

  final String glyph;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius:
            BorderRadius.circular(size < 40 ? 12 : DsShape.radiusTile),
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
      ),
      child: Text(glyph,
          style: context.ds.button(size: size * 0.45, color: Colors.white)),
    );
  }
}

// ---------------------------------------------------------------------------
// Data display
// ---------------------------------------------------------------------------

/// The one big number on a screen: coral panel, white type, an uppercase micro
/// label, and an optional nine-bar sparkline with the current bar picked out in
/// yellow.
class DsHeroMetric extends StatelessWidget {
  const DsHeroMetric({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.bars = const [],
    this.fill = Ds.coralCta,
  });

  final String label;
  final String value;
  final String? unit;

  /// Relative heights, 0..1. The last one is treated as "now".
  final List<double> bars;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final t = context.ds;
    return DsCard(
      color: fill,
      raised: true,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: t.micro(color: Colors.white)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: t.heroMetric(color: Colors.white)),
              if (unit != null) ...[
                const SizedBox(width: 8),
                Text(unit!, style: t.caption(color: Colors.white)),
              ],
            ],
          ),
          if (bars.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(height: 44, child: _Bars(bars: bars)),
          ],
        ],
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.bars});
  final List<double> bars;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < bars.length; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(
            child: FractionallySizedBox(
              heightFactor: bars[i].clamp(0.12, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // The current reading is the yellow one; the history behind it
                  // is white at 55%, per the spec.
                  color: i == bars.length - 1
                      ? Ds.yellow
                      : Colors.white.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A pastel tile in the 2-up grid: uppercase micro label, a number, a caption.
class DsStatTile extends StatelessWidget {
  const DsStatTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.fill = Ds.pastelPink,
    this.onTap,
  });

  final String label;
  final String value;
  final String? caption;
  final Color fill;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.ds;
    return DsCard(
      color: fill,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: t.micro()),
          const SizedBox(height: 6),
          Text(value, style: t.statNumber()),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(caption!, style: t.caption()),
          ],
        ],
      ),
    );
  }
}

/// One line of a [DsListCard].
class DsRow {
  const DsRow({
    required this.label,
    this.value,
    this.onTap,
    this.trailing,
    this.leading,
    this.subtitle,
    this.labelColor,
  });
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// An icon, avatar or badge before the label.
  ///
  /// The spec's list row is a bare label/value pair, which turned out to match
  /// no list in the app: settings rows carry an icon, a subtitle and a trailing
  /// control, and every screen had grown its own private row widget to say so.
  /// Adopting a row that could not hold them would have meant deleting content
  /// to fit the primitive.
  final Widget? leading;

  /// A quieter second line under [label] — what a device is doing, when a
  /// reminder fires, why an action is unavailable.
  final String? subtitle;

  /// Tints the label. Used to mark an irreversible action as such before it is
  /// tapped, not only in the dialog that follows.
  final Color? labelColor;
}

/// A white card of label/value rows separated by hairlines — the hairline is
/// [Ds.divider], NOT the 2px ink used for the card's own outline.
class DsListCard extends StatelessWidget {
  const DsListCard({super.key, required this.rows});

  final List<DsRow> rows;

  @override
  Widget build(BuildContext context) {
    final t = context.ds;
    return DsCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == rows.length - 1
                    ? null
                    : const Border(bottom: BorderSide(color: Ds.divider)),
              ),
              child: InkWell(
                onTap: rows[i].onTap,
                child: Container(
                  constraints:
                      const BoxConstraints(minHeight: DsShape.minTapTarget),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: Row(
                    children: [
                      if (rows[i].leading != null) ...[
                        rows[i].leading!,
                        const SizedBox(width: 14),
                      ],
                      Expanded(
                        child: rows[i].subtitle == null
                            ? Text(rows[i].label,
                                style: t.rowLabel.copyWith(color: rows[i].labelColor))
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(rows[i].label,
                                      style: t.rowLabel
                                          .copyWith(color: rows[i].labelColor)),
                                  const SizedBox(height: 2),
                                  Text(rows[i].subtitle!, style: t.rowValue),
                                ],
                              ),
                      ),
                      if (rows[i].value != null)
                        Text(rows[i].value!, style: t.rowValue),
                      if (rows[i].trailing != null) rows[i].trailing!,
                      if (rows[i].onTap != null && rows[i].trailing == null)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(Icons.chevron_right_rounded,
                              size: 20, color: Ds.chevron),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Controls
// ---------------------------------------------------------------------------

/// White pill, ink chip on the selected segment.
class DsSegmented extends StatelessWidget {
  const DsSegmented({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
  });

  final List<String> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.ds;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: DsShape.pill,
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => onChanged(i),
                customBorder:
                    RoundedRectangleBorder(borderRadius: DsShape.pill),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 38),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: Ds.ink, width: DsShape.borderWidth),
                    color: i == index ? Ds.ink : Colors.transparent,
                    borderRadius: DsShape.pill,
                  ),
                  child: Text(
                    items[i],
                    style: t.button(
                        size: 14,
                        color: i == index ? Colors.white : Ds.textSecondary),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 48×28 pill, mint when on, a 20px white knob, ink outlines throughout.
class DsToggle extends StatelessWidget {
  const DsToggle(
      {super.key,
      required this.value,
      required this.onChanged,
      this.semanticLabel});

  final bool value;

  /// Null disables the toggle. Several reminders are legitimately unavailable —
  /// a period reminder with no cycle logged, a medication reminder with no
  /// medications — and the row still has to show its state while refusing the
  /// tap. Adopting this widget is what surfaced the omission: it required a
  /// non-null callback, so every disabled row in the app was still a raw
  /// Material Switch.
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Semantics(
      label: semanticLabel,
      toggled: value,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? () => onChanged!(!value) : null,
        borderRadius: DsShape.pill,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 48,
          height: 28,
          padding: const EdgeInsets.all(2),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            // Disabled keeps the ink outline and the knob position — it still
            // reads as a switch showing its state, just not one that can be
            // moved — and drops the saturated "on" fill so it does not compete
            // with the toggles that CAN be pressed.
            color: !enabled
                ? Ds.chevron
                : value
                    ? Ds.mint
                    : Ds.chevron,
            borderRadius: DsShape.pill,
            border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
          ),
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.fromBorderSide(DsShape.border),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chrome
// ---------------------------------------------------------------------------

/// Back chevron + title, with an optional right-hand action in the link colour.
class DsScreenHeader extends StatelessWidget {
  const DsScreenHeader({
    super.key,
    required this.title,
    this.step,
    this.onBack,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? step;
  final VoidCallback? onBack;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.ds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (onBack != null)
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.chevron_left_rounded,
                    size: 28, color: Ds.textSecondary),
                constraints: const BoxConstraints(
                  minWidth: DsShape.minTapTarget,
                  minHeight: DsShape.minTapTarget,
                ),
                padding: EdgeInsets.zero,
              ),
            Expanded(child: Text(title, style: t.screenTitle)),
            if (actionLabel != null)
              TextButton(
                onPressed: onAction,
                child: Text(actionLabel!,
                    style: t.button(size: 15, color: Ds.coralText)),
              ),
          ],
        ),
        if (step != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(step!, style: t.caption().copyWith(fontSize: 14)),
          ),
      ],
    );
  }
}

/// The sticky bar at the foot of a screen: an ink top rule, the cream-at-94%
/// fill, and room left for the home indicator.
class DsBottomActionBar extends StatelessWidget {
  const DsBottomActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, DsLayout.homeIndicator),
      decoration: const BoxDecoration(
        color: Ds.barFill,
        border:
            Border(top: BorderSide(color: Ds.ink, width: DsShape.borderWidth)),
      ),
      child: child,
    );
  }
}

/// Striped placeholder standing in for a map that has not loaded (or is not
/// wired yet). The spec asks for stripes and a mono caption rather than a grey
/// box, so an unloaded map never reads as a broken one.
class DsMapPlaceholder extends StatelessWidget {
  const DsMapPlaceholder({super.key, this.caption, this.height = 260});

  final String? caption;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: DsShape.card,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: DsShape.card,
          border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
        ),
        child: CustomPaint(
          painter: const _StripePainter(),
          child: caption == null
              ? null
              : Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(caption!, style: context.ds.mono()),
                  ),
                ),
        ),
      ),
    );
  }
}

class _StripePainter extends CustomPainter {
  const _StripePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Ds.mapStripeA);
    final stripe = Paint()..color = Ds.mapStripeB;
    // 45° bands, drawn as a rotated rect sweep.
    const w = 14.0;
    for (var x = -size.height; x < size.width; x += w * 2) {
      final p = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + size.height, 0)
        ..lineTo(x + size.height + w, 0)
        ..lineTo(x + w, size.height)
        ..close();
      canvas.drawPath(p, stripe);
    }
  }

  @override
  bool shouldRepaint(_StripePainter oldDelegate) => false;
}

/// The spec's sticky tab bar surface: a 2px ink top edge over blurred cream.
///
/// The design system's one constant is "black-ink 2px outlines on every
/// surface", and the tab bar — the only surface visible from every screen —
/// had no edge at all, so it floated against whatever was behind it instead of
/// sitting on the page.
///
/// The blur is deliberate and narrow. The system bans blur everywhere else
/// ("no gradients, no blur except the sticky tab bar and lock screen"), and it
/// is what makes a 94%-opaque bar read as glass over content scrolling under
/// it rather than as a flat strip.
class DsTabBarSurface extends StatelessWidget {
  final Widget child;
  const DsTabBarSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      // ClipRect bounds the filter. Without it BackdropFilter samples the whole
      // layer and blurs the screen above the bar too.
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Ds.ink, width: DsShape.borderWidth),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
