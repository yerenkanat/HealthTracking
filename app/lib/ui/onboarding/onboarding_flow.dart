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
import '../../data/device_location.dart';
import '../../l10n/l10n_scope.dart';
import '../settings/legal_screen.dart';
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
  // Consent to the privacy policy and terms, captured on the welcome screen.
  // Kept in the UI layer (not the OnboardingController) so the step state
  // machine and its verify suite are untouched — it only gates the first
  // "Get started" tap.
  bool _consented = false;

  void _openLegal(BuildContext context, LegalDoc doc) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => LegalScreen(doc: doc)),
      );

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final c = widget.controller;
    // On the welcome step she must accept the policy before continuing.
    final blockedForConsent = c.step == OnboardingStep.welcome && !_consented;

    return StreamBuilder<void>(
      stream: c.changes,
      builder: (context, _) {
        return AuroraBackground(
          child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            leading: c.stepIndex > 0
                ? IconButton(
                    // Unlabelled, a screen reader announced only "button" —
                    // on every onboarding step after the first.
                    tooltip: l.t('onb_back'),
                    icon: const Icon(Icons.arrow_back),
                    onPressed: c.back,
                  )
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
                onPressed: (c.canProceed && !blockedForConsent) ? () => _advance(c) : null,
                // On the child step the label depends on whether she is adding
                // one. Saying "Finish" over an untouched form reads as though
                // something is missing; "Skip for now" says plainly that it is
                // optional, which is the fact that used to be hidden behind a
                // permanently greyed-out button.
                child: Text(c.step == OnboardingStep.child
                    ? (c.hasChild ? l.t('onb_finish') : l.t('onb_child_skip'))
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
        OnboardingStep.welcome => _Welcome(
            l,
            consented: _consented,
            onConsentChanged: (v) => setState(() => _consented = v),
            onOpenPrivacy: () => _openLegal(context, LegalDoc.privacy),
            onOpenTerms: () => _openLegal(context, LegalDoc.terms),
          ),
        OnboardingStep.language => _LanguagePage(controller: widget.controller, onLocaleChange: widget.onLocaleChange),
        OnboardingStep.profile => _ProfilePage(controller: widget.controller),
        OnboardingStep.pairBand => _PairBandPage(controller: widget.controller, scanBands: widget.scanBands),
        OnboardingStep.child => _ChildPage(controller: widget.controller),
        OnboardingStep.done => const SizedBox.shrink(),
      };
}

class _Welcome extends StatelessWidget {
  final L10n l;
  final bool consented;
  final ValueChanged<bool> onConsentChanged;
  final VoidCallback onOpenPrivacy;
  final VoidCallback onOpenTerms;
  const _Welcome(
    this.l, {
    required this.consented,
    required this.onConsentChanged,
    required this.onOpenPrivacy,
    required this.onOpenTerms,
  });
  @override
  Widget build(BuildContext context) {
    // Centred but SCROLLABLE. A fixed Column centres nicely at the default font
    // size and then runs 114px off the bottom once a user enlarges her system
    // text — on the very first screen of the app, before she has any reason to
    // trust it. Wrapping in a scroll view keeps the centred look while letting
    // the words have the room they need.
    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height * 0.6),
        child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.spa, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 24),
        Text(l.t('onb_welcome_title'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text(l.t('onb_welcome_body'), style: const TextStyle(fontSize: 16, height: 1.4)),
        const SizedBox(height: 28),
        // Consent, captured before she can proceed. A CheckboxListTile so the
        // label is part of the tap target and carries the accessible name (a
        // bare Checkbox is an unlabeled tap target). The two documents are one
        // tap away beneath it.
        CheckboxListTile(
          value: consented,
          onChanged: (v) => onConsentChanged(v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Text(l.t('onb_consent_label'),
              style: const TextStyle(fontSize: 13.5, height: 1.4)),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 48),
          child: Wrap(
            spacing: 4,
            children: [
              TextButton(
                onPressed: onOpenPrivacy,
                style: TextButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: Text(l.t('set_privacy')),
              ),
              TextButton(
                onPressed: onOpenTerms,
                style: TextButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: Text(l.t('set_terms')),
              ),
            ],
          ),
        ),
      ],
        ),
      ),
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
        RadioGroup<AppLocale>(
          groupValue: controller.locale,
          onChanged: (v) {
            if (v == null) return;
            controller.setLocale(v);
            onLocaleChange?.call(v); // update the whole app's language live
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (loc, label) in options)
                RadioListTile<AppLocale>(value: loc, title: Text(label)),
            ],
          ),
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
                  initialDate: controller.dueDate ?? now.add(const Duration(days: 140)), // elapsed-ok: a picker default
                  firstDate: now.subtract(const Duration(days: 60)), // elapsed-ok: a generous picker bound
                  lastDate: now.add(const Duration(days: 300)), // elapsed-ok: a generous picker bound
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
                    return RadioGroup<String>(
                      groupValue: controller.bandId,
                      onChanged: controller.setBandId,
                      child: ListView(
                        children: [
                          for (final b in bands)
                            RadioListTile<String>(
                              value: b.id,
                              title: Text(b.name),
                              subtitle: Text(b.id),
                            ),
                        ],
                      ),
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
    // ListView, not Column: this page carries a name field, a date row, gender
    // chips and two zone tiles, and at 360dp in Russian that is 27px taller
    // than the screen. The profile step already scrolls; this one did not, so
    // the last step of onboarding clipped its own controls.
    return ListView(
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
        // Wrap, not Row: a label plus two chips is wider than 360dp once the
        // words are Russian — 64px past the edge — and this is the last step of
        // onboarding, where a clipped control is the difference between
        // finishing and giving up.
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          children: [
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
        ],
        ),
        const SizedBox(height: 12),
        _ZoneTile(
          icon: Icons.home_outlined,
          label: l.t('onb_home_label'),
          isSet: homeSet,
          radiusM: 100,
          onPicked: controller.setHome,
        ),
        _ZoneTile(
          icon: Icons.school_outlined,
          label: l.t('onb_school_label'),
          isSet: controller.school != null,
          radiusM: 120,
          onPicked: controller.setSchool,
        ),
      ],
    );
  }
}

