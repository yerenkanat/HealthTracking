/// A glass "big number" stat tile: an icon chip, a large monospaced value, and
/// a label. The profile summary and the "Your journey" grid had each hand-rolled
/// their own private copy of this; they are the same tile and now share one.
///
/// Two icon styles, because both callers wanted one: pass [gradient] for a filled
/// gradient chip with a white glyph (profile), or [color] for a tinted chip with
/// a coloured glyph (journey). Exactly one should be given; [gradient] wins.
///
/// NOTE (intentionally not merged): the dashboard's compact tinted stat strip and
/// the water-history centred figure share the name `_StatTile` in their own files
/// but are a different design — a different shape, a unit slot, no icon — so they
/// are left as they are rather than forced through a grab-bag of options here.
library;

import 'package:flutter/material.dart';

import '../design_system.dart';
import 'glass.dart';

class StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  /// Tinted-chip style (chip = [color] at low alpha, glyph = [color]). Used when
  /// [gradient] is null.
  final Color? color;

  /// Filled-gradient chip with a white glyph. Takes precedence over [color].
  final Gradient? gradient;

  /// When set, the tile becomes a button (and shows a chevron so it reads as
  /// tappable). A tile with no [onTap] is a plain readout.
  final VoidCallback? onTap;

  const StatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color,
    this.gradient,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // In the design system the icon chip is a solid accent block with a white
    // glyph and an ink outline — the tinted-chip variant the [gradient]/[color]
    // split expressed no longer exists, so both now produce the same tile. The
    // parameters stay because 20 call sites pass them; [gradient] contributes
    // its first colour, since the system has no gradients.
    final chip = gradient?.colors.firstOrNull ?? color ?? Ds.coralCta;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: chip,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
                ),
                child: Icon(icon, color: Colors.white, size: 19),
              ),
              const Spacer(),
              if (onTap != null) const Icon(Icons.chevron_right_rounded, color: Ds.chevron, size: 20),
            ],
          ),
          const SizedBox(height: 14),
          // The display face, not mono: these are headline figures, and
          // JetBrains Mono has no ә ғ қ ң ұ for the units that follow them.
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.ds.statNumber()),
          const SizedBox(height: 2),
          Text(label, style: context.ds.caption()),
        ],
      ),
    );
  }
}
