/// What replaces a screen that threw.
///
/// Flutter's default is a red diagnostic panel in debug and, in RELEASE, a bare
/// grey rectangle: no words, no way out, and nothing to tell support. On an app
/// someone opens because they are worried about a reading, a silent grey
/// rectangle is close to the worst possible answer.
///
/// This replaces it with something that says what happened in her language and
/// offers the one action that reliably helps — go back to the main screen.
library;

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

/// A calm, localized replacement for a subtree that failed to build.
///
/// [onRestart] is optional because this is also used as [ErrorWidget.builder],
/// where there is no navigator to return to and no context worth trusting.
class ErrorFallback extends StatelessWidget {
  final String? details;
  final VoidCallback? onRestart;

  const ErrorFallback({super.key, this.details, this.onRestart});

  @override
  Widget build(BuildContext context) {
    // Deliberately does NOT read L10nScope. This widget exists precisely
    // because something above it went wrong, and an InheritedWidget lookup that
    // throws here would replace the error screen with another error screen.
    final l = L10nScope.maybeOf(context) ?? const L10n(AppLocale.ru);
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
                  l.t('err_body'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, height: 1.4, color: Palette.text.withValues(alpha: 0.7)),
                ),
                if (onRestart != null) ...[
                  const SizedBox(height: 20),
                  FilledButton(onPressed: onRestart, child: Text(l.t('err_back'))),
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
