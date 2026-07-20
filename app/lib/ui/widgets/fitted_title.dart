/// App-bar title that shrinks instead of truncating.
///
/// Screen titles are written in English and then translated, and the Russian
/// and Kazakh wordings are routinely longer — "Your health" becomes "Ваше
/// здоровье" and "Сіздің денсаулығыңыз". Next to three or four app-bar actions
/// there is not enough room, and the default behaviour ellipsises: a device
/// running the app in its DEFAULT language showed "Ваше здоров…" on the very
/// first screen.
///
/// No test caught it, and none would have: ellipsis is a legal layout, not an
/// overflow. It took looking at the running app.
///
/// Scaling down keeps the whole title readable in every language, and only
/// engages when it must — English titles that already fit are untouched.
library;

import 'package:flutter/material.dart';

class FittedTitle extends StatelessWidget {
  final String text;
  const FittedTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Text(text),
      );
}
