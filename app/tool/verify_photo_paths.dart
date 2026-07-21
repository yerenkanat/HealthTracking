/// Verification of stored-photo resolution.
/// `dart run tool/verify_photo_paths.dart`
///
/// Photos were saved as absolute paths under the app's documents directory.
/// On iOS that directory is named with a container UUID that CHANGES on every
/// update or reinstall, so after an update every stored path pointed into a
/// directory that no longer existed. The file was still on disk; the avatar
/// checked existsSync, found nothing, and fell back to initials.
///
/// What a mother saw was her child's photo quietly gone after an app update,
/// with nothing broken enough to report.
library;

import 'dart:io';
import '../lib/data/photo_paths.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  // Container paths before and after an iOS update. Same app, same file.
  const oldDocs = '/var/mobile/Containers/Data/Application/AAAA-1111/Documents';
  const newDocs = '/var/mobile/Containers/Data/Application/BBBB-2222/Documents';
  const file = 'child-1_1700000000000.jpg';

  /// Only the file under the NEW container exists — the state after an update.
  bool onlyNew(String p) => p == '$newDocs/$photosFolder/$file';

  // ---- The filename form, which is what is stored now ----
  _chk('a filename resolves under the current documents directory',
      resolvePhotoPath(file, newDocs, exists: onlyNew) == '$newDocs/$photosFolder/$file');

  // ---- The migration that matters ----
  _chk('a path saved before the update still finds the photo after it',
      resolvePhotoPath('$oldDocs/$photosFolder/$file', newDocs, exists: onlyNew) ==
          '$newDocs/$photosFolder/$file');

  // ---- An install where nothing moved ----
  {
    // Android keeps the same container, so an old absolute path still points at
    // a real file. Those installs must keep working untouched.
    bool onlyOld(String p) => p == '$oldDocs/$photosFolder/$file';
    _chk('an absolute path that still resolves is left alone',
        resolvePhotoPath('$oldDocs/$photosFolder/$file', oldDocs, exists: onlyOld) ==
            '$oldDocs/$photosFolder/$file');
  }

  // ---- Nothing there ----
  _chk('a photo that was deleted resolves to nothing',
      resolvePhotoPath(file, newDocs, exists: (_) => false) == null);
  _chk('null in, null out', resolvePhotoPath(null, newDocs, exists: (_) => true) == null);
  _chk('empty in, null out', resolvePhotoPath('   ', newDocs, exists: (_) => true) == null);

  // ---- Filenames across platforms ----
  //
  // A backup written on one platform can be restored on the other, so both
  // separators have to be understood — a Windows-style path can reach an
  // Android device and the reverse.
  _chk('a posix path yields its filename', photoFileName('/a/b/c.jpg') == 'c.jpg');
  _chk('a windows path yields its filename',
      photoFileName(r'C:\Users\x\Documents\photos\c.jpg') == 'c.jpg');
  _chk('a bare filename is already the filename', photoFileName('c.jpg') == 'c.jpg');
  _chk('a trailing separator yields nothing rather than a directory',
      photoFileName('/a/b/') == '');
  _chk('a reference that is only a separator resolves to nothing',
      resolvePhotoPath('/a/b/', newDocs, exists: (_) => true) == null);

  // ---- The startup-resolved form ----
  {
    // Before main has found the documents directory, nothing resolves — which
    // is the same as having no photo, and shows initials rather than throwing.
    photosDocsPath = null;
    _chk('nothing resolves before startup has found the directory',
        resolveStoredPhoto(file) == null);

    // The real check hits the filesystem, so point it at a real temp file.
    final dir = Directory.systemTemp.createTempSync('umay_photos');
    Directory('${dir.path}/$photosFolder').createSync(recursive: true);
    File('${dir.path}/$photosFolder/$file').writeAsStringSync('x');
    photosDocsPath = dir.path;
    _chk('once set, a stored filename resolves to a real file',
        File(resolveStoredPhoto(file)!).existsSync());
    _chk('and an old absolute path migrates to it',
        resolveStoredPhoto('$oldDocs/$photosFolder/$file') == '${dir.path}/$photosFolder/$file');
    photosDocsPath = null;
    dir.deleteSync(recursive: true);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
