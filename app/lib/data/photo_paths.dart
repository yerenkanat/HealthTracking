/// Turning a stored photo reference into a file on THIS install.
///
/// WHY THIS EXISTS
///
/// Photos were saved as absolute paths — `<docs>/photos/child-1_1700000.jpg` —
/// with a comment that this keeps them valid across restarts. Across restarts,
/// yes. Not across updates: on iOS the application container is named with a
/// UUID that changes every time the app is reinstalled or updated, so every
/// stored path points into a directory that no longer exists.
///
/// The file itself is still there, under the new container. But the avatar
/// checks `File(path).existsSync()` and falls back to initials, so what a
/// mother sees is her child's photo quietly gone after an app update — and
/// nothing broken enough to report.
///
/// So the stored reference is now just the FILENAME, resolved against wherever
/// the documents directory happens to be today.
///
/// Pure dart:io on purpose: no Flutter, no plugins, so the resolution rule is
/// exercised by a tool runner rather than only on a device that has been
/// updated.
library;

import 'dart:io';

/// The folder photos live in, under the app's documents directory.
const photosFolder = 'photos';

/// Where the documents directory is on this run, resolved once at startup.
///
/// Held rather than looked up per use because the avatar resolves a path
/// during build, and getApplicationDocumentsDirectory is async. Null until
/// main sets it, and null simply means no photo resolves yet — the avatar
/// shows initials, which is the same thing it does for a user who never added
/// one.
String? photosDocsPath;

/// Resolve against the directory found at startup. The form the UI uses.
String? resolveStoredPhoto(String? stored) {
  final docs = photosDocsPath;
  if (docs == null) return null;
  return resolvePhotoPath(stored, docs);
}

/// Resolve a stored reference against [docsPath].
///
/// Accepts both forms:
///   · a bare filename, which is what is stored now;
///   · a full path from an older build, which is migrated by taking its
///     filename and looking under today's photos folder.
///
/// The legacy path is returned unchanged ONLY when it still resolves to a file
/// and today's folder does not have it — on Android the container does not
/// move, so those installs keep working untouched rather than being migrated
/// for a problem they do not have.
///
/// Returns null when nothing usable is found, which is exactly what the avatar
/// needs to fall back to initials.
String? resolvePhotoPath(String? stored, String docsPath, {bool Function(String)? exists}) {
  if (stored == null || stored.trim().isEmpty) return null;
  final check = exists ?? (p) => File(p).existsSync();

  final name = photoFileName(stored);
  if (name.isEmpty) return null;

  final candidate = '$docsPath/$photosFolder/$name';
  if (check(candidate)) return candidate;

  // An older absolute path that still points at a real file.
  if (stored != name && check(stored)) return stored;

  return null;
}

/// The filename part of a stored reference, whatever separators it uses.
///
/// Handles both separators explicitly: a backup written on one platform can be
/// restored on the other, so a Windows-style path can reach an Android device
/// and the reverse.
String photoFileName(String stored) {
  final normalized = stored.replaceAll(r'\', '/');
  final cut = normalized.lastIndexOf('/');
  return cut == -1 ? normalized : normalized.substring(cut + 1);
}
