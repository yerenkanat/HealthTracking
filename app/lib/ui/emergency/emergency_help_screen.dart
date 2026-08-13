/// Screen 37 — «Экстренная помощь».
///
/// docs/CLAUDE-app-design.md: «карточка „103“ (`#A8002F`) → секция „Что
/// происходит?“ — сценарии с `border-left` красным/янтарным → карточка адреса
/// для диспетчера → „Позвонить педиатру“.»
///
/// WHY THIS EXISTS, next to emergency_rescue_screen.dart
///
/// That screen is TRIAGE: it appears by itself when a reading or the band says
/// something is wrong, it has one action, and it is deliberately hard to
/// dismiss. This one is a REFERENCE she opens on purpose, at 3am, while
/// deciding whether what she is looking at is worth an ambulance. Until now
/// «Гиды» sent everyone who was not pregnant to the triage screen with a
/// paragraph of red flags and a single button — no scenarios to recognise
/// herself in, no address to read out, and no way to reach her own doctor.
///
/// FOUR THINGS, IN THE ORDER SOMEBODY NEEDS THEM
///
///   1. The 103 card. First, because if she already knows, everything below is
///      in the way. `#A8002F` — the spec assigns that colour to SOS and to this
///      card, and to nothing else.
///   2. «Что происходит?» — the scenarios, each with the red or amber stripe
///      that says dial now or call today. Content, not code: they come from
///      `emergency_help_repository.dart` (asset → cache → server), so the back
///      office can correct a first-aid instruction without a release.
///   3. The address, because it is the dispatcher's first question and nobody
///      recites their own entry code under stress.
///   4. Her own doctor, from `profile.doctorPhone` — a number the app has been
///      storing and syncing for a year and had exactly one screen to dial from.
///
/// NOTHING HERE IS INVENTED. No address means the card says her city and
/// «Добавьте адрес»; no doctor's number means the row explains where to add
/// one. Both are supported states, not gaps to paper over.
///
/// The dialler is an injected callback, so a widget test can drive the whole
/// screen without url_launcher.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/emergency_help.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../ds_widgets.dart';
import '../theme.dart';
import '../widgets/fitted_title.dart';

class EmergencyHelpScreen extends StatelessWidget {
  /// The scenarios, already merged (contract + whatever the server published).
  final EmergencyHelp help;

  /// Where an ambulance would be sent. Empty is a real state — see [_AddressCard].
  final String address;

  /// Her city, the fallback line on the address card. Also may be empty.
  final String city;

  /// Her own doctor / clinic, from the profile. Empty hides the call and
  /// explains why rather than drawing a button that dials nothing.
  final String doctorPhone;

  /// Whether she is expecting — decides which scenarios apply to her.
  ///
  /// Expecting: the whole list, pregnancy triage included (she may also have a
  /// toddler). Not expecting: the pregnancy-only scenarios are dropped, because
  /// «после 20 недель» is a row she cannot act on standing between her and the
  /// one she opened this screen for. See [scenariosForAudience].
  final bool pregnant;

  /// Open «Признаки родов». Passed only for a pregnant reader, and it is the
  /// reason this screen is now HER red-flag screen too: labour signs used to be
  /// the whole of what «Когда сразу звонить 103» gave her, on a screen with no
  /// way onward to the ambulance card, the address or her doctor.
  final VoidCallback? onLabourSigns;

  /// Place a call. Returns false when the dialler could not be opened, so the
  /// screen can put the number in front of her instead of doing nothing.
  final Future<bool> Function(String tel) onCall;

  /// Open the profile editor, for the two «добавьте…» prompts. Null leaves
  /// them as plain text — an instruction is still better than a dead button.
  final VoidCallback? onEditProfile;

