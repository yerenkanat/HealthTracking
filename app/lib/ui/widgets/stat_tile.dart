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

import '../theme.dart';
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

  const StatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? Palette.violet;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: gradient,
              color: gradient == null ? chipColor.withValues(alpha: 0.14) : null,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: gradient != null ? Colors.white : chipColor, size: 20),
          ),
          const SizedBox(height: 14),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontFamily: 'JetBrainsMono', fontSize: 26, fontWeight: FontWeight.w700, height: 1)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Palette.textDim, fontSize: 13)),
        ],
      ),
    );
  }
}
