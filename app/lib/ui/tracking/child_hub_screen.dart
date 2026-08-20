/// Frame 15a — the «Ребёнок» tab, as two segments rather than a map with a
/// sheet floating over it.
///
/// `docs/CLAUDE-app-design.md`:
///
/// > Два сегмента (`DsSegmented`), не таббар: **Где ребёнок** — карта (кадр 12),
/// > **Сегодня** — этот список. По умолчанию открывается **Сегодня**, если у
/// > ребёнка нет спаренного трекера: карта без брелока — это пустой экран,
/// > поставленный заголовком. С трекером по умолчанию открывается карта.
///
/// [DsSegmented] is used as-is and **without `onClear`**. That flag is opt-in
/// per call site precisely so a tab-like use cannot be emptied: an empty index
/// here would leave the whole tab blank with no way back to either half.
library;

import 'package:flutter/material.dart';

import '../../l10n/l10n_scope.dart';
import '../ds_widgets.dart';
import '../theme.dart';

class ChildHubScreen extends StatefulWidget {
  const ChildHubScreen({
    super.key,
    required this.map,
    required this.today,
    required this.openOnMap,
  });

  /// «Где ребёнок» — кадр 12.
  final Widget map;

  /// «Сегодня» — кадр 15a's grouped list.
  final Widget today;

  /// Which segment this tab opens on.
  ///
  /// True when the child has a paired tracker — the map then has something to
  /// draw. It is also true when there is NO child at all: the map segment is
  /// the one carrying «Добавить ребёнка», so opening on a care list for a child
  /// who does not exist would hide the only control that fixes that.
  final bool openOnMap;

  @override
  State<ChildHubScreen> createState() => ChildHubScreenState();
}

/// Public so the shell can hand over to the MAP specifically.
///
/// Screen 21's «Открыть карту» and the setup step that adds a safe zone both
/// name the map, not the tab. Switching the tab alone would land a mother who
/// has just tapped a red SOS button on a list of care tiles — the segment has
/// to move with it, and only this state knows which segment is showing.
class ChildHubScreenState extends State<ChildHubScreen> {
  late int _index = widget.openOnMap ? 0 : 1;

  /// Deliberately NOT re-derived in `didUpdateWidget`. Pairing a tracker while
  /// she is reading the vaccination tile must not throw her onto the map.

  /// Show «Где ребёнок». Safe to call when it is already showing.
  void showMap() {
    if (_index == 0) return;
    setState(() => _index = 0);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    return Material(
      color: Palette.bg,
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: DsSegmented(
                items: [l.t('child_seg_where'), l.t('child_seg_today')],
                index: _index,
                onChanged: (i) => setState(() => _index = i),
                // No onClear — see the library comment.
                label: l.t('nav_child'),
              ),
            ),
          ),
          // IndexedStack, not a swap: the map is a platform view, and rebuilding
          // it on every segment tap re-creates the native surface and loses the
          // camera position she just panned to.
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [widget.map, widget.today],
            ),
          ),
        ],
      ),
    );
  }
}
