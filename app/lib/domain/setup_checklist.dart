/// Setup checklist — which first-run steps are still outstanding, so the
/// dashboard can nudge the user to finish setting up. PURE Dart → unit-testable
/// via verify_setup.dart. Takes plain booleans so it stays independent of the
/// controller's shape.
library;

/// The steps that make the app genuinely useful. Order is the order shown.
/// Order is the order shown.  sits after the essentials: the app is
/// fully usable without a birth date or city, and asking for them before the
/// user has anything working would be asking for data in exchange for nothing.
enum SetupStep { profileName, healthMode, child, zone, details, backup }

class SetupProgress {
  final List<SetupStep> done;
  final List<SetupStep> remaining; // in [SetupStep.values] order
  const SetupProgress(this.done, this.remaining);

  int get total => done.length + remaining.length;

  /// Completion 0..1.
  double get fraction => total == 0 ? 1 : done.length / total;

  bool get complete => remaining.isEmpty;

  /// The step to nudge next, or null when everything's done.
  SetupStep? get next => remaining.isEmpty ? null : remaining.first;
}

/// Work out which steps are done. Each flag maps to one [SetupStep].
SetupProgress computeSetupProgress({
  required bool hasName,
  required bool hasHealthData, // a due date, or any logged period
  required bool hasChild,
  required bool hasZone,
  /// Birth date AND city — the pair that sharpens age-relevant guidance and
  /// makes regional availability real. Counted together so a half-answer
  /// doesn't quietly tick the box.
  required bool hasDetails,
  required bool hasBackup, // exported at least once
}) {
  final byStep = <SetupStep, bool>{
    SetupStep.profileName: hasName,
    SetupStep.healthMode: hasHealthData,
    SetupStep.child: hasChild,
    SetupStep.zone: hasZone,
    SetupStep.details: hasDetails,
    SetupStep.backup: hasBackup,
  };
  final done = <SetupStep>[];
  final remaining = <SetupStep>[];
  for (final s in SetupStep.values) {
    (byStep[s]! ? done : remaining).add(s);
  }
  return SetupProgress(done, remaining);
}
