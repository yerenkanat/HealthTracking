/// Onboarding flow — first-run experience driven by the verified
/// OnboardingController. Each step is a simple page; the bottom bar advances only
/// when the step's requirements are met (canProceed). On completion it calls
/// [onComplete] with the assembled config.
///
/// The band-pairing step takes a [scanBands] callback so the real BLE scan can be
/// injected (and stubbed in tests). Localized via L10nScope.
library;

import 'package:flutter/material.dart';
import '../../ble/band_scan_state.dart';
import '../../domain/country_codes.dart';
import '../../domain/family.dart';
import '../../domain/onboarding_controller.dart';
import '../../l10n/l10n.dart';
import '../../data/device_location.dart';
import '../../l10n/l10n_scope.dart';
import '../settings/legal_screen.dart';
import '../design_system.dart';
import '../ds_widgets.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import '../widgets/phone_format.dart';

/// [DiscoveredBand] used to be declared here, which is why `ble/band_scan.dart`
/// imported a UI file to describe its own output. It now lives with the scan
/// state it belongs to and is re-exported so existing importers keep working.
export '../../ble/band_scan_state.dart'
    show BandScanPhase, BandScanUpdate, DiscoveredBand, isStrongSignal;

/// The pairing scan. Emits what it is doing AND why it has found nothing — see
/// [BandScanUpdate]. It used to emit a bare list, so four different reasons for
/// an empty one looked identical on the screen.
typedef BandScanner = Stream<BandScanUpdate> Function();

/// Asks the OS to switch Bluetooth on, for the «Включить Bluetooth» button.
/// Resolves to whether the radio is on afterwards. Null on platforms where no
/// such API exists (iOS) — the button is then not offered rather than offered
/// and silently doing nothing.
typedef BluetoothEnabler = Future<bool> Function();

class OnboardingFlow extends StatefulWidget {
  final OnboardingController controller;
  final void Function(OnboardingResult) onComplete;
  final BandScanner? scanBands;

  /// Passed through to the pairing step's «Включить Bluetooth» button.
  final BluetoothEnabler? onEnableBluetooth;
  final void Function(AppLocale)? onLocaleChange;

