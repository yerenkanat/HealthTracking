/// A child's emergency medical-ID information — the few things a parent wants to
/// hand a paramedic or a clinician fast: blood type, allergies, conditions,
/// medications, the doctor, and who to call.
///
/// PURE Dart → verified by tool/verify_child_emergency.dart.
///
/// All fields are free text and optional — this is what the PARENT knows and
/// chooses to record, not anything the app measures or verifies. It is stored
/// per child and shown on its own screen so it can be read out or shown at a
/// glance in the moment it matters.
library;

class ChildEmergencyInfo {
  final String bloodType;
  final String allergies;
  final String conditions;
  final String medications;
  final String doctorName;
  final String doctorPhone;
  final String contactName;
  final String contactPhone;
  final String notes;

  const ChildEmergencyInfo({
    this.bloodType = '',
    this.allergies = '',
    this.conditions = '',
    this.medications = '',
    this.doctorName = '',
    this.doctorPhone = '',
    this.contactName = '',
    this.contactPhone = '',
    this.notes = '',
  });

  /// True when nothing has been filled in — the screen shows an invitation
  /// rather than an empty card.
  bool get isEmpty =>
      bloodType.trim().isEmpty &&
      allergies.trim().isEmpty &&
      conditions.trim().isEmpty &&
      medications.trim().isEmpty &&
      doctorName.trim().isEmpty &&
      doctorPhone.trim().isEmpty &&
      contactName.trim().isEmpty &&
      contactPhone.trim().isEmpty &&
      notes.trim().isEmpty;

  /// True when a field a first responder acts on immediately — allergies or a
  /// medical condition — is present, so the screen can lead with it.
  bool get hasCritical => allergies.trim().isNotEmpty || conditions.trim().isNotEmpty;

  /// Only the fields that were filled in, written; an all-blank info round-trips
  /// to `{}` and takes no space on disk.
  Map<String, dynamic> toJson() => {
        if (bloodType.trim().isNotEmpty) 'bloodType': bloodType.trim(),
        if (allergies.trim().isNotEmpty) 'allergies': allergies.trim(),
        if (conditions.trim().isNotEmpty) 'conditions': conditions.trim(),
        if (medications.trim().isNotEmpty) 'medications': medications.trim(),
        if (doctorName.trim().isNotEmpty) 'doctorName': doctorName.trim(),
        if (doctorPhone.trim().isNotEmpty) 'doctorPhone': doctorPhone.trim(),
        if (contactName.trim().isNotEmpty) 'contactName': contactName.trim(),
        if (contactPhone.trim().isNotEmpty) 'contactPhone': contactPhone.trim(),
        if (notes.trim().isNotEmpty) 'notes': notes.trim(),
      };

  factory ChildEmergencyInfo.fromJson(Map<String, dynamic> j) => ChildEmergencyInfo(
        bloodType: (j['bloodType'] as String?) ?? '',
        allergies: (j['allergies'] as String?) ?? '',
        conditions: (j['conditions'] as String?) ?? '',
        medications: (j['medications'] as String?) ?? '',
        doctorName: (j['doctorName'] as String?) ?? '',
        doctorPhone: (j['doctorPhone'] as String?) ?? '',
        contactName: (j['contactName'] as String?) ?? '',
        contactPhone: (j['contactPhone'] as String?) ?? '',
        notes: (j['notes'] as String?) ?? '',
      );

  ChildEmergencyInfo copyWith({
    String? bloodType,
    String? allergies,
    String? conditions,
    String? medications,
    String? doctorName,
    String? doctorPhone,
    String? contactName,
    String? contactPhone,
    String? notes,
  }) =>
      ChildEmergencyInfo(
        bloodType: bloodType ?? this.bloodType,
        allergies: allergies ?? this.allergies,
        conditions: conditions ?? this.conditions,
        medications: medications ?? this.medications,
        doctorName: doctorName ?? this.doctorName,
        doctorPhone: doctorPhone ?? this.doctorPhone,
        contactName: contactName ?? this.contactName,
        contactPhone: contactPhone ?? this.contactPhone,
        notes: notes ?? this.notes,
      );
}
