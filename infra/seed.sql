-- Minimal seed for integration smoke tests: one mother, one device, one child,
-- Home + School geofences, and a push token. IDs are fixed so the smoke test can
-- reference them. Run after schema init:
--   docker compose exec -T db psql -U fcs -d fcs < infra/seed.sql

INSERT INTO users (id, email, phone_e164, display_name, locale, timezone, due_date)
VALUES ('11111111-1111-1111-1111-111111111111', 'aigerim@example.kz', '+77001112233',
        'Aigerim', 'ru-KZ', 'Asia/Almaty', DATE '2026-11-01')
ON CONFLICT (id) DO NOTHING;

INSERT INTO devices (id, user_id, ble_mac, model)
VALUES ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111',
        'AA:BB:CC:DD:EE:FF', 'DaFit-OEM-1')
ON CONFLICT (id) DO NOTHING;

INSERT INTO children (id, guardian_id, name, beacon_uuid, beacon_major, beacon_minor)
VALUES ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111',
        'Sultan', 'e2c56db5-dffb-48d2-b060-d0f5a71096e0', 1, 42)
ON CONFLICT (id) DO NOTHING;

-- Home (circle) and School (circle) around Almaty.
INSERT INTO geofences (id, guardian_id, child_id, name, shape, center, radius_m)
VALUES
  ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111',
   '33333333-3333-3333-3333-333333333333', 'Home', 'circle',
   ST_MakePoint(76.889709, 43.238949)::geography, 100),
  ('55555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111',
   '33333333-3333-3333-3333-333333333333', 'School', 'circle',
   ST_MakePoint(76.95, 43.25)::geography, 120)
ON CONFLICT (id) DO NOTHING;

INSERT INTO push_tokens (user_id, platform, token)
VALUES ('11111111-1111-1111-1111-111111111111', 'android', 'test-fcm-token-abc')
ON CONFLICT (user_id, token) DO NOTHING;
