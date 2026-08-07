/// «Внизу — 103.»
///
/// docs/CLAUDE-app-design.md §"Медицинские формулировки": red flags go in their
/// own block, not behind "read more", and the ambulance number goes at the
/// bottom.
///
/// The red-flag screens listed the signs and stopped. A woman who has just read
/// «кровотечение», «схватки раньше срока», «ребёнок стал меньше шевелиться» and
/// recognised herself was then left to leave the app, find the dialler and
/// remember the number — in the state of mind that list creates. The whole
/// point of writing the signs down is what she does next.
///
/// Deliberately not the emergency red. This sits at the bottom of a reference
/// screen she may be reading calmly at week 20; the alarm palette is reserved
/// for [EmergencyRescueScreen], where something IS happening. Making both look
/// the same makes neither mean anything.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../theme.dart';

/// Kazakhstan's ambulance number. 112 (the single emergency line) is in the
/// legal text; 103 is what gets somebody to a pregnant woman fastest, and one
/// button beats two on a screen read under stress.
const String kAmbulanceTel = '103';

class CallAmbulanceFooter extends StatelessWidget {
  /// Overridden in tests, and by any caller that wants to log the attempt.
  /// Returns false when the dialler could not be opened, which is when the
  /// number itself has to be readable on screen.
  final Future<bool> Function(String tel)? onCall;

  const CallAmbulanceFooter({super.key, this.onCall});

  Future<bool> _dial() async {
    final uri = Uri(scheme: 'tel', path: kAmbulanceTel);
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Semantics(
      button: true,
      label: '${l.t('em_call_ambulance')} $kAmbulanceTel',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: DsShape.card,
          onTap: () async {
            final ok = await (onCall?.call(kAmbulanceTel) ?? _dial());
            if (!ok && context.mounted) {
              // Doing nothing on a failed launch is the worst outcome here: she
              // taps, the screen does not move, and she assumes the call went
              // out. Show the number so she can dial it by hand.
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('${l.t('em_call_ambulance')}: $kAmbulanceTel'),
              ));
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Ds.pastelPink,
              borderRadius: DsShape.card,
              border: Border.all(color: Ds.hairline, width: DsShape.borderWidth),
            ),
            child: Row(children: [
              const Icon(Icons.call_rounded, size: 20, color: Ds.coralText),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.t('em_call_ambulance'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Ds.coralText)),
                    const SizedBox(height: 2),
                    // The number itself, always visible. If the dialler cannot
                    // open — a tablet, a locked-down device — she has still read
                    // the three digits she needs.
                    Text(l.t('em_ambulance_hint', {'tel': kAmbulanceTel}),
                        style: const TextStyle(
                            color: Palette.textDim, fontSize: 12.5, height: 1.35)),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
