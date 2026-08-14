/// The nine child-care screens, and the one place that knows how to open each.
///
/// Медкарта · Болезни · Развитие · Прививки · Рост и вес · Дневник малыша ·
/// Детектор плача · Прикорм · Безопасность дома.
///
/// They are reached from TWO places now — the cards on the child's card, and
/// the tools sheet on the «Ребёнок» tab — and every one of them needs more
/// than a `push`: a StreamBuilder so a tick saved inside the screen comes back
/// out, a controller callback, a confirm before a delete. Copying that wiring
/// into the second caller is how one copy keeps working and the other quietly
/// stops persisting; so it lives here once and both callers spend it.
library;

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../data/cry_classifier_client.dart';
import '../../data/cry_recorder.dart';
import '../../data/cry_settings_repository.dart';
import '../../domain/child_growth.dart';
import '../../domain/family.dart';
import '../../domain/newborn_log.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/confirm.dart';
import 'child_development_screen.dart';
import 'child_emergency_screen.dart';
import 'child_growth_screen.dart';
import 'child_illness_screen.dart';
import 'cry_insight_screen.dart';
import 'home_safety_screen.dart';
import 'newborn_log_screen.dart';
import 'solids_screen.dart';
import 'vaccination_screen.dart';

/// The backend API base — same default as the transport in main.dart. The cry
/// client talks to this (the Node proxy), not the classifier directly.
const _apiBase =
    String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8080');

/// The child's emergency medical-ID card — allergies, conditions, the person to
/// call. Rebuilt on controller changes so an edit made inside it is what the
/// screen then shows.
void openMedicalId(
    BuildContext context, AppController controller, ChildProfile child) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => StreamBuilder<void>(
      stream: controller.changes,
      builder: (_, __) => ChildEmergencyScreen(
        childName: child.name,
        info: controller.emergencyInfoFor(child.id),
        onSave: (info) => controller.setEmergencyInfo(child.id, info),
      ),
    ),
  ));
}

/// Unwell-child guidance — fever, red flags, when to call 103.
void openIllness(BuildContext context, ChildProfile child, DateTime now) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ChildIllnessScreen(ageMonths: child.ageInMonths(now)),
  ));
}

/// The development calendar for this child's age.
void openDevelopment(BuildContext context, ChildProfile child, DateTime now) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ChildDevelopmentScreen(child: child, today: now),
  ));
}

/// The vaccination schedule, with what has been recorded done.
void openVaccinations(
    BuildContext context, AppController controller, ChildProfile child, DateTime now) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => StreamBuilder<void>(
      stream: controller.changes,
      builder: (_, __) => VaccinationScreen(
        child: child,
        today: now,
        doneKeys: controller.vaccinesDoneFor(child.id),
        onToggleDone: (key) => controller.toggleVaccineDone(child.id, key),
      ),
    ),
  ));
}

/// The weaning guide for this child's age.
void openSolids(BuildContext context, ChildProfile child, DateTime now) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => SolidsScreen(ageMonths: child.ageInMonths(now)),
  ));
}

/// The home-safety checklist. Household-wide, so it is keyed on the age only
/// for which tasks are relevant.
void openHomeSafety(
    BuildContext context, AppController controller, ChildProfile child, DateTime now) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => StreamBuilder<void>(
      stream: controller.changes,
      builder: (_, __) => HomeSafetyScreen(
        ageMonths: child.ageInMonths(now),
        done: controller.homeSafetyDone,
        onToggle: controller.toggleHomeSafetyTask,
      ),
    ),
  ));
}

/// Open the newborn log, wired to the controller.
void openNewbornLog(BuildContext context, AppController controller,
    ChildProfile child, DateTime today) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => StreamBuilder<void>(
      stream: controller.changes,
      builder: (context, _) => NewbornLogScreen(
        childName: child.name,
        events: controller.newbornLogFor(child.id),
        today: today,
        onLog: (e) => controller.logNewbornEvent(child.id, e),
        onDelete: (e) =>
            _confirmDeleteNewborn(context, controller, child.id, e),
      ),
    ),
  ));
}

