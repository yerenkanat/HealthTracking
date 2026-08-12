/// Screen 21 — «Сигнал SOS». The one red screen in the app.
///
/// «Метка "Сигнал SOS" → "Алия нажала кнопку на брелоке" 32/700 → время →
/// карточка последнего местоположения → "Позвонить Алие" → "Открыть карту" →
/// "Сообщить Нуржану и Әже".»
///
/// WHY IT IS A TAKEOVER, NOT A ROUTE. It is raised by [AppController] over the
/// whole app — the same mechanism as [EmergencyRescueScreen] — because the
/// moment it exists is the moment nothing else on the phone matters. A pushed
/// route can be under a modal, under a sheet, under whatever she happened to
/// have open; this cannot.
///
/// ON «ПОЗВОНИТЬ АЛИЕ». It is not here, and that is deliberate. Nothing in the
/// schema holds a phone number for a child or for the tracker she wears —
/// `children` has name, gender and date of birth; `child_devices` has an id and
/// a battery. The screen therefore says so and offers the ambulance
/// ([CallAmbulanceFooter], 103), because the alternative — a button labelled
/// «Позвонить Алие» that dials the mother's own emergency contact, or a number
/// composed from something that looks like one — is a lie told on the worst
/// screen in the product to tell it on. Recorded in docs/DESIGN_DEVIATIONS.md.
///
/// ON THE MAP. The location card carries the real map when one is injected
/// ([mapBuilder]) and a plain position line when it is not, because
/// google_maps_flutter is a platform view that cannot render in a widget test
/// and this screen must be testable. Where the card cannot say anything true it
/// says «приложение не получало координат» rather than centring a map on
/// nothing.
///
/// NOT [ChildSafetyScreen]: that one is age-appropriate safety TIPS, read
/// calmly on a Tuesday. This is the alarm.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../core/geofence.dart';
import '../../l10n/l10n.dart';
import '../../l10n/l10n_scope.dart';
import '../design_system.dart';
import '../widgets/call_ambulance.dart';
import '../widgets/confirm.dart';
import 'child_map_screen.dart' show MapBuilder;

class SosAlertScreen extends StatefulWidget {
  /// Who pressed it. Empty when the alert names a child this install does not
  /// have — the headline then needs no name instead of borrowing one.
  final String childName;

  /// When the button was pressed, and the clock this screen measures against.
  final DateTime at;
  final DateTime now;

  /// The zone she was in when it happened, if any.
  final String zoneName;

  /// Last known position. Null when the app has never had one for this child.
  final Coordinates? coords;
  final DateTime? coordsAt;

  /// «Сообщить Нуржану» — from the child's medical-ID card. Both empty when
  /// nobody is recorded; the screen then says so.
  final String contactName;
  final String contactPhone;

  /// Place a call. Returns false when the dialler could not be opened, so the
  /// screen can put the number in front of her instead of doing nothing.
  final Future<bool> Function(String tel) onCall;

  /// «Открыть карту» — hands over to the live tracking screen. Null hides the
  /// button rather than opening nothing.
  final VoidCallback? onOpenMap;

  /// Dismissal, already confirmed by this screen.
  final Future<void> Function() onDismissConfirmed;

  /// The live map for the location card. Null → the card shows the position as
  /// text (and tests inject a stub).
  final MapBuilder? mapBuilder;

  const SosAlertScreen({
    super.key,
    required this.childName,
    required this.at,
    required this.now,
    required this.onCall,
    required this.onDismissConfirmed,
    this.zoneName = '',
    this.coords,
    this.coordsAt,
    this.contactName = '',
    this.contactPhone = '',
    this.onOpenMap,
    this.mapBuilder,
  });

  /// There is somebody to call AND a number to call them on. A name alone
  /// cannot be dialled.
  bool get hasContact =>
      contactName.trim().isNotEmpty && contactPhone.trim().isNotEmpty;

  @override
  State<SosAlertScreen> createState() => _SosAlertScreenState();
}

