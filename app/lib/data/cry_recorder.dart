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
  Future<List<int>?> stopAndRead();

  /// Release native resources. Safe to call more than once.
  Future<void> dispose();
}

/// Production recorder over the `record` plugin. Captures AAC in an m4a-style
/// container at 16 kHz mono — small, and exactly what the classifier wants.
class RecordCryRecorder implements CryRecorder {
  final AudioRecorder _rec = AudioRecorder();
  String? _path;

  @override
  Future<bool> start() async {
    try {
      if (!await _rec.hasPermission()) return false;
      final dir = await getTemporaryDirectory();
      // Overwrite one fixed temp file rather than piling up clips.
      _path = '${dir.path}/umay_cry.m4a';
      await _rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1),
        path: _path!,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<int>?> stopAndRead() async {
    try {
      final path = await _rec.stop() ?? _path;
      if (path == null) return null;
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _rec.dispose();
    } catch (_) {
      // already disposed / never started — nothing to do
    }
  }
}
