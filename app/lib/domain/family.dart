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
  const UserProfile({this.displayName = '', this.dialCode = '+7', this.phoneNumber = ''});

  String get e164 => toE164(dialCode, phoneNumber);
  bool get hasPhone => isValidNationalNumber(phoneNumber);

  UserProfile copyWith({String? displayName, String? dialCode, String? phoneNumber}) => UserProfile(
        displayName: displayName ?? this.displayName,
        dialCode: dialCode ?? this.dialCode,
        phoneNumber: phoneNumber ?? this.phoneNumber,
      );

  Map<String, dynamic> toJson() => {'displayName': displayName, 'dialCode': dialCode, 'phoneNumber': phoneNumber};
  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        displayName: (j['displayName'] as String?) ?? '',
        dialCode: (j['dialCode'] as String?) ?? '+7',
        phoneNumber: (j['phoneNumber'] as String?) ?? '',
      );
}

class ChildProfile {
  final String id;
  final String name;
  final List<Geofence> geofences;
  final String? tagId; // beacon/tracker id, if paired

  const ChildProfile({required this.id, required this.name, this.geofences = const [], this.tagId});

  ChildProfile copyWith({String? name, List<Geofence>? geofences, String? tagId}) => ChildProfile(
        id: id,
        name: name ?? this.name,
        geofences: geofences ?? this.geofences,
        tagId: tagId ?? this.tagId,
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
