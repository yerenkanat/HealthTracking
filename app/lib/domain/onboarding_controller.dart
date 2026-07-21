/// OnboardingController — the first-run flow state machine. Pure Dart (dart:async
/// listeners), so step navigation + per-step validation + config assembly are all
/// unit-testable without Flutter. Owned by PM + Mobile Architect.
///
/// Steps: welcome → language → profile → pairBand → child → done.
/// Band pairing is optional (a user may only want the child tracker, or pair the
/// band later). Child setup requires a name + a Home zone (the anchor for
/// "arrived home" alerts). School is optional.
library;

import 'dart:async';

import '../core/geofence.dart';
import '../l10n/l10n.dart';
import 'country_codes.dart';
import 'family.dart';

enum OnboardingStep { welcome, language, profile, pairBand, child, done }

class ZoneInput {
  final String name;
  final double lat;
  final double lng;
  final double radiusM;
  const ZoneInput(this.name, this.lat, this.lng, {this.radiusM = 100});
  Geofence toGeofence(String id) => Geofence.circle(id, name, Coordinates(lat, lng), radiusM);
}

class OnboardingResult {
  final AppLocale locale;
  final UserProfile profile;
  final String? bandId;
  /// Null when the child step was skipped — the pregnancy half needs no child.
  final ChildProfile? child;
  const OnboardingResult({
    required this.locale,
    required this.profile,
    required this.bandId,
    required this.child,
  });
}

class OnboardingController {
  static const _order = [
    OnboardingStep.welcome,
    OnboardingStep.language,
    OnboardingStep.profile,
    OnboardingStep.pairBand,
    OnboardingStep.child,
    OnboardingStep.done,
  ];

  final _changes = StreamController<void>.broadcast();

  OnboardingStep _step = OnboardingStep.welcome;
  AppLocale _locale;
  String _displayName = '';
  String _dialCode = defaultCountry.dial;
  String _phoneNumber = '';
  bool _expecting = false;
  DateTime? _dueDate;
  String? _bandId;
  String _childName = '';
  DateTime? _childDob;
  Gender? _childGender;
  ZoneInput? _home;
  ZoneInput? _school;

  OnboardingController({AppLocale initialLocale = AppLocale.ru}) : _locale = initialLocale;

  Stream<void> get changes => _changes.stream;
  OnboardingStep get step => _step;
  AppLocale get locale => _locale;
  String get displayName => _displayName;
  String get dialCode => _dialCode;
  String get phoneNumber => _phoneNumber;
  bool get expecting => _expecting;
  DateTime? get dueDate => _dueDate;
  String? get bandId => _bandId;
  String get childName => _childName;
  DateTime? get childDob => _childDob;
  Gender? get childGender => _childGender;
  ZoneInput? get home => _home;
  ZoneInput? get school => _school;

  int get stepIndex => _order.indexOf(_step);
  int get totalSteps => _order.length - 1; // 'done' is terminal, not a page
  bool get isComplete => _step == OnboardingStep.done;

  // ---- inputs ----
  void setLocale(AppLocale l) => _set(() => _locale = l);
  void setDisplayName(String v) => _set(() => _displayName = v);
  void setDialCode(String v) => _set(() => _dialCode = v);
  void setPhoneNumber(String v) => _set(() => _phoneNumber = v);
  void setExpecting(bool v) => _set(() => _expecting = v);
  void setDueDate(DateTime? v) => _set(() => _dueDate = v);
  void setBandId(String? v) => _set(() => _bandId = v);
  void setChildName(String v) => _set(() => _childName = v);
  void setChildDob(DateTime? d) => _set(() => _childDob = d);
  void setChildGender(Gender? g) => _set(() => _childGender = g);
  void setHome(ZoneInput? z) => _set(() => _home = z);
  void setSchool(ZoneInput? z) => _set(() => _school = z);

  /// Whether the current step's requirements are met.
  bool get canProceed => switch (_step) {
        OnboardingStep.welcome => true,
        OnboardingStep.language => true,
        OnboardingStep.profile =>
          _displayName.trim().isNotEmpty && isValidNationalNumber(_phoneNumber, dial: _dialCode),
        OnboardingStep.pairBand => true, // optional — may skip
        // The child step is OPTIONAL.
        //
        // It used to require a name AND a home zone, with a single button that
        // stayed greyed out until both were given and no way past. So a
        // pregnant woman with no children — a first-time expectant mother, the
        // most likely person to install a pregnancy app — could not finish
        // setup at all. Her only way in was to invent a child.
        //
        // Half a child is still refused: once she starts naming one, the home
        // zone is what makes it trackable, and a child with no zone would sit
        // in the app doing nothing.
        OnboardingStep.child => _childName.trim().isEmpty || _home != null,
        OnboardingStep.done => true,
      };

  void next() {
    if (!canProceed || isComplete) return;
    _set(() => _step = _order[stepIndex + 1]);
  }

  void back() {
    if (stepIndex == 0) return;
    _set(() => _step = _order[stepIndex - 1]);
  }

  /// Whether a child was actually set up. False when the step was skipped.
  bool get hasChild => _childName.trim().isNotEmpty;

  /// Assemble the final config (call once [isComplete]).
  ///
  /// [OnboardingResult.child] is null when the child step was skipped — the
  /// pregnancy half of the app needs no child, and inventing an empty one
  /// would put a nameless entry in her family list and a nameless chip on the
  /// tracking screen.
  OnboardingResult build() {
    final fences = <Geofence>[
      if (_home != null) _home!.toGeofence('home'),
      if (_school != null) _school!.toGeofence('school'),
    ];
    return OnboardingResult(
      locale: _locale,
      profile: UserProfile(
        displayName: _displayName.trim(),
        dialCode: _dialCode,
        phoneNumber: _phoneNumber.trim(),
        dueDate: _expecting ? _dueDate : null,
      ),
      bandId: _bandId,
      child: hasChild
          ? ChildProfile(
              id: 'child-1',
              name: _childName.trim(),
              dateOfBirth: _childDob,
              gender: _childGender,
              geofences: fences)
          : null,
    );
  }

  void _set(void Function() mutate) {
    mutate();
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}
