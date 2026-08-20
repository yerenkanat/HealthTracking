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
    // A card is a Material surface, even when it is not tappable, and the
    // Material has to be INSIDE the fill.
    //
    // Anything that draws its own ink — a ListTile, a Switch, a nested InkWell
    // — paints onto its nearest Material ancestor. Put that ancestor outside
    // this Container and the Container's own colour covers the ink; Flutter
    // says so directly: "the ListTile is wrapped in a DecoratedBox that has a
    // background color … this DecoratedBox will hide [the splashes]".
    //
    // GlassCard nested it this way and the profile screen depended on it
    // without anyone knowing until these stopped being GlassCards.
    final inner = Material(
      type: MaterialType.transparency,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              // Inset by the border so the ripple cannot paint over the outline.
              borderRadius: BorderRadius.circular(radius - DsShape.borderWidth),
              child: Padding(padding: padding, child: child),
            ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        // A raised card must be opaque: the hard shadow is an unblurred ink
        // rectangle behind it, and a translucent pastel would let it read
        // through and turn the card near-black.
        color: raised ? DsShape.opaque(color) : color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
        boxShadow: raised ? DsShape.hardShadow : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - DsShape.borderWidth),
        child: inner,
      ),
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
  const DsIconTile({
    super.key,
    this.glyph,
    this.icon,
    this.color = Ds.coralCta,
    this.size = 42,
  }) : assert(glyph != null || icon != null, 'a tile needs a glyph or an icon');

  /// An emoji or short text mark.
  final String? glyph;

  /// A Material icon, for the chips the app actually builds.
  ///
  /// This widget only accepted [glyph], so every icon-based chip in the app —
  /// the reminder rows, the settings rows, the appointment cards — could not
  /// use it and hand-rolled its own Container instead. That is why it had no
  /// callers: not because the chip was unwanted, but because it could only be
  /// asked for in a form nothing used.
  final IconData? icon;

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
      child: icon != null
          ? Icon(icon, color: Colors.white, size: size * 0.5)
          : Text(glyph!,
              style: context.ds.button(size: size * 0.45, color: Colors.white)),
    );
  }
}

// ---------------------------------------------------------------------------
// Data display
// ---------------------------------------------------------------------------
//
// `DsHeroMetric` and `DsStatTile` used to live here and were removed — see
// docs/design-system-app.md, "Who plays each role". Both were drawn by nothing,
// and in both cases the role was already occupied by something the screens
// could actually use:
//
//   * the hero number, because it could not carry an "as of" age. Every hero
//     figure in this app is a vital sign, and a vitals surface with no
//     freshness treatment is a reading that will be trusted when it should not
//     be. `_MetricCard` (dashboard/health_dashboard_screen.dart) is the real
//     one, and it is built from `DsCard`.
//   * the stat tile, because `widgets/stat_tile.dart` already fills that role
//     at twenty call sites, and the dashboard's private tile adds a unit slot,
//     a verdict colour and a Kazakh scale-down that the system version had no
//     way to express.
//
// Do not re-add either without a screen. Git has them.

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
                                style: t.rowLabel
                                    .copyWith(color: rows[i].labelColor))
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
///
/// Two or three mutually exclusive labels, equal width, all visible at once.
/// It is NOT a filter strip: a variable number of options, a scrolling row, or
/// anything that can be multi-selected belongs in chips, not here — an
/// `Expanded` segment gets narrower with every option added, and the fourth one
/// truncates its Kazakh at 320dp.
class DsSegmented extends StatelessWidget {
  const DsSegmented({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
    this.onClear,
    this.label,
  });

  final List<String> items;

  /// The chosen segment, or null for "nothing chosen yet".
  ///
  /// Nullable because the first screen to adopt this — onboarding step 4's
  /// «Пол» — is an OPTIONAL field on an OPTIONAL step, and the `ChoiceChip`
  /// row it replaced could show no answer at all. A segmented control that
  /// required an index would have had to open pre-answered «Мальчик», which
  /// invents a fact about someone's child, or open with the first segment
  /// falsely inked. Neither is acceptable, so the empty state is a state.
  final int? index;

  final ValueChanged<int> onChanged;

  /// Tapping the already-selected segment clears the answer.
  ///
  /// Off by default: a segmented control normally cannot be emptied, and the
  /// tab-like uses (§9.13's «Где ребёнок / Сегодня») must not be. It is opt-in
  /// per call site so that a widget swap can never quietly change what a form
  /// permits — a caller that wants a clearable field has to say so in one
  /// visible word.
  final VoidCallback? onClear;

