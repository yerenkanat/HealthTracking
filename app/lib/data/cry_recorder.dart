/// Recording a short cry clip for analysis.
///
/// Behind an interface so the cry screen is fully unit-testable with a fake: the
/// real recorder touches the microphone and the filesystem, neither of which
/// exists in a widget test. [RecordCryRecorder] is the production implementation
/// over the `record` plugin; tests inject their own.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// A minimal recorder: start, stop-and-read the bytes, dispose.
abstract class CryRecorder {
  /// Begin recording. Returns false when the microphone is unavailable or the
  /// permission was denied — the caller then shows guidance instead of a spinner.
  Future<bool> start();

  /// Stop and return the recorded audio bytes, or null if nothing was captured.
  ///
  /// The clip must not outlive this call: whatever the implementation wrote to
  /// disk is deleted before the bytes are handed back. See [RecordCryRecorder].
  Future<List<int>?> stopAndRead();

  /// Release native resources. Safe to call more than once.
  Future<void> dispose();
}

/// The slice of the microphone [RecordCryRecorder] uses.
///
/// Extracted so the FILE LIFECYCLE — the part that decides whether a recording
/// of somebody's baby is still on their phone — can be tested for real, with
/// the real recorder class, without a microphone. The default implementation is
/// the `record` plugin and nothing else.
abstract class CryMic {
  Future<bool> hasPermission();

  /// Start capturing to [path].
  Future<void> start(String path);

  /// Stop, returning the path actually written (null if the plugin has none).
  Future<String?> stop();

  Future<void> dispose();
}

/// Production recorder over the `record` plugin. Captures AAC in an m4a-style
/// container at 16 kHz mono — small, and exactly what the classifier wants.
///
/// WHO DELETES THE CLIP
///
/// This class does, and it has to be this class: it is the only code that knows
/// a file was written at all. The screen sees bytes, the classifier client sees
/// bytes, and the privacy line the user reads before the microphone opens says
/// the recording is not kept — while the last cry of her baby sat in the temp
/// directory until the OS felt like reclaiming it, which on Android can be
/// never. The server side of that promise is held to it by
/// packages/backend cryNotStored.test.ts; this is the phone's half.
///
/// Deletion happens in a `finally` on both exits — after the bytes are read
/// (success OR failure of the read, and so before the upload can fail) and
/// again on [dispose], which is the path taken when she leaves the screen
/// mid-recording and stopAndRead is never called at all.
class RecordCryRecorder implements CryRecorder {
  final CryMic _mic;
  final Future<Directory> Function() _tempDir;
  String? _path;

  RecordCryRecorder({CryMic? mic, Future<Directory> Function()? tempDir})
      : _mic = mic ?? _PluginMic(),
        _tempDir = tempDir ?? getTemporaryDirectory;

  @override
  Future<bool> start() async {
    try {
      if (!await _mic.hasPermission()) return false;
      final dir = await _tempDir();
      // Overwrite one fixed temp file rather than piling up clips.
      _path = '${dir.path}/umay_cry.m4a';
      await _mic.start(_path!);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<int>?> stopAndRead() async {
    String? written;
    try {
      final path = await _mic.stop() ?? _path;
      written = path;
      if (path == null) return null;
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    } finally {
      // The bytes are in memory now; the file has no further purpose, whether
      // the upload that follows succeeds or fails. Not after the upload: a
      // throw, a lost connection or a user who walks away must not be able to
      // leave the clip behind.
      await _delete(written ?? _path);
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _mic.dispose();
    } catch (_) {
      // already disposed / never started — nothing to do
    } finally {
      // A recording she abandoned: started, then back-button before the five
      // seconds were up. stopAndRead never ran, so nothing else would ever
      // delete the partial clip.
      await _delete(_path);
    }
  }

  /// Best-effort delete. A file that is already gone, or that the OS will not
  /// let us remove, must not turn into an error the user sees — the analysis
  /// she asked for is unaffected either way.
  Future<void> _delete(String? path) async {
    if (path == null) return;
    _path = null;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // nothing more we can do; not worth surfacing
    }
  }
}

/// The real microphone: the `record` plugin, and nothing else.
class _PluginMic implements CryMic {
  final AudioRecorder _rec = AudioRecorder();

  @override
  Future<bool> hasPermission() => _rec.hasPermission();

  @override
  Future<void> start(String path) => _rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1),
        path: path,
      );

  @override
  Future<String?> stop() => _rec.stop();

  @override
  Future<void> dispose() => _rec.dispose();
}
