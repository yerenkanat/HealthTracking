/// The Ма!Ма! course.
///
/// Two screens in one, and the difference matters commercially:
///
///   * NOT entitled — this is an offer, not an error. It says what the course
///     is and that the комплект includes it. A locked door with a sign sells
///     the bundle; a locked door with no sign looks broken and costs a sale.
///   * Entitled — the lessons, in order, each opening on YouTube.
///
/// The gate is the SERVER's answer, not a flag this screen decides. It asks
/// GET /course/lessons and draws what comes back.
///
/// YouTube opens externally on purpose: their terms require their player and
/// their branding, which is the same rule the timeline content already follows.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/course_lesson.dart';
import '../../l10n/l10n_scope.dart';
import '../ds_widgets.dart';
import '../theme.dart';

class MamaCourseScreen extends StatelessWidget {
  /// Null while loading; [CourseAccess.none] when the request failed, which
  /// draws the offer rather than an error — the course being unreachable and
  /// the course not being bought look the same to someone who has not bought it.
  final CourseAccess? access;
  final Future<void> Function()? onRetry;

  /// Injected so the test can assert what would be opened without launching a
  /// browser.
  final Future<bool> Function(Uri url)? launch;

  const MamaCourseScreen({super.key, required this.access, this.onRetry, this.launch});

  Future<void> _open(BuildContext context, CourseLesson lesson) async {
    final uri = Uri.tryParse(lesson.youtubeUrl);
    if (uri == null) return;
    final opener = launch ?? (u) => launchUrl(u, mode: LaunchMode.externalApplication);
    final ok = await opener(uri);
    if (!ok && context.mounted) {
      // Saying nothing here leaves a tap that did nothing, which reads as a
      // broken lesson rather than a missing YouTube app.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10nScope.of(context).t('course_open_failed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final a = access;

    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(title: Text(l.t('course_title'))),
      body: a == null
          ? const Center(child: CircularProgressIndicator())
          : a.entitled
              ? _Lessons(access: a, onTap: (x) => _open(context, x), onRetry: onRetry)
              : const _Offer(),
    );
  }
}

/// What somebody who has not bought the комплект sees.
class _Offer extends StatelessWidget {
  const _Offer();

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        DsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.play_circle_outline_rounded, size: 40, color: Palette.rose),
              const SizedBox(height: 12),
              Text(l.t('course_locked_title'),
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(l.t('course_locked_body'),
                  style: const TextStyle(color: Palette.textDim, height: 1.45)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Lessons extends StatelessWidget {
  final CourseAccess access;
  final void Function(CourseLesson) onTap;
  final Future<void> Function()? onRetry;
  const _Lessons({required this.access, required this.onTap, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    // Entitled but empty is its own state: she paid, and the lessons are not up
    // yet. Showing the offer here would tell a customer to buy what she owns.
    if (access.lessons.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(l.t('course_empty'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Palette.textDim, height: 1.45)),
        ),
      );
    }

    final lang = l.locale.name;
    return RefreshIndicator(
      onRefresh: () async => onRetry?.call(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: access.lessons.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final lesson = access.lessons[i];
          final summary = lesson.summary(lang);
          return DsCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              leading: CircleAvatar(
                backgroundColor: Palette.pink,
                child: Text('${i + 1}',
                    style: const TextStyle(color: Palette.rose, fontWeight: FontWeight.w700)),
              ),
              title: Text(lesson.title(lang),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: summary == null ? null : Text(summary),
              trailing: const Icon(Icons.open_in_new_rounded, size: 20, color: Palette.textDim),
              onTap: () => onTap(lesson),
            ),
          );
        },
      ),
    );
  }
}