  /// Announced to a screen reader as the group's question, since the segments
  /// themselves only say «Ұл» / «Қыз» and lose the «Жынысы» above them.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final t = context.ds;
    return Semantics(
      container: true,
      label: label,
      child: Container(
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
                child: Semantics(
                  inMutuallyExclusiveGroup: true,
                  selected: i == index,
                  button: true,
                  child: InkWell(
                    onTap: () => (i == index && onClear != null)
                        ? onClear!()
                        : onChanged(i),
                    customBorder:
                        RoundedRectangleBorder(borderRadius: DsShape.pill),
                    child: Container(
                      // 38 is the painted chip in the spec; 48 is the tap
                      // target this app holds itself to, and DsToggle already
                      // had to be corrected for the same thing. The segments
                      // are the only way to answer a question on the last step
                      // of onboarding, one-handed.
                      constraints: const BoxConstraints(
                          minHeight: DsShape.minTapTarget),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: Ds.ink, width: DsShape.borderWidth),
                        color: i == index ? Ds.ink : Colors.transparent,
                        borderRadius: DsShape.pill,
                      ),
                      // scaleDown, not ellipsis. Measured at 320dp with text
                      // at 130%: «Мальчик» wants 129.1dp and a half-width
                      // segment gives it 119.0 — 10dp short, so without this
                      // the gender control reads «Маль…», which nobody can
                      // identify. Same guard the vitals tiles use.
                      //
                      // Note which language is tight. Kazakh normally
                      // truncates first and is what the 320dp rule is written
                      // for, but «Ұл» (36.9dp) and «Қыз» (55.3dp) are the
                      // SHORT case here — Russian is the one that breaks. A
                      // segmented control has to be measured in both.
                      //
                      // Three segments are already near the floor: at the same
                      // 320dp/130%, «История» wants 129.1dp into 73.3. Four
                      // would be unreadable, which is why this widget is for
                      // two or three labels and filters belong in chips.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          items[i],
                          maxLines: 1,
                          style: t.button(
                              size: 14,
                              color: i == index
                                  ? Colors.white
                                  : Ds.textSecondary),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
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
        // The pill is 48x28 because the spec says so, but 28dp is not a tap
        // target — the guideline is 48, and the Material Switch this replaced
        // padded itself out to meet it. Adopting this widget quietly shrank the
        // target on ten rows. The pill still draws at 28; only the hit area
        // grows, centred on it.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: DsShape.minTapTarget),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
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
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chrome
// ---------------------------------------------------------------------------
//
// `DsScreenHeader` used to live here and was removed. The spec's header —
// docs/design-system-app.md:62, chevron + title + optional right action — is
// drawn by the themed `AppBar` at `theme.dart`'s `appBarTheme`, which carries
// `type.screenTitle` and the cream/ink pair, and which 71 screens already use.
// It also gets the system back gesture, the route's own pop semantics and the
// status-bar inset right; the hand-rolled Column did none of that. One entry
// per destination applies to components too.

/// The sticky bar at the foot of a screen: an ink top rule, the cream-at-94%
/// fill, and room left for the home indicator.
///
/// [fill] and [rule] exist so the two NIGHT screens (§2.17 — the contraction
/// timer and the night feed) can use THIS bar instead of hand-rolling a third
/// one. They were hand-rolling: the house rule says a repeated action goes at
/// the bottom and that this widget is what puts it there, and a bar that only
/// works on the cream canvas quietly exempts the two screens where the
/// bottom-third rule matters most — the ones used one-handed, at night, in
/// labour.
class DsBottomActionBar extends StatelessWidget {
  const DsBottomActionBar({
    super.key,
    required this.child,
    this.fill = Ds.barFill,
    this.rule = Ds.ink,
  });

  final Widget child;

  /// The bar surface. Defaults to the cream-at-94% of the light canvas.
  final Color fill;

  /// The 1px top rule. Ink on light; on the night canvas ink is invisible, so
  /// a night caller passes a colour that can actually be seen against [fill].
  final Color rule;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, DsLayout.homeIndicator),
      decoration: BoxDecoration(
        color: fill,
        border: Border(top: BorderSide(color: rule, width: DsShape.borderWidth)),
      ),
      child: child,
    );
  }
}

/// Striped placeholder standing in for a map that has not loaded (or is not
/// wired yet). The spec asks for stripes and a mono caption rather than a grey
/// box, so an unloaded map never reads as a broken one.
///
/// NO PRODUCTION CALLER TODAY, AND THAT IS NOT THE USUAL DEFECT. An audit
/// listed this among five `Ds*` widgets "drawn by no screen"; finished code
/// with no caller really is this repo's dominant defect, and three of the five
/// were deleted for it. This one is different, and re-reporting it wastes the
/// next audit's time:
///
///   The map screens take a `mapBuilder`, because the real map needs a tile
///   provider and a platform view that a widget test cannot render. THIS is
///   what those tests pass — `children_golden_test.dart:55`,
///   `narrow_phone_test.dart:348, 374, 1593, 1844`. It is a design-system test
///   double, deliberately, and it is the reason the child-map golden and the
///   320dp sweep can cover those screens at all.
///
/// It is also the honest fallback the day a tile fetch fails on a 2G
/// connection in a village, which is the state the stripes and the mono caption
/// were specified for. If it ever gains that caller, delete this note — do not
/// delete the widget for the caller count.
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