  const OnboardingFlow({
    super.key,
    required this.controller,
    required this.onComplete,
    this.scanBands,
    this.onEnableBluetooth,
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Why the button is grey.
                  //
                  // It was grey and silent on two of the five steps — the
                  // consent step and the name/phone step — and a disabled
                  // control that gives no reason is where onboarding is
                  // abandoned: she cannot tell whether she missed something or
                  // the app is broken. The checkbox sits far left of its label
                  // and the phone field looks filled in the moment it has any
                  // digits at all, so neither cause is obvious.
                  //
                  // Said BEFORE she taps, not after: a message that only
                  // appears on a dead tap has already cost her the guess.
                  if (_blockReason(c, l, blockedForConsent) case final why?) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        key: const Key('onb-block-reason'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              size: 16, color: Palette.textDim),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(why,
                                style: const TextStyle(
                                    fontSize: 13, color: Palette.textDim, height: 1.35)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  FilledButton(
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
                ],
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
        OnboardingStep.pairBand => _PairBandPage(
            controller: widget.controller,
            scanBands: widget.scanBands,
            onEnableBluetooth: widget.onEnableBluetooth,
          ),
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

/// A controller seeded with what the model already holds, caret at the end.
///
/// Every text field on this flow needs one. A [TextField] with no `controller:`
/// makes a private one, empty, on each fresh [State] — so a page that is rebuilt
/// from scratch paints an empty box over data the app still has.
TextEditingController _seededField(String text) => TextEditingController.fromValue(
      TextEditingValue(
        text: text,
        // Not the default TextEditingController(text:) — that leaves the
        // selection at offset -1, and a field she taps into then has to guess
        // where the caret goes.
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );

/// Bring a field back in line with the model — and ONLY when they truly differ.
///
/// The unguarded version (`field.text = value` on every build) is a worse bug
/// than the one being fixed: assigning `.text` resets the selection, so the
/// caret jumps out of the word she is in the middle of typing, on every
/// keystroke. She types "Aigerim" and gets "mireagi".
void _syncField(TextEditingController field, String value) {
  if (field.text == value) return;
  field.value = TextEditingValue(
    text: value,
    selection: TextSelection.collapsed(offset: value.length),
  );
}

/// Step 3 — her name and phone.
///
/// Stateful for one reason: it owns the two [TextEditingController]s, so it can
/// dispose them. It was a StatelessWidget with two uncontrolled [TextField]s,
/// and that is how the name went missing.
///
/// Deny the Bluetooth permission on the next step and the flow bounces back
/// here. A bounce builds a NEW [State], the fields' private controllers were
/// born empty, and the page painted an empty name over an
/// `OnboardingController` that still held "Aigerim". Nothing was ever lost —
/// only the display of it — which is exactly why «Далее» stayed enabled over an
/// apparently blank required field and moved her on: [OnboardingController.canProceed]
/// reads the model, and the model was intact. The pregnancy switch beside it
/// survived for the same reason: it reads the model on every build, as these
/// fields now do.
class _ProfilePage extends StatefulWidget {
  final OnboardingController controller;
  const _ProfilePage({required this.controller});

  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<_ProfilePage> {
  late final TextEditingController _name = _seededField(widget.controller.displayName);
  late final TextEditingController _phone = _seededField(widget.controller.phoneNumber);

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final controller = widget.controller;
    final dial = controller.dialCode;
    // The model can also be written from outside these fields (the flow rebuilds
    // on every change it publishes), so follow it here too — guarded, so typing
    // is never overwritten mid-word.
    _syncField(_name, controller.displayName);
    _syncField(_phone, controller.phoneNumber);
    return ListView(
      children: [
        Text(l.t('onb_profile_title'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        TextField(
          controller: _name,
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
                border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
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
                controller: _phone,
                keyboardType: TextInputType.phone,
                // Grouped as she types. Eleven unbroken digits cannot be
                // checked at a glance, and this is the number her whole
                // account hangs off.
                inputFormatters: [PhoneGroupFormatter(dial: controller.dialCode)],
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
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
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

/// Onboarding step 5 — «Есть устройство Ana-Bala?».
///
/// This page could say two things: «Поиск устройств…» and a list of watches.
/// Everything else the transport can produce — Bluetooth switched off, the
/// permission declined, a handset with no radio at all, a scan that would not
/// start, and the ordinary case of nothing being nearby — arrived as the same
/// empty list, so all five rendered as the scanning line, for ever. A woman
/// whose phone simply had Bluetooth off was never told the one fact she needed,
/// and could not tell a broken app from a broken watch.
///
/// It now renders one state per [BandScanPhase], each with its own sentence and
/// its own action. What it deliberately does NOT show is anything about
/// connecting: this step records the id she picks and the link is made after
/// onboarding, so "connecting", "connected" and "connection refused" have no
/// truth to draw from here. They live on [BandLinkState] and are shown by the
/// dashboard.
class _PairBandPage extends StatefulWidget {
  final OnboardingController controller;
  final BandScanner? scanBands;
  final BluetoothEnabler? onEnableBluetooth;
  const _PairBandPage({
    required this.controller,
    this.scanBands,
    this.onEnableBluetooth,
  });

  @override
  State<_PairBandPage> createState() => _PairBandPageState();
}

class _PairBandPageState extends State<_PairBandPage> {
  /// Bumped by «Искать снова» — a new key rebuilds the StreamBuilder against a
  /// fresh scan rather than re-listening to a stream that has already settled.
  int _attempt = 0;

  /// She tapped «Пока нет — буду записывать вручную». Not a dead end: it is the
  /// state that says what the app does without a watch, which is most of it.
  bool _decidedManual = false;

  Stream<BandScanUpdate>? _stream;
  int _streamKey = -1;

  Stream<BandScanUpdate>? _scan() {
    final scan = widget.scanBands;
    if (scan == null) return null;
    // Built once per attempt: StreamBuilder rebuilds on every setState, and
    // calling scanBands() in build would start a new radio scan each time.
    if (_streamKey != _attempt || _stream == null) {
      _streamKey = _attempt;
      _stream = scan();
    }
    return _stream;
  }

  void _retry() => setState(() {
        _decidedManual = false;
        _attempt++;
      });

  Future<void> _enableBluetooth() async {
    final enable = widget.onEnableBluetooth;
    if (enable == null) return;
    final on = await enable();
    if (!mounted) return;
    // Only a radio that actually came on earns a fresh scan. A refusal at the
    // system dialog leaves the «Bluetooth выключен» plate where it is, which is
    // still true — the alternative is a spinner that will never resolve.
    if (on) _retry();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final stream = _scan();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.t('onb_pair_title'),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Expanded(
          child: _decidedManual || stream == null
              // No scanner injected (a desktop or test build) is the same
              // situation as choosing to log by hand: there is no radio path,
              // so say what the app does without one instead of showing a
              // search that cannot happen.
              ? ListView(padding: EdgeInsets.zero, children: [
                  _Subtitle(l.t('onb_pair_hint')),
                  const SizedBox(height: 16),
                  _manualPlate(l),
                ])
              : StreamBuilder<BandScanUpdate>(
                  key: ValueKey(_attempt),
                  stream: stream,
                  builder: (context, snap) {
                    final update = snap.data ?? BandScanUpdate.opening;
                    return ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        // The subtitle is built from the SAME frame as the slot
                        // below it: «выберите из списка» is only true when
                        // there is a list, and printed over an empty area it is
                        // the sentence that made the step read as broken.
                        _Subtitle(l.t(update.phase == BandScanPhase.found
                            ? 'onb_pair_body'
                            : 'onb_pair_hint')),
                        const SizedBox(height: 16),
                        ..._slotFor(context, l, update),
                        const SizedBox(height: 8),
                        _manualLink(l),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  List<Widget> _slotFor(BuildContext context, L10n l, BandScanUpdate u) {
    switch (u.phase) {
      case BandScanPhase.scanning:
        return [_ScanningCard(label: l.t('onb_pair_scanning'))];

      case BandScanPhase.found:
        return [
          _FoundList(
            bands: u.bands,
            selected: widget.controller.bandId,
            onSelect: widget.controller.setBandId,
          ),
          if (u.searching) ...[
            const SizedBox(height: 6),
            _ScanningLine(label: l.t('onb_pair_scanning_more')),
          ],
        ];

      case BandScanPhase.noneNearby:
        return [
          _StatePlate(
            key: const Key('onb-pair-none'),
            title: l.t('onb_pair_none_title'),
            body: l.t('onb_pair_none_body'),
          ),
          _RetryButton(label: l.t('onb_pair_retry'), onTap: _retry),
        ];

      case BandScanPhase.bluetoothOff:
        return [
          _StatePlate(
            key: const Key('onb-pair-bluetooth-off'),
            title: l.t('onb_pair_bt_off_title'),
            body: l.t('onb_pair_bt_off_body'),
          ),
          // Android can be asked to switch it on; iOS cannot, and there the
          // honest offer is to look again once she has done it herself.
          if (widget.onEnableBluetooth != null)
            _RetryButton(
                label: l.t('onb_pair_bt_on'),
                icon: Icons.bluetooth_rounded,
                onTap: _enableBluetooth)
          else
            _RetryButton(label: l.t('onb_pair_retry'), onTap: _retry),
        ];

      case BandScanPhase.permissionDenied:
        return [
          _StatePlate(
            key: const Key('onb-pair-permission'),
            title: l.t('onb_pair_perm_title'),
            body: l.t('onb_pair_perm_body'),
          ),
          _RetryButton(label: l.t('onb_pair_retry'), onTap: _retry),
        ];

      case BandScanPhase.unsupported:
        // The one state with no retry: a phone does not grow a radio. The way
        // forward is the manual route, and it is the next thing on the screen.
        return [
          _StatePlate(
            key: const Key('onb-pair-unsupported'),
            title: l.t('onb_pair_unsupported_title'),
            body: l.t('onb_pair_unsupported_body'),
          ),
        ];

      case BandScanPhase.failed:
        return [
          _StatePlate(
            key: const Key('onb-pair-failed'),
            title: l.t('onb_pair_failed_title'),
            body: l.t('onb_pair_failed_body'),
          ),
          _RetryButton(label: l.t('onb_pair_retry'), onTap: _retry),
        ];
    }
  }

  Widget _manualLink(L10n l) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: const Key('onb-pair-no-device'),
          onPressed: () => setState(() {
            _decidedManual = true;
            widget.controller.setBandId(null);
          }),
          style: TextButton.styleFrom(
              foregroundColor: Palette.violetText,
              minimumSize: const Size(0, DsShape.minTapTarget)),
          // `onb_pair_skip` («Пропустить»), NOT `onb_pair_no_device`.
          //
          // That key read «Пока нет — буду записывать вручную» and was the FIRST
          // thing offered to a woman without a bracelet. Hand entry of vitals
          // was removed on 2026-08-18, so it promised a screen that no longer
          // exists — found by running the app, after every suite passed.
          //
          // `onb_pair_skip` already existed and had no caller. It says only what
          // is true: she can move on. It does not claim she will be able to
          // record anything by hand, and it does not claim the opposite either,
          // which is not this control's job to answer.
          child: Text(l.t('onb_pair_skip'),
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      );

  /// «Без браслета приложение работает полностью» — and what that means, in the
  /// four words she will look for later: Настройки → Устройства.
  Widget _manualPlate(L10n l) => Container(
        key: const Key('onb-pair-manual'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Ds.pastelMint,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: Palette.good, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.check_rounded, size: 19, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.t('onb_pair_manual_title'),
                      style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: Ds.mintText)),
                  const SizedBox(height: 2),
                  Text(l.t('onb_pair_manual_body'),
                      style: const TextStyle(
                          fontSize: 13.5, height: 1.45, color: Ds.mintText)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Subtitle extends StatelessWidget {
  final String text;
  const _Subtitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant));
}

/// «Ищем устройства рядом…» with a spinner and two skeleton rows, so the wait
/// looks like a wait rather than like a page that failed to load.
class _ScanningCard extends StatelessWidget {
  final String label;
  const _ScanningCard({required this.label});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ScanningLine(label: label),
            const SizedBox(height: 10),
            for (final w in const [1.0, 0.62]) ...[
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: w,
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: Palette.glass,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      );
}

class _ScanningLine extends StatelessWidget {
  final String label;
  const _ScanningLine({required this.label});
  @override
  Widget build(BuildContext context) => Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 13.5, color: Palette.textDim)),
          ),
        ],
      );
}

/// The watches we can see, strongest first.
class _FoundList extends StatelessWidget {
  final List<DiscoveredBand> bands;
  final String? selected;
  final ValueChanged<String?> onSelect;
  const _FoundList(
      {required this.bands, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Ds.ink, width: DsShape.borderWidth),
      ),
      // Transparent Material: a RadioListTile paints its ink on the nearest
      // Material ancestor, and a DecoratedBox between the two hides the splash
      // — which the framework asserts about rather than merely looking wrong.
      child: Material(
        type: MaterialType.transparency,
        child: RadioGroup<String>(
          groupValue: selected,
          onChanged: onSelect,
          child: Column(
            children: [
              for (final b in bands)
                RadioListTile<String>(
                  value: b.id,
                  title: Text(b.name),
                  // Two identical AK-08B advertisements are otherwise the same
                  // row twice; the id and the signal are what tell her which one
                  // is the watch on the table in front of her.
                  subtitle: Text(
                    '${b.id} · ${l.t(isStrongSignal(b.rssi) ? 'onb_pair_signal_strong' : 'onb_pair_signal_weak')}',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An amber "something needs attention" plate — the spec's «плашка-внимание».
/// Amber, never red: «Красный только SOS», and a radio that is switched off is
/// not an emergency.
class _StatePlate extends StatelessWidget {
  final String title;
  final String body;
  const _StatePlate({super.key, required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Ds.pastelButter,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: Palette.amber,
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.priority_high_rounded,
                  size: 19, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: Ds.amberText)),
                  const SizedBox(height: 2),
                  Text(body,
                      style: const TextStyle(
                          fontSize: 13.5, height: 1.45, color: Ds.amberText)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _RetryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _RetryButton(
      {required this.label, required this.onTap, this.icon = Icons.refresh_rounded});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 18),
            label: Text(label),
            style: OutlinedButton.styleFrom(
              foregroundColor: Palette.violetText,
              minimumSize: const Size.fromHeight(52),
              side: BorderSide(color: Palette.violet.withValues(alpha: 0.45)),
            ),
          ),
        ),
      );
}

/// Step 5 — the child, optional.
///
/// Stateful for the same reason as [_ProfilePage]: it owns the name field's
/// controller. Coming back to this step — from the zone picker's snackbar, or
/// simply by stepping back and forward again — used to repaint an empty name
/// over a child the controller still knew about, and «Пропустить» then replaced
/// «Завершить» on a form that looked filled in.
class _ChildPage extends StatefulWidget {
  final OnboardingController controller;
  const _ChildPage({required this.controller});

  @override
  State<_ChildPage> createState() => _ChildPageState();
}

class _ChildPageState extends State<_ChildPage> {
  late final TextEditingController _childName = _seededField(widget.controller.childName);

  @override
  void dispose() {
    _childName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final controller = widget.controller;
    _syncField(_childName, controller.childName);
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
          controller: _childName,
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
        // Frame 35 asks for «Пол (два сегмента)», and this drew Material
        // ChoiceChips in Palette.violet instead — so the one control the spec
        // names by component was the one control not built from the system.
        //
        // The label sits ABOVE rather than inline. It used to be a Wrap for
        // exactly this reason: a label plus two chips is wider than 360dp in
        // Russian, 64px past the edge, and this is the last step of onboarding
        // where a clipped control is the difference between finishing and
        // giving up. A full-width segmented pill cannot share a line with
        // anything, so stacking it removes the problem instead of wrapping
        // around it, and matches how the child edit sheet already labels the
        // same field.
        Text(l.t('child_gender'), style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        DsSegmented(
          label: l.t('child_gender'),
          items: [for (final g in Gender.values) l.t('gender_${g.name}')],
          index: controller.childGender == null
              ? null
              : Gender.values.indexOf(controller.childGender!),
          onChanged: (i) => controller.setChildGender(Gender.values[i]),
          // Unchanged from the ChoiceChips: tapping the answer again clears it.
          // The field is optional (ChildProfile.gender is nullable and
          // copyWith carries an explicit clearGender), the whole child step is
          // skippable, and gender drives nothing but the avatar glyph — so a
          // mis-tap that cannot be undone would be the only irreversible thing
          // on this screen, for the least consequential field on it.
          onClear: () => controller.setChildGender(null),
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

/// Why the primary button will not move her on, in her own language — or null
/// when nothing is blocking it.
///
/// Names the ONE thing to fix rather than listing everything the step wants:
/// "enter your name and a phone number and accept the terms" over a form where
/// only the phone is short reads as a wall, and she has to work out which part
/// applies to her.
String? _blockReason(OnboardingController c, L10n l, bool blockedForConsent) {
  if (blockedForConsent) return l.t('onb_need_consent');
  if (c.canProceed) return null;
  return switch (c.step) {
    OnboardingStep.profile => c.displayName.trim().isEmpty
        ? l.t('onb_need_name')
        : l.t('onb_need_phone'),
    // Half a child: she has started naming one, and the home zone is what
    // makes it trackable.
    OnboardingStep.child => l.t('onb_need_child_zone'),
    _ => null,
  };
}
