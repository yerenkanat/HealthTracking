# Shipping the Android app

What has to exist before a build can be uploaded, and how to make it.
Everything here is a one-off except the last step.

## 1. The upload keystore

Google signs what customers install; this key signs what we upload to Google.
**If it is lost, the app cannot be updated under the same listing** — back it
up somewhere that is not this repository and not one laptop.

```bash
keytool -genkey -v \
  -keystore ~/ana-bala-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

Then `app/android/key.properties`, which is gitignored and must stay that way:

```properties
storePassword=…
keyPassword=…
keyAlias=upload
storeFile=/absolute/path/to/ana-bala-upload.jks
```

`app/android/app/build.gradle.kts` reads it. Without the file the release build
still runs — but it signs with the DEBUG key and prints a warning saying the
result cannot be published. That is deliberate: the previous setup signed with
the debug key silently, and the Play Store only rejects that *after* the
upload, which is the slowest possible place to find out.

## 2. The Google Maps key

The tracking screen is the product, and it renders a blank placeholder without
a key.

1. Google Cloud console → enable **Maps SDK for Android**.
2. Restrict the key to the package `com.fcs.fcs_app` and the SHA-1 of the
   upload keystore (`keytool -list -v -keystore ~/ana-bala-upload.jks`).
3. Export it at build time:

```bash
export GOOGLE_MAPS_API_KEY=AIza…
flutter build appbundle --release --dart-define=MAPS_ENABLED=true
```

`MAPS_ENABLED` is separate on purpose: the manifest key makes the map *able* to
draw, and the dart-define is what turns the real `GoogleMap` on instead of the
placeholder. Both are needed.

## 3. Server-side credentials

These do not affect the build, but the app is not usable without them. None of
them belongs in this repository or in a chat message — put them on the server
over `scp` and reference them from `deploy/backend.env`.

| What | Why it blocks launch |
|---|---|
| **SMS gateway** (`REQUIRE_PHONE_CODE=1` + a provider) | Until this is set, sign-in accepts any phone number with no verification. On a product that shows a child's live location, that means anyone who knows a customer's number can reach her child's map. The verified flow is built and tested behind the flag. |
| **Firebase service account** | Emergency push is wired and has no credentials, so an SOS from a tracker reaches nobody. |
| `ANTHROPIC_API_KEY` | The assistant and the photo-to-vitals extraction 503 without it. Degrades cleanly; not a launch blocker. |

## 4. Legal

The Play Store listing needs a privacy-policy URL. Use
`https://ana-bala.kz/privacy` — it is served from `legal/legal.json`, which is
the same text the app shows in Settings, and a test in each package fails if
the two ever disagree.

The wording is currently marked as a **draft pending legal review**, and the
page says so. That is honest and it is also a thing to close before the
listing goes live, not after.

## 5. Building

```bash
cd app
flutter clean
flutter pub get
flutter test                       # 1300+ tests; CI runs these too
flutter analyze                    # must be zero errors
export GOOGLE_MAPS_API_KEY=AIza…
flutter build appbundle --release --dart-define=MAPS_ENABLED=true
```

The bundle lands at `build/app/outputs/bundle/release/app-release.aab`.

Bump `version:` in `app/pubspec.yaml` before every upload — the Play Store
refuses a build whose `versionCode` it has already seen, and the code is
derived from that line.

## 6. After uploading

Check the release build actually signed correctly before promoting it:

```bash
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
```

The SHA-1 must match the upload keystore, not the debug one. If it matches the
debug key, `key.properties` was missing and the build printed the warning
described in §1.
