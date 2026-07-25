/// A reusable "read from a photo" affordance.
///
/// Any data-entry form that a user would otherwise fill from a physical thing —
/// a device display, a prescription box, a lab slip — can drop this in: it shows
/// a tappable card, lets the user pick a camera/gallery image (downscaled before
/// upload), hands the bytes to [onScan], and reflects busy / filled / empty /
/// error status. [onScan] does the network call AND applies the extracted values
/// to the form, returning a [ScanOutcome] describing what happened — so this
/// widget stays free of any domain, network, or ApiClient knowledge.
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

/// What a scan produced: whether it filled anything, and an optional human note
/// (which device/document was seen, or why nothing was read).
class ScanOutcome {
  final bool filled;
  final String? note;
  const ScanOutcome({required this.filled, this.note});
}

/// Picks the image bytes → extracts → applies to the form → reports the outcome.
typedef ScanRunner = Future<ScanOutcome> Function(List<int> bytes, String mediaType);

class PhotoScanTile extends StatefulWidget {
  /// The card's title, e.g. "Read from a photo". Domain-specific, from the caller.
  final String cta;

  /// The card's one-line hint, e.g. "A photo of a glucometer or lab slip".
  final String hint;

  final ScanRunner onScan;

  const PhotoScanTile({super.key, required this.cta, required this.hint, required this.onScan});

  @override
  State<PhotoScanTile> createState() => _PhotoScanTileState();
}

enum _S { idle, busy, filled, empty, error }

class _PhotoScanTileState extends State<PhotoScanTile> {
  _S _state = _S.idle;
  String? _note;

  Future<void> _start() async {
    final l = L10nScope.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 6),
          ListTile(
            leading: const Icon(Icons.photo_camera_rounded, color: Palette.violet),
            title: Text(l.t('scan_camera')),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded, color: Palette.violet),
            title: Text(l.t('scan_gallery')),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          const SizedBox(height: 6),
        ]),
      ),
    );
    if (source == null || !mounted) return;

    final XFile? file;
    try {
      // Downscale + recompress before upload: a full-res phone photo is several
      // MB, and printed digits/text read just as well at 1600px — smaller
      // upload, faster and cheaper extraction.
      file = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 72);
    } catch (_) {
      if (mounted) setState(() => _state = _S.error); // no camera / permission denied
      return;
    }
    if (file == null || !mounted) return; // cancelled

    setState(() {
      _state = _S.busy;
      _note = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final outcome = await widget.onScan(bytes, _mediaTypeFor(file.name));
      if (!mounted) return;
      setState(() {
        _state = outcome.filled ? _S.filled : _S.empty;
        _note = outcome.note;
      });
    } catch (_) {
      if (mounted) setState(() => _state = _S.error);
    }
  }

  static String _mediaTypeFor(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    final l = L10nScope.of(context);
    final busy = _state == _S.busy;

    (Color, String)? status() {
      switch (_state) {
        case _S.filled:
          final base = l.t('scan_filled');
          return (Palette.violet, _note?.isNotEmpty == true ? '$base · $_note' : base);
        case _S.empty:
          return (Palette.textDim, l.t('scan_none'));
        case _S.error:
          return (Palette.danger, l.t('scan_error'));
        case _S.idle:
        case _S.busy:
          return null;
      }
    }

    final s = status();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Palette.violet.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: busy ? null : _start,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Palette.violet.withValues(alpha: 0.35)),
              ),
              child: Row(children: [
                busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Palette.violet))
                    : const Icon(Icons.photo_camera_rounded, color: Palette.violet, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(busy ? l.t('scan_reading') : widget.cta,
                        style: const TextStyle(color: Palette.text, fontWeight: FontWeight.w700, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(widget.hint, style: const TextStyle(color: Palette.textDim, fontSize: 12, height: 1.25)),
                  ]),
                ),
                if (!busy) const Icon(Icons.chevron_right_rounded, color: Palette.textDim),
              ]),
            ),
          ),
        ),
        if (s != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(_state == _S.filled ? Icons.check_circle_rounded : Icons.info_outline_rounded, size: 15, color: s.$1),
            const SizedBox(width: 7),
            Expanded(child: Text(s.$2, style: TextStyle(color: s.$1, fontSize: 12.5, height: 1.3))),
          ]),
        ],
      ],
    );
  }
}
