/// Emergency Rescue Screen — the highest-stakes UI in the app.
/// Rendered when triage returns `forceEmergencyScreen` (from the band on-device,
/// or from the server's guardrail `SHOW_EMERGENCY_SCREEN`).
///
/// UX (FemTech specialist, low-anxiety design for a frightened user):
///   • ONE dominant action — a large "Call ambulance" button, thumb-reachable.
///   • High contrast, large legible type, generous tap targets (>= 64dp).
///   • Calm-but-serious palette — deliberately NOT flashing alarm red (that spikes
///     panic); a steady, confident surface with a clear emergency accent.
///   • Screen-reader announced on open; heavy haptic so it's felt, not just seen.
///   • Dismissal is DELIBERATE (confirm) so a panicked tap can't hide a real alert.
///
/// The call action + dismissal are injected callbacks → the widget is unit-testable
/// without url_launcher / platform channels.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

class EmergencyCallButton {
  final String label; // "Call ambulance"
  final String tel; // "103"
  const EmergencyCallButton(this.label, this.tel);
}

class EmergencyRescueScreen extends StatefulWidget {
  final String message; // top triage finding, localized upstream
  final List<String> details; // optional supporting findings
  final List<EmergencyCallButton> callButtons; // primary first (e.g. ambulance)
  final Future<void> Function(EmergencyCallButton) onCall;
  final Future<void> Function() onDismissConfirmed;

  const EmergencyRescueScreen({
    super.key,
    required this.message,
    required this.callButtons,
    required this.onCall,
    required this.onDismissConfirmed,
    this.details = const [],
  });

  @override
  State<EmergencyRescueScreen> createState() => _EmergencyRescueScreenState();
}

class _EmergencyRescueScreenState extends State<EmergencyRescueScreen> {
  static const _surface = Palette.bg; // steady dark, not panic-inducing
  static const _emergency = Palette.danger; // clear accent for the call action
  static const _onSurface = Palette.text;

  @override
  void initState() {
    super.initState();
    // Felt, not just seen. And announce for screen-reader users immediately.
    HapticFeedback.heavyImpact();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l = L10nScope.of(context);
      SemanticsService.sendAnnouncement(
        View.of(context),
        '${l.t('em_title')}. ${widget.message}',
        TextDirection.ltr,
        assertiveness: Assertiveness.assertive,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final primary = widget.callButtons.isNotEmpty ? widget.callButtons.first : null;
    final secondary = widget.callButtons.skip(1).toList();

    return PopScope(
      canPop: false, // block the back gesture — dismissal must be deliberate
      child: Scaffold(
        backgroundColor: _surface,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 1.1,
              colors: [Color(0x33FB5E6D), Palette.bg],
            ),
          ),
          child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The message scrolls; the call button never does.
                //
                // This was a plain Column with a Spacer, which cannot shrink —
                // so on a 360x640 phone the Russian copy overflowed by 14px
                // before this screen carried the reading, and by 82 with it.
                // Nothing in the test suite rendered this screen, so it went
                // unseen on the one screen where losing a line is worst.
                //
                // Expanded + a scroll view keeps the button pinned in thumb
                // reach while letting long triage copy run as far as it needs.
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: _emergency, size: 34),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l.t('em_title'),
                        style: const TextStyle(
                          color: _onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    widget.message,
                    style: const TextStyle(color: _onSurface, fontSize: 20, height: 1.35),
                  ),
                ),
                if (widget.details.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  for (final d in widget.details)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('• $d',
                          style: TextStyle(color: _onSurface.withValues(alpha: 0.8), fontSize: 16)),
                    ),
                ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // PRIMARY action — the one thing a frightened user should reach for.
                if (primary != null)
                  Semantics(
                    button: true,
                    label: '${primary.label}. ${l.t('em_call_semantics')}',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: _emergency.withValues(alpha: 0.5), blurRadius: 32, spreadRadius: -4)],
                      ),
                      child: SizedBox(
                        height: 78,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _emergency,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          icon: const Icon(Icons.phone_in_talk_rounded, size: 30),
                          label: Text('${primary.label}  (${primary.tel})',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                          onPressed: () => widget.onCall(primary),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                for (final b in secondary)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SizedBox(
                      height: 60,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _onSurface,
                          side: BorderSide(color: _onSurface.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: const Icon(Icons.phone_rounded),
                        label: Text('${b.label}  (${b.tel})', style: const TextStyle(fontSize: 18)),
                        onPressed: () => widget.onCall(b),
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _confirmDismiss,
                  child: Text(l.t('em_not_emergency'),
                      // 0.6 alpha measured 4.16 against this surface, under the
                      // 4.5 minimum — on the screen most likely to be read in a
                      // hurry, in poor light, by someone frightened.
                      style: TextStyle(color: _onSurface.withValues(alpha: 0.8), fontSize: 15)),
                ),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDismiss() async {
    final l = L10nScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.t('em_dismiss_title')),
        content: Text(l.t('em_dismiss_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.t('em_keep'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.t('em_dismiss'))),
        ],
      ),
    );
    if (ok == true) await widget.onDismissConfirmed();
  }
}
