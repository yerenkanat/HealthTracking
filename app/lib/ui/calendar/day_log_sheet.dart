/// The day-log editor sheet, shared by every screen that surfaces a specific
/// day: the calendar, the symptom drill-down, and the notes browser. Extracted
/// so those screens open the SAME editor instead of each growing its own.
library;

import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import 'kick_session_screen.dart';
import 'logging_drawer.dart';

/// Open the log editor for [day]. Every mutation goes straight to the
/// controller, so callers don't need to handle a result.
Future<void> showDayLogSheet(BuildContext context, AppController c, DateTime day) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => StreamBuilder<void>(
      stream: c.changes,
      builder: (_, __) => FloStyleCalendarDrawer(
        day: day,
        log: c.logFor(day),
        pregnant: c.isPregnant,
        onToggleMood: (m) => c.toggleMoodFor(day, m),
        onToggleSymptom: (s) => c.toggleSymptomFor(day, s),
        onToggleFlow: (f) => c.toggleFlowFor(day, f),
        onKick: () => c.addKickFor(day),
        onResetKicks: () => c.resetKicksFor(day),
        onSetNote: (note) => c.setNoteFor(day, note),
        onStartSession: () {
          Navigator.of(sheetCtx).pop(); // close the sheet, then open the session
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => KickSessionScreen(onSave: (n, elapsed) => c.logKickSession(day, n, elapsed)),
          ));
        },
      ),
    ),
  );
}
