/// Screen 19 — «Скелет загрузки»: «повторяет раскладку главной».
///
/// WHY A SKELETON RATHER THAN A SPINNER
///
/// A centred `CircularProgressIndicator` tells her that something is happening
/// and nothing about what. Then the real screen arrives and everything jumps
/// into place at once. A skeleton that repeats the layout does two things a
/// spinner cannot: it says what is coming, and when the content lands nothing
/// moves — the blocks were already the right size in the right places.
///
/// ON THE SHIMMER. It runs at a deliberately slow, low-contrast cycle. This app
/// is opened at three in the morning by somebody holding a baby; a bright pulse
/// at that hour is unkind, and a fast one reads as urgency the screen does not
/// mean. It also stops entirely when the platform asks for reduced motion,
/// which is a real accessibility setting and not a preference to ignore.
///
/// ON HONESTY. A skeleton is a promise that content is COMING. It must never be
/// shown for a request that has already failed, or for an empty result — a
/// permanent skeleton is a screen that lies about loading forever. Callers show
/// this only while a request is genuinely in flight.
library;

import 'package:flutter/material.dart';

import '../design_system.dart';
import '../theme.dart';

/// One grey block standing in for a piece of content.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        // Tinted from the surface rather than a flat grey, so the skeleton
        // belongs to this app's palette instead of looking like a system
        // placeholder dropped on top of it.
        color: Ds.ink.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Wraps skeleton blocks in a slow shimmer.
///
/// Honours [MediaQuery.disableAnimationsOf]: with reduced motion on, the
/// blocks are simply still. A shimmer is decoration, and decoration is the
/// first thing to drop when somebody has asked for less movement.
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    // Slow on purpose. See the note at the top of the file.
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_c.isAnimating) _c.stop();
      return widget.child;
    }
    if (!_c.isAnimating) _c.repeat(reverse: true);
    return AnimatedBuilder(
      animation: _c,
      // The subtree does not depend on the animation, so it is built ONCE and
      // handed to the builder rather than rebuilt sixty times a second.
      child: widget.child,
      builder: (_, child) => Opacity(
        opacity: 0.55 + 0.30 * _c.value,
        child: child,
      ),
    );
  }
}

/// The home screen's shape, before the home screen exists.
///
/// Deliberately mirrors the real layout: greeting, the hero card, the row of
/// quick actions, then the list of cards. If the home screen's structure
/// changes, this should change with it — a skeleton that promises a layout the
/// app no longer has is worse than a spinner, because the content arriving
/// then jumps exactly as far as the skeleton was wrong.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.bg,
      body: SafeArea(
        child: Shimmer(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            // Nothing here scrolls meaningfully, and letting it bounce invites
            // a pull-to-refresh gesture on a screen with nothing to refresh.
            physics: const NeverScrollableScrollPhysics(),
            children: const [
              // Greeting: «Доброе утро, Айгерім» + the date beneath.
              SkeletonBox(width: 190, height: 24, radius: 8),
              SizedBox(height: 8),
              SkeletonBox(width: 120, height: 14, radius: 7),
              SizedBox(height: 22),

              // The hero card — the week of pregnancy, or the child's day.
              SkeletonBox(height: 168, radius: 22),
              SizedBox(height: 16),

              // Quick actions.
              Row(children: [
                Expanded(child: SkeletonBox(height: 76, radius: 18)),
                SizedBox(width: 12),
                Expanded(child: SkeletonBox(height: 76, radius: 18)),
                SizedBox(width: 12),
                Expanded(child: SkeletonBox(height: 76, radius: 18)),
              ]),
              SizedBox(height: 20),

              // The cards below: today's content, then whatever follows.
              SkeletonBox(height: 108, radius: 20),
              SizedBox(height: 12),
              SkeletonBox(height: 108, radius: 20),
              SizedBox(height: 12),
              SkeletonBox(height: 108, radius: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// A list-shaped skeleton, for screens that are a list rather than the home
/// layout — orders, notifications, the day's events.
class ListSkeleton extends StatelessWidget {
  final int rows;
  final double rowHeight;

  const ListSkeleton({super.key, this.rows = 5, this.rowHeight = 84});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.bg,
      body: SafeArea(
        child: Shimmer(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            physics: const NeverScrollableScrollPhysics(),
            itemCount: rows,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, __) => SkeletonBox(height: rowHeight, radius: 18),
          ),
        ),
      ),
    );
  }
}