/// "Home" / "School" during onboarding: set this zone to where the phone is.
///
/// Two things were wrong here before.
///
/// It never asked the device. `setHome(const ZoneInput('Home', 43.238949,
/// 76.889709))` wrote the SAME Almaty coordinate for every user in the country,
/// so a family in Astana finished onboarding with a home zone six hundred
/// kilometres away — and every geofence alert after that was about a street
/// they had never seen. A hardcoded constant behind a button labelled "use
/// current location" is the kind of placeholder that survives to production
/// because nothing looks broken.
///
/// And the zone was named in English while the rest of the app names it with
/// l.t('onb_home_label') — so the same zone was "Home" if created here and
/// "Дом" if created from the family sheet, which is what broke
/// distanceFromHomeM for Russian users.
///
/// The trailing action is also width-constrained: an unbounded TextButton in a
/// ListTile's trailing slot threw "Trailing widget consumes the entire tile
/// width" at 360dp, in every language.
class _ZoneTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSet;
  final double radiusM;
  final void Function(ZoneInput) onPicked;

  const _ZoneTile({
    required this.icon,
    required this.label,
    required this.isSet,
    required this.radiusM,
    required this.onPicked,
  });

  @override
  State<_ZoneTile> createState() => _ZoneTileState();
}

class _ZoneTileState extends State<_ZoneTile> {
  bool _busy = false;

  Future<void> _use() async {
    setState(() => _busy = true);
    final result = await currentCoordinates();
    if (!mounted) return;
    setState(() => _busy = false);

    if (result.ok) {
      widget.onPicked(ZoneInput(
        widget.label, // the localized name, matching the rest of the app
        result.coords!.lat,
        result.coords!.lng,
        radiusM: widget.radiusM,
      ));
      return;
    }
    // Say what went wrong and what to do instead. Failing silently here would
    // leave the zone unset with no explanation, on the step that gates
    // finishing onboarding.
    final l = L10nScope.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.t(result.messageKey!)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Palette.danger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(widget.icon),
      title: Text(widget.label),
      trailing: ConstrainedBox(
        // Bounded, or a long label — "Использовать текущее" — takes the whole
        // tile and Flutter asserts rather than laying out.
        constraints: const BoxConstraints(maxWidth: 150),
        child: widget.isSet
            ? Text(
                l.t('onb_zone_set'),
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              )
            : TextButton(
                onPressed: _busy ? null : _use,
                child: _busy
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(
                        l.t('onb_use_current'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
      ),
    );
  }
}