  const EmergencyHelpScreen({
    super.key,
    required this.help,
    required this.onCall,
    this.address = '',
    this.city = '',
    this.doctorPhone = '',
    this.pregnant = false,
    this.onLabourSigns,
    this.onEditProfile,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final locale = l.locale.name;
    // Who is reading decides WHICH scenarios, before severity decides their
    // order. Pregnancy triage reaches her only while she is expecting; nothing
    // else is ever taken away from anybody.
    final mine = scenariosForAudience(help.scenarios, pregnant: pregnant);
    final red = scenariosBySeverity(mine, EmergencySeverity.red);
    final amber = scenariosBySeverity(mine, EmergencySeverity.amber);

    return Scaffold(
      backgroundColor: Ds.cream,
      appBar: AppBar(title: FittedTitle(l.t('eh_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _CallCard(
            tel: help.tel,
            label: l.t('eh_call_103'),
            body: l.t('eh_call_body'),
            onTap: () => _call(context, help.tel),
          ),
          const SizedBox(height: 18),
          if (mine.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(l.t('eh_no_scenarios'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Palette.textDim, height: 1.4)),
            )
          else ...[
            _SectionHeader(l.t('eh_whats_happening')),
            // Red first, then amber. Not a sort by `sort` across the whole
            // list: the two groups mean different things — dial now, and call
            // today — and interleaving them would leave somebody scrolling
            // past a "call tomorrow" row to find "call an ambulance".
            for (final s in [...red, ...amber])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ScenarioCard(scenario: s, locale: locale, l: l),
              ),
          ],
          // For someone expecting: the labour reference, which is a different
          // question («пора ли ехать») on a different screen. A link rather
          // than a copy — and the only route to it from here, now that the
          // red-flag card opens this screen for her as well.
          if (onLabourSigns != null) ...[
            const SizedBox(height: 6),
            _LabourSignsRow(onTap: onLabourSigns!),
          ],
          const SizedBox(height: 6),
          _AddressCard(
            address: address,
            city: city,
            onEditProfile: onEditProfile,
          ),
          const SizedBox(height: 14),
          _DoctorRow(
            doctorPhone: doctorPhone,
            onCall: () => _call(context, doctorPhone),
            onEditProfile: onEditProfile,
          ),
        ],
      ),
    );
  }

  /// Call, and if the phone will not open, put the number in front of her.
  ///
  /// The same rule as the triage screen: a button that silently does nothing is
  /// worst on the screen where it costs the most.
  Future<void> _call(BuildContext context, String tel) async {
    final l = L10nScope.of(context);
    final ok = await onCall(tel);
    if (ok || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.t('em_call_failed_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.t('em_call_failed_body')),
            const SizedBox(height: 12),
            // Big, and selectable: she may be reading it out to someone else.
            SelectableText(
              tel,
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 2),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: tel));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(l.t('em_copy_number')),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.t('act_close'))),
        ],
      ),
    );
  }
}

