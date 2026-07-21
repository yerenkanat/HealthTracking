/// Photo storage — picks an image (gallery or camera) and copies it into the
/// app's documents directory so the saved path stays valid across restarts.
/// Kept out of the domain layer (does file IO + plugin calls).
library;

import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'photo_paths.dart';

class PhotoStore {
  final ImagePicker _picker;
  PhotoStore({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  /// Pick an image from [source], downscale, copy into <docs>/photos, and
  /// return the stored FILENAME. Returns null if the user cancels the picker.
  ///
  /// The filename, not the full path. iOS renames the application container on
  /// every update, so an absolute path stops resolving and the photo silently
  /// disappears — see photo_paths.dart. Callers store what comes back and hand
  /// it to resolvePhotoPath to read it.
  Future<String?> pickAndStore(
    ImageSource source, {
    required String prefix,
    DateTime Function() now = DateTime.now,
  }) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked == null) return null;

    final docs = await getApplicationDocumentsDirectory();
    final photos = Directory('${docs.path}/$photosFolder');
    if (!await photos.exists()) await photos.create(recursive: true);

    final ext = picked.path.contains('.') ? picked.path.split('.').last : 'jpg';
    final name = '${prefix}_${now().millisecondsSinceEpoch}.$ext';
    await File(picked.path).copy('${photos.path}/$name');
    return name;
  }

  /// Best-effort delete of a previously stored photo.
  ///
  /// Takes either form — a bare filename or an absolute path from an older
  /// build — because both are in the config files already out there.
  Future<void> delete(String? stored) async {
    if (stored == null || stored.isEmpty) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final resolved = resolvePhotoPath(stored, docs.path);
      if (resolved == null) return; // already gone, which is the end state
      await File(resolved).delete();
    } catch (_) {/* ignore — a missing file is fine */}
  }
}
