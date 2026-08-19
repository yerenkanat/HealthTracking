/// What replaces a screen that threw.
///
/// Flutter's default is a red diagnostic panel in debug and, in RELEASE, a bare
/// grey rectangle: no words, no way out, and nothing to tell support. On an app
/// someone opens because they are worried about a reading, a silent grey
/// rectangle is close to the worst possible answer.
///
/// This replaces it with something that says what happened in her language and,
/// WHEN THERE IS ONE, the one action that reliably helps — back to the main
/// screen. When there is not, it says something else, because a screen whose
/// copy instructs an action it does not offer is its own second defect.
library;

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../ds_widgets.dart';
import '../theme.dart';

/// A calm, localized replacement for a subtree that failed to build.
///
/// [onRestart] is optional, and as [ErrorWidget.builder] — the only place this
/// is constructed in production — it cannot be supplied: that assignment runs in
/// `main()`, long before any BuildContext exists. The way out is therefore
/// derived here, from the context this widget is actually built in. See
/// [_wayOut] for what "back to the main screen" can honestly mean.
class ErrorFallback extends StatelessWidget {
  final String? details;
  final VoidCallback? onRestart;

  const ErrorFallback({super.key, this.details, this.onRestart});

  /// The one action that can be offered without lying, or null when there is
  /// none.
  ///
  /// This runs after a widget has ALREADY thrown, so the test is not "is there
  /// a button we could draw" but "is there something that genuinely recovers".
  /// Rebuilding the same subtree does not: a deterministic bug — the usual kind
  /// — throws straight back into this screen, and a button that returns you to
  /// where you already are is worse than no button. So the only offer made is
  /// the one that DISPOSES the broken subtree instead of rebuilding it: pop back
  /// to the first route.
  ///
  /// Which means it is offered only when the failure is on a PUSHED route.
  /// `route.isFirst` is that question exactly. When it is the first route — a
  /// tab of the home shell — or when there is no navigator at all — the app root
  /// itself threw — nothing here can undo it, and the copy says so instead
  /// (`err_body_restart`) rather than drawing a button that does nothing.
  ///
  /// An explicit [onRestart] wins: a caller that passes one knows something
  /// about its own recovery that this cannot infer.
  VoidCallback? _wayOut(BuildContext context) {
    final explicit = onRestart;
    if (explicit != null) return explicit;
    // Nullable lookup, never `of`: this widget exists because something above it
    // went wrong, and a throwing lookup here would replace the error screen with
    // another error screen. A non-null route also proves a Navigator is above us.
    final route = ModalRoute.of(context);
    if (route == null || route.isFirst) return null;
    return () => Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    // Deliberately does NOT read L10nScope. This widget exists precisely
    // because something above it went wrong, and an InheritedWidget lookup that
    // throws here would replace the error screen with another error screen.
    final l = L10nScope.maybeOf(context) ?? const L10n(AppLocale.ru);
    final wayOut = _wayOut(context);
    return Material(
      color: Palette.bg,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_rounded, size: 44, color: Palette.text.withValues(alpha: 0.35)),
                const SizedBox(height: 16),
                Text(
                  l.t('err_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Palette.text),
                ),
                const SizedBox(height: 8),
                Text(
                  // The copy follows the button, not the other way round. The
                  // «Вернитесь на главный экран» wording is only true when the
                  // screen actually offers that; with no way out it would be
                  // instructing an action it does not have.
                  l.t(wayOut == null ? 'err_body_restart' : 'err_body'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, height: 1.4, color: Palette.text.withValues(alpha: 0.7)),
                ),
                if (wayOut != null) ...[
                  const SizedBox(height: 20),
                  // The spec's primary CTA: coral pill, ink outline, and the
                  // 4px hard offset shadow a ButtonStyle cannot express — the
                  // reason DsPrimaryButton exists at all.
                  DsPrimaryButton(label: l.t('err_back'), onPressed: wayOut),
                ],
                // The technical detail is available but not in her face: it is
                // for the screenshot support asks for, not for her to read.
                if (details != null && details!.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  ExpansionTile(
                    title: Text(l.t('err_details'),
                        style: TextStyle(fontSize: 13, color: Palette.text.withValues(alpha: 0.6))),
                    tilePadding: EdgeInsets.zero,
                    children: [
                      SelectableText(
                        details!,
                        style: TextStyle(
                            fontSize: 12, fontFamily: 'monospace', color: Palette.text.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