/// The «103» card — `#A8002F`, and the only thing above the fold.
class _CallCard extends StatelessWidget {
  final String tel;
  final String label;
  final String body;
  final VoidCallback onTap;
  const _CallCard({required this.tel, required this.label, required this.body, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '$label. $body',
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DsShape.radiusCard),
            boxShadow: DsShape.hardShadowLg,
          ),
          child: Material(
            color: Ds.sos,
            borderRadius: BorderRadius.circular(DsShape.radiusCard),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(DsShape.radiusCard),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 44,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(label,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text(body,
                              style: TextStyle(
                                  // White at 0.88 measures 7.4:1 on #A8002F —
                                  // this line is read in poor light by someone
                                  // frightened.
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontSize: 13,
                                  height: 1.35)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

/// One scenario — the red or amber `border-left`, the signs, and what to do.
class _ScenarioCard extends StatelessWidget {
  final EmergencyScenario scenario;
  final String locale;
  final L10n l;
  const _ScenarioCard({required this.scenario, required this.locale, required this.l});

  @override
  Widget build(BuildContext context) {
    final red = scenario.severity == EmergencySeverity.red;
    final stripe = red ? Ds.sos : Ds.amber;
    final t = scenario.textFor(locale);
    final tag = l.t(red ? 'eh_sev_red' : 'eh_sev_amber');
    // The spec's `border-left`, drawn as a child rather than as a BorderSide.
    //
    // `Border(left: …, top: …)` with different colours plus a borderRadius is
    // an assertion failure in Flutter — «a borderRadius can only be given on
    // borders with uniform colors» — and it throws at PAINT time, so the widget
    // builds, the test tree is queryable, and the card is simply absent on a
    // real phone. A stripe in a Row is the same picture with none of that.
    return ClipRRect(
      borderRadius: BorderRadius.circular(DsShape.radiusCard),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border.fromBorderSide(DsShape.border),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Wide enough to read as a stripe at a glance rather than as a
              // hairline somebody has to look for.
              Container(width: 6, color: stripe),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title,
                          style: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w800, color: Ds.text)),
                      const SizedBox(height: 6),
                      Text(t.what,
                          style: const TextStyle(
                              color: Ds.textBody, fontSize: 13, height: 1.45)),
                      const SizedBox(height: 10),
                      Text('${l.t('eh_do')}: ${t.todo}',
                          style: TextStyle(
                              color: red ? Ds.coralText : Ds.amberText,
                              fontSize: 13,
                              height: 1.45,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      // The severity in WORDS as well as in colour. A stripe
                      // alone is meaningless to a colour-blind reader and to a
                      // screen reader, and this is the field that decides
                      // whether she dials.
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: red ? Ds.pastelPink : Ds.pastelButter,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(tag,
                              style: TextStyle(
                                  color: red ? Ds.coralText : Ds.amberText,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// «Признаки родов» — the labour reference, one tap from here.
///
/// Violet like the rest of the pregnancy material and NOT red: this is the
/// calm question (is it starting, when do I go in), and painting it like the
/// 103 card would make the two indistinguishable at a glance.
class _LabourSignsRow extends StatelessWidget {
  final VoidCallback onTap;
  const _LabourSignsRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return DsCard(
      color: Ds.pastelLilac,
      onTap: onTap,
      child: Row(
        children: [
          const Icon(Icons.pregnant_woman_rounded, size: 22, color: Ds.text),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('lab_title'),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800, color: Ds.text)),
                const SizedBox(height: 4),
                Text(l.t('eh_labour_signs'),
                    style: const TextStyle(
                        color: Ds.textBody, fontSize: 12.5, height: 1.35)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, size: 20, color: Ds.text),
        ],
      ),
    );
  }
}

/// «Карточка адреса для диспетчера».
class _AddressCard extends StatelessWidget {
  final String address;
  final String city;
  final VoidCallback? onEditProfile;
  const _AddressCard({required this.address, required this.city, this.onEditProfile});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final has = address.trim().isNotEmpty;
    return DsCard(
      color: Ds.pastelSky,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_rounded, size: 20, color: Ds.blueText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l.t('eh_address_title'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800, color: Ds.blueText)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (has) ...[
            // Selectable and large: she is reading it out, or handing the phone
            // to somebody who will.
            SelectableText(
              address.trim(),
              style: const TextStyle(
                  fontSize: 18, height: 1.35, fontWeight: FontWeight.w700, color: Ds.text),
            ),
            const SizedBox(height: 8),
            Text(l.t('eh_address_hint'),
                style: const TextStyle(color: Ds.textBody, fontSize: 12.5, height: 1.4)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: address.trim()));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.t('eh_address_copied'))),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: Text(l.t('eh_address_copy')),
                style: TextButton.styleFrom(foregroundColor: Ds.blueText),
              ),
            ),
          ] else ...[
            // Her city, if the app knows it, because «Алматы» is a real half of
            // an answer to «адрес?» and better than a blank card. Nothing is
            // invented past that.
            if (city.trim().isNotEmpty)
              Text(city.trim(),
                  style: const TextStyle(
                      fontSize: 18, height: 1.3, fontWeight: FontWeight.w700, color: Ds.text)),
            if (city.trim().isNotEmpty) const SizedBox(height: 6),
            Text(l.t('eh_address_missing_body'),
                style: const TextStyle(color: Ds.textBody, fontSize: 12.5, height: 1.4)),
            if (onEditProfile != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onEditProfile,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(l.t('eh_address_missing')),
                  style: TextButton.styleFrom(foregroundColor: Ds.blueText),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// «Позвонить педиатру» — her own doctor, or an honest explanation of why the
/// button is not there.
class _DoctorRow extends StatelessWidget {
  final String doctorPhone;
  final VoidCallback onCall;
  final VoidCallback? onEditProfile;
  const _DoctorRow({required this.doctorPhone, required this.onCall, this.onEditProfile});

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    if (doctorPhone.trim().isEmpty) {
      return DsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.t('eh_no_doctor'),
                style: const TextStyle(color: Ds.textBody, fontSize: 13, height: 1.4)),
            if (onEditProfile != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onEditProfile,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(l.t('prof_doctor_hint')),
                  style: TextButton.styleFrom(foregroundColor: Ds.coralText),
                ),
              ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 60,
      child: OutlinedButton.icon(
        onPressed: onCall,
        icon: const Icon(Icons.local_hospital_rounded),
        label: Text('${l.t('eh_call_doctor')}  ·  ${doctorPhone.trim()}',
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          foregroundColor: Ds.coralText,
          side: const BorderSide(color: Ds.coralText, width: DsShape.borderWidth),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
              color: Palette.textDim,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            )),
      );
}
