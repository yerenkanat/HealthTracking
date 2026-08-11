/// Fetches the course, then shows it.
///
/// Split from [MamaCourseScreen] so the screen stays a pure function of what it
/// is given — that is what makes both of its states testable without a server.
/// This is the only part that knows there is a network.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../domain/course_lesson.dart';
import '../../domain/shop_catalogue.dart';
import 'mama_course_screen.dart';

class CourseRoute extends StatefulWidget {
  final AppController controller;
  const CourseRoute({super.key, required this.controller});

  @override
  State<CourseRoute> createState() => _CourseRouteState();
}

class _CourseRouteState extends State<CourseRoute> {
  CourseAccess? _access;

  /// The WhatsApp number the offer's contact button opens. Empty until the
  /// public storefront config answers, and empty for good if it never does —
  /// which hides the button rather than opening a chat with nobody.
  String _whatsapp = '';

  /// What the комплект costs today. Empty until `/shop/products` answers, and
  /// the price card then shows the compile-time constants labelled as
  /// approximate — never a stale figure presented as current.
  ShopCatalogue _catalogue = ShopCatalogue.empty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = widget.controller.api;
    if (api == null) {
      // No server configured (a dev build with no API_BASE). Falling back to
      // "not entitled" shows the offer, which is the honest thing to show
      // somebody whose app cannot check what she owns.
      if (mounted) setState(() => _access = CourseAccess.none);
      return;
    }
    // Fetched alongside, not after: the contact is only needed when she is NOT
    // entitled, but waiting for the entitlement answer first would leave the
    // offer's button missing for a beat and then appear under her thumb.
    unawaited(api.getShopContact().then((c) {
      if (mounted && c.whatsapp.isNotEmpty) setState(() => _whatsapp = c.whatsapp);
    }));
    // Same reasoning for the prices. getShopCatalogue never throws — an
    // unreachable shop leaves the card on its constants, which it labels.
    unawaited(api.getShopCatalogue().then((c) {
      if (mounted && c.products.isNotEmpty) setState(() => _catalogue = c);
    }));
    try {
      final access = await api.getCourse();
      if (mounted) setState(() => _access = access);
    } catch (_) {
      // A failed request must not look like an empty course she paid for.
      // CourseAccess.none draws the offer, which is wrong for a buyer but
      // recoverable — pull to refresh retries.
      if (mounted) setState(() => _access = CourseAccess.none);
    }
  }

  /// Where the player got to.
  ///
  /// Two things at once, and both matter. The local state is updated first, so
  /// coming back from a lesson shows the tick immediately instead of after a
  /// round trip. Then it is sent, and the send is allowed to fail silently —
  /// this fires while a video is playing and an error over it would be worse
  /// than losing ten seconds of position.
  void _onProgress(LessonProgress p) {
    final a = _access;
    if (a != null && mounted) setState(() => _access = a.withProgress(p));
    final api = widget.controller.api;
    if (api == null) return;
    unawaited(api.putCourseProgress(
      lessonId: p.lessonId,
      positionSeconds: p.positionSeconds,
      durationSeconds: p.durationSeconds,
      completed: p.completed,
    ));
  }

  @override
  Widget build(BuildContext context) => MamaCourseScreen(
        access: _access,
        onRetry: _load,
        onProgress: _onProgress,
        whatsapp: _whatsapp,
        catalogue: _catalogue,
      );
}
