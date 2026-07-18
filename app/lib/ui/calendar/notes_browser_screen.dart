/// NotesBrowserScreen — browse and search every day note. A search field filters
/// by substring; results are shown newest-first. Pure presentation over the
/// [searchNotes] domain helper.
library;

import 'package:flutter/material.dart';
import '../../domain/cycle_insights.dart';
import '../../domain/cycle_log.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';
import '../widgets/glass.dart';

class NotesBrowserScreen extends StatefulWidget {
  final List<DayLog> logs;
  const NotesBrowserScreen({super.key, required this.logs});
  @override
  State<NotesBrowserScreen> createState() => _NotesBrowserScreenState();
}

class _NotesBrowserScreenState extends State<NotesBrowserScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final results = searchNotes(widget.logs, _search.text);
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(l.t('notes_browser_title'))),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: l.t('notes_search_hint'),
                  prefixIcon: const Icon(Icons.search_rounded, color: Palette.textDim),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, color: Palette.textDim),
                          onPressed: () => setState(_search.clear),
                        ),
                  filled: true,
                  fillColor: Palette.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                ),
              ),
            ),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(_search.text.isEmpty ? l.t('notes_empty') : l.t('notes_no_match'),
                            textAlign: TextAlign.center, style: const TextStyle(color: Palette.textDim, height: 1.4)),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: results.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _NoteCard(log: results[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final DayLog log;
  const _NoteCard({required this.log});
  @override
  Widget build(BuildContext context) {
    final ml = MaterialLocalizations.of(context);
    final date = DateTime.tryParse(log.date);
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(date == null ? log.date : ml.formatMediumDate(date),
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Palette.roseDeep)),
          const SizedBox(height: 3),
          Text(log.note, style: const TextStyle(fontSize: 14, color: Palette.text, height: 1.35)),
        ],
      ),
    );
  }
}
