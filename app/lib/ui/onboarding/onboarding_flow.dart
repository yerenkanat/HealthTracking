/// Onboarding flow — first-run experience driven by the verified
/// OnboardingController. Each step is a simple page; the bottom bar advances only
/// when the step's requirements are met (canProceed). On completion it calls
/// [onComplete] with the assembled config.
///
/// The band-pairing step takes a [scanBands] callback so the real BLE scan can be
/// injected (and stubbed in tests). Localized via L10nScope.
library;

import 'package:flutter/material.dart';
import '../../domain/onboarding_controller.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';

/// A discovered band the user can pick during onboarding.
typedef DiscoveredBand = ({String id, String name});
typedef BandScanner = Stream<List<DiscoveredBand>> Function();

class OnboardingFlow extends StatefulWidget {
  final OnboardingController controller;
  final void Function(OnboardingResult) onComplete;
  final BandScanner? scanBands;
  final void Function(AppLocale)? onLocaleChange;

  const OnboardingFlow({
    super.key,
    required this.controller,
    required this.onComplete,
    this.scanBands,
    this.onLocaleChange,
  });

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final c = widget.controller;

    return StreamBuilder<void>(
      stream: c.changes,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            leading: c.stepIndex > 0
                ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: c.back)
                : null,
            title: Text(l.t('onb_step', {'n': c.stepIndex + 1, 'total': c.totalSteps})),
            elevation: 0,
          ),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: _pageFor(c.step, l),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: c.canProceed ? () => _advance(c) : null,
                child: Text(c.step == OnboardingStep.child
                    ? l.t('onb_finish')
                    : c.step == OnboardingStep.welcome
                        ? l.t('onb_get_started')
                        : l.t('onb_next')),
              ),
            ),
          ),
        );
      },
    );
  }

  void _advance(OnboardingController c) {
    final wasChild = c.step == OnboardingStep.child;
    c.next();
    if (wasChild && c.isComplete) widget.onComplete(c.build());
  }

  Widget _pageFor(OnboardingStep step, L10n l) => switch (step) {
        OnboardingStep.welcome => _Welcome(l),
        OnboardingStep.language => _LanguagePage(controller: widget.controller, onLocaleChange: widget.onLocaleChange),
        OnboardingStep.profile => _ProfilePage(controller: widget.controller),
        OnboardingStep.pairBand => _PairBandPage(controller: widget.controller, scanBands: widget.scanBands),
        OnboardingStep.child => _ChildPage(controller: widget.controller),
        OnboardingStep.done => const SizedBox.shrink(),
      };
}

class _Welcome extends StatelessWidget {
  final L10n l;
  const _Welcome(this.l);
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.spa, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 24),
        Text(l.t('onb_welcome_title'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text(l.t('onb_welcome_body'), style: const TextStyle(fontSize: 16, height: 1.4)),
      ],
    );
  }
}

class _LanguagePage extends StatelessWidget {
  final OnboardingController controller;
  final void Function(AppLocale)? onLocaleChange;
  const _LanguagePage({required this.controller, this.onLocaleChange});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    const options = [
      (AppLocale.ru, 'Русский'),
      (AppLocale.kk, 'Қазақша'),
      (AppLocale.en, 'English'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.t('onb_language_title'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        for (final (loc, label) in options)
          RadioListTile<AppLocale>(
            value: loc,
            groupValue: controller.locale,
            title: Text(label),
            onChanged: (v) {
              if (v == null) return;
              controller.setLocale(v);
              onLocaleChange?.call(v); // update the whole app's language live
            },
          ),
      ],
    );
  }
}

class _ProfilePage extends StatelessWidget {
  final OnboardingController controller;
  const _ProfilePage({required this.controller});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.t('onb_profile_title'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        TextField(
          autofocus: true,
          decoration: InputDecoration(labelText: l.t('onb_name_hint'), border: const OutlineInputBorder()),
          onChanged: controller.setDisplayName,
        ),
      ],
    );
  }
}

class _PairBandPage extends StatelessWidget {
  final OnboardingController controller;
  final BandScanner? scanBands;
  const _PairBandPage({required this.controller, this.scanBands});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.t('onb_pair_title'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(l.t('onb_pair_body'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        Expanded(
          child: scanBands == null
              ? Center(child: Text(l.t('onb_pair_skip')))
              : StreamBuilder<List<DiscoveredBand>>(
                  stream: scanBands!(),
                  builder: (context, snap) {
                    final bands = snap.data ?? const [];
                    if (bands.isEmpty) {
                      return Center(child: Text(l.t('onb_pair_scanning')));
                    }
                    return ListView(
                      children: [
                        for (final b in bands)
                          RadioListTile<String>(
                            value: b.id,
                            groupValue: controller.bandId,
                            title: Text(b.name),
                            subtitle: Text(b.id),
                            onChanged: controller.setBandId,
                          ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ChildPage extends StatelessWidget {
  final OnboardingController controller;
  const _ChildPage({required this.controller});
  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final homeSet = controller.home != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.t('onb_child_title'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        TextField(
          decoration: InputDecoration(labelText: l.t('onb_child_name_hint'), border: const OutlineInputBorder()),
          onChanged: controller.setChildName,
        ),
        const SizedBox(height: 20),
        ListTile(
          leading: const Icon(Icons.home_outlined),
          title: Text(l.t('onb_home_label')),
          trailing: homeSet
              ? Text(l.t('onb_zone_set'), style: TextStyle(color: Theme.of(context).colorScheme.primary))
              : TextButton(
                  onPressed: () => controller.setHome(const ZoneInput('Home', 43.238949, 76.889709, radiusM: 100)),
                  child: Text(l.t('onb_use_current')),
                ),
        ),
        ListTile(
          leading: const Icon(Icons.school_outlined),
          title: Text(l.t('onb_school_label')),
          trailing: controller.school != null
              ? Text(l.t('onb_zone_set'), style: TextStyle(color: Theme.of(context).colorScheme.primary))
              : TextButton(
                  onPressed: () => controller.setSchool(const ZoneInput('School', 43.25, 76.95, radiusM: 120)),
                  child: Text(l.t('onb_use_current')),
                ),
        ),
      ],
    );
  }
}
