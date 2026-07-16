/// Family/account domain models: the mother's profile (with phone), her children
/// (multiple), and paired devices (her band + each child's tracker tag).
/// Pure Dart → serializable + testable. Owned by PM + Mobile Architect.
library;

import '../core/geofence.dart';
import 'country_codes.dart';

class UserProfile {
  final String displayName;
  final String dialCode; // '+7'
  final String phoneNumber; // national digits/formatted
  final String doctorPhone; // emergency contact (E.164 or free-form), optional
  final DateTime? dueDate; // estimated due date (EDD) → drives gestation week
  const UserProfile({
    this.displayName = '',
    this.dialCode = '+7',
    this.phoneNumber = '',
    this.doctorPhone = '',
    this.dueDate,
  });

  String get e164 => toE164(dialCode, phoneNumber);
  bool get hasPhone => isValidNationalNumber(phoneNumber);
  bool get hasDoctor => doctorPhone.trim().isNotEmpty;
  bool get hasDueDate => dueDate != null;

  UserProfile copyWith({
    String? displayName,
    String? dialCode,
    String? phoneNumber,
    String? doctorPhone,
    DateTime? dueDate,
    bool clearDueDate = false,
  }) =>
      UserProfile(
        displayName: displayName ?? this.displayName,
        dialCode: dialCode ?? this.dialCode,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        doctorPhone: doctorPhone ?? this.doctorPhone,
        dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      );

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'dialCode': dialCode,
        'phoneNumber': phoneNumber,
        'doctorPhone': doctorPhone,
        if (dueDate != null) 'dueDate': dueDate!.toIso8601String(),
      };
  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        displayName: (j['displayName'] as String?) ?? '',
        dialCode: (j['dialCode'] as String?) ?? '+7',
        phoneNumber: (j['phoneNumber'] as String?) ?? '',
        doctorPhone: (j['doctorPhone'] as String?) ?? '',
        dueDate: j['dueDate'] is String ? DateTime.tryParse(j['dueDate'] as String) : null,
      );
}

class ChildProfile {
  final String id;
  final String name;
  final List<Geofence> geofences;
  final String? tagId; // beacon/tracker id, if paired
  final DateTime? dateOfBirth; // for age-based personalization (safety tips, thresholds)

  const ChildProfile({
    required this.id,
    required this.name,
    this.geofences = const [],
    this.tagId,
    this.dateOfBirth,
  });

  bool get hasDateOfBirth => dateOfBirth != null;

  /// Whole months of age at [now]; 0 if unknown or in the future. Kept pure so
  /// the UI just localizes it (see L10n.childAge).
  int ageInMonths(DateTime now) {
    final d = dateOfBirth;
    if (d == null) return 0;
    var months = (now.year - d.year) * 12 + (now.month - d.month);
    if (now.day < d.day) months -= 1;
    return months < 0 ? 0 : months;
  }

  ChildProfile copyWith({
    String? name,
    List<Geofence>? geofences,
    String? tagId,
    DateTime? dateOfBirth,
    bool clearDateOfBirth = false,
  }) =>
      ChildProfile(
        id: id,
        name: name ?? this.name,
        geofences: geofences ?? this.geofences,
        tagId: tagId ?? this.tagId,
        dateOfBirth: clearDateOfBirth ? null : (dateOfBirth ?? this.dateOfBirth),
      );
}

enum DeviceKind { band, tag }

class PairedDevice {
  final String id; // BLE id / serial
  final String name;
  final DeviceKind kind;
  final String? childId; // for tags: which child it tracks

  const PairedDevice({required this.id, required this.name, required this.kind, this.childId});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'kind': kind.name, 'childId': childId};
  factory PairedDevice.fromJson(Map<String, dynamic> j) => PairedDevice(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        kind: DeviceKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => DeviceKind.band),
        childId: j['childId'] as String?,
      );
}