class _SosAlertScreenState extends State<SosAlertScreen> {
  @override
  void initState() {
    super.initState();
    // Felt, not just seen — she may be looking at something else entirely.
    HapticFeedback.heavyImpact();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l = L10nScope.of(context);
      SemanticsService.sendAnnouncement(
        View.of(context),
        '${l.t('sos21_label')}. ${_headline(l)}',
        TextDirection.ltr,
        assertiveness: Assertiveness.assertive,
      );
    });
  }

  String _headline(L10n l) => widget.childName.trim().isEmpty
      ? l.t('sos21_title_noname')
      : l.t('sos21_title', {'name': widget.childName.trim()});

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return PopScope(
      // The back gesture must not hide an alarm. Dismissal is deliberate.
      canPop: false,
      child: Scaffold(
        backgroundColor: Ds.sos,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Everything above the actions scrolls; the actions never do.
                // At 320dp with the font at 130% in Kazakh this column is
                // taller than the phone, and a red screen with the buttons
                // pushed off the bottom is the same as no screen.
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label(l),
                        const SizedBox(height: 14),
                        Text(
                          _headline(l),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l.t('sos21_when', {
                            'time': _hhmm(widget.at),
                            'ago': l.ago(widget.now.difference(widget.at)),
                          }),
                          style: const TextStyle(
                            color: Color(0xFFFFD3DE),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _locationCard(l),
                        const SizedBox(height: 12),
                        // 103, on the screen where the ambulance is the answer
                        // whenever the family cannot be reached. Sits inside a
                        // white surface so the reused footer keeps its own
                        // contrast rather than being read against the red.
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: DsShape.card,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                                child: Text(
                                  l.t('sos21_no_child_phone'),
                                  style: const TextStyle(
                                    color: Ds.textSecondary,
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                              CallAmbulanceFooter(onCall: widget.onCall),
                            ],
                          ),
                        ),
                        if (!widget.hasContact) ...[
                          const SizedBox(height: 12),
                          _noContactNote(l),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // «Сообщить Нуржану» — the primary action when there IS
                // somebody to reach, because the family gets there before an
                // ambulance does.
                if (widget.hasContact)
                  _ActionButton(
                    label: l.t('sos21_call_contact', {
                      'name': widget.contactName.trim(),
                    }),
                    icon: Icons.phone_in_talk_rounded,
                    filled: true,
                    onPressed: () => _call(widget.contactPhone.trim()),
                  ),
                if (widget.hasContact) const SizedBox(height: 10),
                if (widget.onOpenMap != null)
                  _ActionButton(
                    label: l.t('sos21_open_map'),
                    icon: Icons.map_rounded,
                    filled: !widget.hasContact,
                    onPressed: widget.onOpenMap!,
                  ),
                if (widget.onOpenMap != null) const SizedBox(height: 4),
                TextButton(
                  onPressed: _confirmDismiss,
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    l.t('sos21_dismiss'),
                    style: const TextStyle(
                      color: Color(0xFFFFD3DE),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(L10n l) => Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: DsShape.pill,
              border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
            ),
            child: Text(
              l.t('sos21_label').toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      );

  /// «карточка последнего местоположения с картой».
  Widget _locationCard(L10n l) {
    final coords = widget.coords;
    final at = widget.coordsAt;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: DsShape.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (coords != null && widget.mapBuilder != null)
            SizedBox(
              height: 116,
              child: widget.mapBuilder!(context, coords, const []),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.t('sos21_where'),
                  style: const TextStyle(
                    color: Ds.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                if (coords == null)
                  Text(
                    l.t('sos21_where_unknown'),
                    style: const TextStyle(
                      color: Ds.ink,
                      fontSize: 14,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else ...[
                  Text(
                    // The zone when she was in one, and the position itself
                    // when she was not — which is the ordinary case for an SOS.
                    widget.zoneName.trim().isNotEmpty
                        ? widget.zoneName.trim()
                        : '${coords.lat.toStringAsFixed(5)}, '
                            '${coords.lng.toStringAsFixed(5)}',
                    style: const TextStyle(
                      color: Ds.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (at != null) ...[
                    const SizedBox(height: 3),
                    // «Плашка свежести — всегда»: a position with no age on it
                    // claims to be live, and on this screen that is the claim
                    // most likely to be wrong.
                    Text(
                      l.t('sos21_where_at', {
                        'time': _hhmm(at),
                        'ago': l.ago(widget.now.difference(at)),
                      }),
                      style: const TextStyle(
                        color: Ds.textSecondary,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _noContactNote(L10n l) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: DsShape.card,
          border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.t('sos21_no_contact_title'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l.t('sos21_no_contact_body'),
              style: const TextStyle(
                color: Color(0xFFFFE0E8),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      );

  /// Call, and if the phone will not open, put the number in front of her.
  Future<void> _call(String tel) async {
    final ok = await widget.onCall(tel);
    if (ok || !mounted) return;
    final l = L10nScope.of(context);
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
            SelectableText(
              tel,
              style: const TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 1.5),
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
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l.t('act_close'))),
        ],
      ),
    );
  }

  /// Closing an alarm is irreversible in the way that matters — the screen does
  /// not come back on its own — so it goes through the app's confirmation, like
  /// every other destructive action.
  Future<void> _confirmDismiss() async {
    final l = L10nScope.of(context);
    final ok = await confirmDestructive(
      context,
      title: l.t('sos21_dismiss_title'),
      message: l.t('sos21_dismiss_body'),
      confirmLabel: l.t('sos21_dismiss_confirm'),
    );
    if (ok) await widget.onDismissConfirmed();
  }
}

/// A full-width action on the red canvas. White fill for the one thing to reach
/// for; outlined for the rest.
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // No `height` — «Ни у одной кнопки нет height, только min-height». At 130%
    // in Kazakh these labels wrap to two lines and the button has to grow.
    final shape = RoundedRectangleBorder(borderRadius: DsShape.input);
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 22, color: filled ? Ds.sos : Colors.white),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: filled ? Ds.sos : Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
    return filled
        ? FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Ds.sos,
              shape: shape,
              minimumSize: const Size.fromHeight(54),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            child: child,
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white, width: 1.4),
              shape: shape,
              minimumSize: const Size.fromHeight(54),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            child: child,
          );
  }
}
