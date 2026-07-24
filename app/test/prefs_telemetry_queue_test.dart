import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fcs_app/data/prefs_telemetry_queue.dart';
import 'package:fcs_app/net/telemetry_batcher.dart';

/// The disk mirror behind the offline telemetry queue. Without it, a reading
/// buffered offline was lost on an app kill; these lock the round-trip that
/// makes it survive.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final store = PrefsTelemetryQueue();

  test('a saved queue restores identically (order, payload, urgent flag)', () async {
    final items = [
      const QueuedItem('telemetry', {'heartRateBpm': 82}, urgent: false),
      const QueuedItem('telemetry', {'systolicMmHg': 168, 'diastolicMmHg': 116}, urgent: true),
      const QueuedItem('location', {'childId': 'c1', 'lat': 43.2, 'lng': 76.9}),
    ];
    await store.save(items);

    final back = await store.load();
    expect(back.length, 3);
    expect(back[0].type, 'telemetry');
    expect(back[0].payload['heartRateBpm'], 82);
    expect(back[1].urgent, isTrue); // the emergency reading keeps its bypass flag
    expect(back[1].payload['systolicMmHg'], 168);
    expect(back[2].type, 'location');
    expect(back[2].payload['childId'], 'c1');
  });

  test('nothing saved restores empty', () async {
    expect(await store.load(), isEmpty);
  });

  test('saving an empty queue clears the mirror', () async {
    await store.save([const QueuedItem('telemetry', {'hr': 70})]);
    expect(await store.load(), isNotEmpty);
    await store.save([]);
    expect(await store.load(), isEmpty);
  });

  test('an unreadable buffer is discarded, not fatal', () async {
    SharedPreferences.setMockInitialValues({'fcs_telemetry_queue_v1': 'not json {['});
    expect(await store.load(), isEmpty); // returns empty instead of throwing
    // and the bad blob is cleared so it cannot fail every launch
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('fcs_telemetry_queue_v1'), isNull);
  });
}
