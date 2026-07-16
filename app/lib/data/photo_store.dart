/// Photo storage — picks an image (gallery or camera) and copies it into the
/// app's documents directory so the saved path stays valid across restarts.
/// Kept out of the domain layer (does file IO + plugin calls).
library;

import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class PhotoStore {
  final ImagePicker _picker;
  PhotoStore({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  /// Pick an image from [source], downscale, copy into <docs>/photos, and return
  /// the stored path. Returns null if the user cancels the picker.
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
    final photos = Directory('${docs.path}/photos');
    if (!await photos.exists()) await photos.create(recursive: true);

    final ext = picked.path.contains('.') ? picked.path.split('.').last : 'jpg';
    final dest = '${photos.path}/${prefix}_${now().millisecondsSinceEpoch}.$ext';
    await File(picked.path).copy(dest);
    return dest;
  }

  /// Best-effort delete of a previously stored photo.
  Future<void> delete(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {/* ignore — a missing file is fine */}
  }
}
