/// Every OS notification id the app allocates, in one place.
///
/// The OS keeps ONE id namespace: posting a notification with an id that a
/// scheduled reminder also uses replaces it. The blocks below were previously
/// declared in three separate files — 800001/800002 private to AppController,
/// 900001/900002 as local consts in main.dart, the appointment block in
/// AppController, and immediate alerts counting up from 0 in the notification
/// service, which knew about none of the others. They happened not to collide.
/// Nothing checked that, and nothing would have noticed if a new block landed
/// on an old one: the symptom is a reminder that silently never arrives.
///
/// Pure Dart; tool/verify_notifyids.dart asserts the blocks stay disjoint and
/// that every allocator lands inside its own block.
library;

class NotifyBlock {
  final String name;
  final int start;
  final int end; // inclusive
  const NotifyBlock(this.name, this.start, this.end);
  bool contains(int id) => id >= start && id <= end;
}

class NotifyIds {
  NotifyIds._();

  /// Immediate safety alerts (zone entry/exit, SOS, low battery).
  static const alertBase = 100000;
  static const alertSpan = 100000;

  /// Cycle reminders — one fixed id each.
  static const period = 800001;
  static const fertile = 800002;

  /// Repeating daily reminders — one fixed id each.
  static const water = 900001;
  static const medication = 900002;

  /// Appointment reminders, keyed by hashing the appointment id.
  static const appointmentBase = 1000000;
  static const appointmentSpan = 1000000;

  static const blocks = <NotifyBlock>[
    NotifyBlock('alerts', alertBase, alertBase + alertSpan - 1),
    NotifyBlock('cycle', 800001, 800002),
    NotifyBlock('daily', 900001, 900002),
    NotifyBlock('appointments', appointmentBase, appointmentBase + appointmentSpan - 1),
  ];

  static int forAppointment(String appointmentId) =>
      appointmentBase + ((appointmentId.hashCode & 0x7fffffff) % appointmentSpan);

  /// Id for the [seq]-th immediate alert of this run.
  ///
  /// Wrapped into the alert block so a long-running session can never count up
  /// into the cycle or appointment blocks and cancel a pending reminder.
  static int forAlert(int seq) => alertBase + (seq.abs() % alertSpan);
}
