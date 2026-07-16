/// Photo picker sheet — a small bottom sheet offering Gallery / Camera / (Remove).
/// Handles the whole flow and returns a [PhotoResult]: a newly stored path, an
/// explicit remove, or null if the user backed out.
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/photo_store.dart';
import '../../l10n/l10n_scope.dart';
import '../theme.dart';

class PhotoResult {
  final String? path; // newly stored photo path (null when [remove] is true)
  final bool remove;
  const PhotoResult.picked(this.path) : remove = false;
  const PhotoResult.removed()
      : path = null,
        remove = true;
}

/// Show the options and perform the pick. [prefix] namespaces the stored file
/// (e.g. 'profile', 'child-1'). [canRemove] adds the remove option.
Future<PhotoResult?> pickPhoto(
  BuildContext context, {
  required String prefix,
  bool canRemove = false,
  PhotoStore? store,
}) async {
  final l = L10nScope.of(context);
  final source = await showModalBottomSheet<_Choice>(
    context: context,
    backgroundColor: Palette.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Palette.border, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: Palette.violet),
            title: Text(l.t('photo_gallery')),
            onTap: () => Navigator.pop(ctx, _Choice.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined, color: Palette.violet),
            title: Text(l.t('photo_camera')),
            onTap: () => Navigator.pop(ctx, _Choice.camera),
          ),
          if (canRemove)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Palette.danger),
              title: Text(l.t('photo_remove'), style: const TextStyle(color: Palette.danger)),
              onTap: () => Navigator.pop(ctx, _Choice.remove),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (source == null) return null;
  if (source == _Choice.remove) return const PhotoResult.removed();

  final ps = store ?? PhotoStore();
  final path = await ps.pickAndStore(
    source == _Choice.camera ? ImageSource.camera : ImageSource.gallery,
    prefix: prefix,
  );
  if (path == null) return null; // user cancelled the system picker
  return PhotoResult.picked(path);
}

enum _Choice { gallery, camera, remove }
