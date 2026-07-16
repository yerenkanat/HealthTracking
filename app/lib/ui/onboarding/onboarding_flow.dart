/// Onboarding flow — first-run experience driven by the verified
/// OnboardingController. Each step is a simple page; the bottom bar advances only
/// when the step's requirements are met (canProceed). On completion it calls
/// [onComplete] with the assembled config.
///
/// The band-pairing step takes a [scanBands] callback so the real BLE scan can be
/// injected (and stubbed in tests). Localized via L10nScope.
library;

import 'package:flutter/material.dart';
import '../../domain/country_codes.dart';
import '../../domain/family.dart';
import '../../domain/onboarding_controller.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/glass.dart';

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
        return AuroraBackground(
          child: Scaffold(
          backgroundColor: Colors.transparent,
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
    final dial = controller.dialCode;
    return ListView(
      children: [
        Text(l.t('onb_profile_title'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        TextField(
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: l.t('onb_name_hint')),
          onChanged: controller.setDisplayName,
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Country / dial-code picker
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: Palette.glass,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Palette.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _dialValue(dial),
                  dropdownColor: Palette.surfaceHi,
                  borderRadius: BorderRadius.circular(16),
                  onChanged: (v) {
                    if (v != null) controller.setDialCode(v.split('|')[1]);
                  },
                  items: [
                    for (final country in countries)
                      DropdownMenuItem(
                        value: '${country.iso}|${country.dial}',
                        child: Text('${country.flag} ${country.dial}',
                            style: const TextStyle(fontSize: 15)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: l.t('onb_phone_hint')),
                onChanged: controller.setPhoneNumber,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _ExpectingSection(controller: controller),
      ],
    );
  }

  // DropdownButton needs unique values; dial codes repeat (KZ/RU = +7), so we key
  // by "iso|dial" and default to the first country matching the current dial.
  String _dialValue(String dial) {
    final match = countries.firstWhere((c) => c.dial == dial, orElse: () => defaultCountry);
    return '${match.iso}|${match.dial}';
  }
}

/// "Are you expecting?" — sets pregnancy vs cycle mode from day one. When on,
/// reveals a due-date picker (optional; the calendar can also set it later).
class _ExpectingSection extends StatelessWidget {
  final OnboardingController controller;
  const _ExpectingSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Palette.glass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Palette.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: controller.expecting,
            onChanged: controller.setExpecting,
            title: Text(l.t('onb_expecting'), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(l.t('onb_expecting_sub'), style: const TextStyle(fontSize: 12.5)),
          ),
          if (controller.expecting)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_month_rounded, color: Palette.violet),
              title: Text(controller.dueDate == null
                  ? l.t('cal_due_pick')
                  : l.t('onb_due_date_set', {'date': MaterialLocalizations.of(context).formatMediumDate(controller.dueDate!)})),
              trailing: const Icon(Icons.chevron_right, color: Palette.textDim),
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: controller.dueDate ?? now.add(const Duration(days: 140)),
                  firstDate: now.subtract(const Duration(days: 60)),
                  lastDate: now.add(const Duration(days: 300)),
                  helpText: l.t('cal_due_pick'),
                );
                if (picked != null) controller.setDueDate(picked);
              },
            ),
        ],
        ),
      ),
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
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cake_outlined),
          title: Text(l.t('child_dob_hint')),
          subtitle: Text(l.t('child_dob_help'), style: const TextStyle(fontSize: 12)),
          trailing: controller.childDob != null
              ? Text(MaterialLocalizations.of(context).formatMediumDate(controller.childDob!),
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600))
              : const Icon(Icons.chevron_right),
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: controller.childDob ?? DateTime(now.year - 4, now.month, now.day),
              firstDate: DateTime(now.year - 18),
              lastDate: now,
              helpText: l.t('child_dob_hint'),
            );
            if (picked != null) controller.setChildDob(picked);
          },
        ),
        const SizedBox(height: 12),
        Row(children: [
          Text(l.t('child_gender'), style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          for (final g in Gender.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(g == Gender.boy ? Icons.boy : Icons.girl, size: 18,
                    color: controller.childGender == g ? Palette.violet : Palette.textDim),
                label: Text(l.t('gender_${g.name}')),
                selected: controller.childGender == g,
                onSelected: (_) => controller.setChildGender(controller.childGender == g ? null : g),
              ),
            ),
        ]),
        const SizedBox(height: 12),
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