/// Open the cry-analysis recorder. Results save to the shared history via
/// controller.recordCry (which also syncs them across devices). The classifier
/// is reached through the authenticated backend proxy, so the callers only
/// offer this when signed in.
///
/// `minConfidence` is read at push time from the served threshold (кадр 17c),
/// so a number the back office changed this morning is applied tonight without
/// a release. `onVerdict` carries her «это было верно?» back to the controller,
/// which stores it with the analysis and pushes it.
void openCryInsight(BuildContext context, AppController controller) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => StreamBuilder<void>(
      stream: controller.changes,
      builder: (context, _) => CryInsightScreen(
        recorder: RecordCryRecorder(),
        client: CryClassifierClient(
          baseUrl: Uri.parse(_apiBase),
          authToken: () async => controller.authSession?.token,
        ),
        onResult: controller.recordCry,
        history: controller.cryHistory,
        minConfidence: cryMinConfidence(),
        onVerdict: (verdict, actualReason) =>
            controller.rateLatestCry(verdict, actualReason: actualReason),
      ),
    ),
  ));
}

Future<void> _confirmDeleteNewborn(BuildContext context,
    AppController controller, String childId, NewbornEvent event) async {
  final l = L10nScope.of(context);
  final ok = await confirmDestructive(
    context,
    title: l.t('nb_delete_title'),
    message: l.t('nb_delete_body'),
    confirmLabel: l.t('grw_delete'),
  );
  if (ok) controller.removeNewbornEvent(childId, event);
}

/// Open the growth chart, with an add-measurement sheet wired to the controller.
void openGrowth(
    BuildContext context, AppController controller, ChildProfile child) {
  final now = DateTime.now();
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => StreamBuilder<void>(
      stream: controller.changes,
      builder: (context, _) => ChildGrowthScreen(
        childName: child.name,
        points: controller.growthFor(child.id),
        onAdd: () => _addMeasurement(context, controller, child.id, now),
        onDelete: (day) =>
            _deleteMeasurement(context, controller, child.id, day),
      ),
    ),
  ));
}

/// Remove a measurement, after confirming — deleting a recorded number is a
/// destructive action like every other, and confirms like one.
Future<void> _deleteMeasurement(BuildContext context, AppController controller,
    String childId, DateTime day) async {
  final l = L10nScope.of(context);
  final ok = await confirmDestructive(
    context,
    title: l.t('grw_delete_title'),
    message: l.t('grw_delete_body'),
    confirmLabel: l.t('grw_delete'),
  );
  if (ok) controller.removeGrowth(childId, day);
}

Future<void> _addMeasurement(BuildContext context, AppController controller,
    String childId, DateTime today) async {
  final result = await showModalBottomSheet<GrowthPoint>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _MeasurementSheet(today: today),
  );
  if (result != null) controller.recordGrowth(childId, result);
  // A rejected typo is surfaced by the sheet itself, so nothing to report here.
  if (context.mounted && result == null) return;
}

/// Enter a weight and/or height for a given day.
class _MeasurementSheet extends StatefulWidget {
  final DateTime today;
  const _MeasurementSheet({required this.today});

  @override
  State<_MeasurementSheet> createState() => _MeasurementSheetState();
}

class _MeasurementSheetState extends State<_MeasurementSheet> {
  final _weight = TextEditingController();
  final _height = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _weight.dispose();
    _height.dispose();
    super.dispose();
  }

  double? _parse(String s) {
    final t = s.trim().replaceAll(',', '.'); // a Russian keyboard gives a comma
    return t.isEmpty ? null : double.tryParse(t);
  }

  void _save() {
    final l = L10nScope.of(context);
    final w = _parse(_weight.text);
    final h = _parse(_height.text);

    // A typo caught here, not stored: an implausible value would wreck the
    // chart scale and every "since last time" below it.
    if (w != null && !isPlausibleWeight(w)) {
      setState(() => _error = l.t('grw_bad_weight'));
      return;
    }
    if (h != null && !isPlausibleHeight(h)) {
      setState(() => _error = l.t('grw_bad_height'));
      return;
    }
    if (w == null && h == null) {
      Navigator.pop(context); // nothing entered — just close
      return;
    }
    Navigator.pop(
        context, GrowthPoint(at: widget.today, weightKg: w, heightCm: h));
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 18, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('grw_add'),
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _weight,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: l.t('grw_weight'), suffixText: l.t('grw_kg')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _height,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: l.t('grw_height'), suffixText: l.t('grw_cm')),
              ),
            ),
          ]),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(color: Palette.danger, fontSize: 12.5)),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: Palette.violet),
              child: Text(l.t('birth_save')),
            ),
          ),
        ],
      ),
    );
  }
}
