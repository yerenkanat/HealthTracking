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

  @override
  Widget build(BuildContext context) =>
      MamaCourseScreen(access: _access, onRetry: _load, whatsapp: _whatsapp);
}
