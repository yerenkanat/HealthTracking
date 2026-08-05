# Connecting the app to the live server

The app does not talk to ana-bala.kz today. This is the ordered procedure for
the day the credentials exist. Read the whole thing before starting: step 4 is
the one that cannot be done early, and doing it early is the failure this
document exists to prevent.

## Where things actually stand

| | state |
|---|---|
| App sign-in | phone + OTP, running on `StubPhoneAuthProvider` — accepts `123456` for any valid number and mints `stub-token:<uid>` locally. No SMS is sent, no server is involved. |
| App data | `API_BASE` defaults to `http://localhost:8080`. A release build without `--dart-define` points at the handset itself, so nothing loads. |
| Server | Serves every app route correctly. `/children` returns 200 to the backend container right now. |
| Edge | Caddy allow-lists the landing, `/shop*`, `/admin*`, `/health`, `/ready`. **Every app path 404s**, deliberately. |
| `REAL_AUTH` | unset, so the backend still honours `x-user-id` and the app's stub token. |

So the app is a complete, working local product, and the server is a complete,
working remote one, with nothing joining them.

## Why the edge is closed

With `REAL_AUTH` unset, `makeAuthUser` accepts the `x-user-id` header. Opening
the allow-list before turning that off would mean:

```
curl -H 'x-user-id: <any uuid>' https://ana-bala.kz/children
```

returns that family's children. This was true once and is the reason the
allow-list is deny-by-default rather than deny-a-list. **The order below is not
a preference.**

## The procedure

### 1. Get the Firebase service account

Firebase console → Project settings → Service accounts → *Generate new private
key*. A JSON file. It is a credential: it goes to the server over SSH, never
into the repository, and never into a chat window.

```bash
scp serviceAccount.json root@<host>:/etc/umay/firebase.json
ssh root@<host> 'chmod 600 /etc/umay/firebase.json && chown root:root /etc/umay/firebase.json'
```

### 2. Enable phone sign-in in Firebase

Authentication → Sign-in method → Phone. Add ana-bala.kz to the authorised
domains. Kazakh numbers are `+7…`; send yourself a test code before going
further, because an SMS quota or an unverified billing account fails here and
nowhere else.

### 3. Turn on real user auth

```bash
ssh root@<host>
printf 'REAL_AUTH=1\nGOOGLE_APPLICATION_CREDENTIALS=/etc/umay/firebase.json\n' >> /etc/umay/backend.env
docker restart umay-backend
docker logs --tail 30 umay-backend        # must NOT say "authentication is still a development stub"
```

Confirm the stub is dead **before** opening anything:

```bash
# from the host, bypassing the edge
docker exec umay-backend wget -qO- --header='x-user-id: 11111111-1111-1111-1111-111111111111' \
  http://127.0.0.1:8080/children
# expected: 401. If this returns data, STOP — step 4 would expose it publicly.
```

### 4. Open the edge — only after step 3 returns 401

Add the app paths to the `@public` matcher in `deploy/landing-takeover.sh`,
then re-run it. The script validates the config, pushes it into the container
and compares checksums before reloading, so a bad edit cannot take the site
down.

```bash
cd /opt/umay && git pull && bash deploy/landing-takeover.sh
```

Verify from outside:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -H 'x-user-id: <any uuid>' https://ana-bala.kz/children   # 401
curl -s -o /dev/null -w '%{http_code}\n' -H 'Authorization: Bearer <real firebase token>' https://ana-bala.kz/children  # 200
```

### 5. Point the app at production and ship a build

> **The app cannot do Firebase sign-in yet, and this is not a flag.** There is
> no `firebase_auth` or `firebase_core` in `pubspec.yaml`, no
> `google-services.json`, and no real implementation of `PhoneAuthProvider` —
> only `StubPhoneAuthProvider`, which accepts `123456` locally. An earlier
> version of this document told you to pass `--dart-define=REAL_PHONE_AUTH=1`.
> That flag does not exist; I invented it. Steps 1–4 make the *server* ready,
> and the server is genuinely ready — but a build pointed at production would
> still have no way to obtain a token the server accepts.
>
> Closing that gap means: add the two packages, drop in `google-services.json`,
> implement a `FirebasePhoneAuthProvider` behind the existing interface, and
> handle the SMS-cost and delivery questions. It is app work, not configuration.
>
> **See "The alternative" at the foot of this document** before committing to
> it — the server already has everything needed to do phone sign-in itself,
> without Firebase, without SMS, and without any credential from anybody.

```bash
flutter build appbundle --release \
  --dart-define=API_BASE=https://ana-bala.kz
```

`API_BASE` must have **no path** — `https://ana-bala.kz`, not
`https://ana-bala.kz/v1`. See the note in `data/http_transport.dart`: a path is
silently dropped and every request goes to the wrong place.

### 6. Prove it end to end, on a real handset

1. Install the build on a phone that has never run the app.
2. Sign in with a real number and a real SMS code.
3. Add a child, log a reading, force-quit, reinstall, sign in again — the data
   must come back. That is the whole point of the server.
4. Open the back office: the user appears in Пользователи, and the audit log
   records who looked at her record.

Only step 6 proves the thing works. Steps 1–5 prove nothing failed yet.

## Rolling back

Every step is reversible, in reverse order:

```bash
bash deploy/landing-takeover.sh --revert     # closes the edge again
sed -i '/^REAL_AUTH=1$/d' /etc/umay/backend.env && docker restart umay-backend
```

The installed app keeps working against its local store; it degrades to what it
does today rather than breaking.

## The alternative: sign-in without Firebase

Worth deciding before spending money, because most of it is already built.

The back office signs staff in with a phone number and a password: scrypt
hashing, session tokens stored as sha256, per-phone rate limiting, sessions that
die on a password change. `staffAuth.ts` and `staffLogin.ts` are generic — none
of it is specific to staff. Pointing the same machinery at app users is a day's
work on the server and a small one in the app, where `PhoneAuthProvider` is
already an interface with a stub behind it: a second implementation that calls
our own endpoint slots in with no new packages and no `google-services.json`.

|  | Firebase phone auth | Our own |
|---|---|---|
| Verifies the number is really theirs | yes, by SMS | no, until an SMS gateway is added |
| Cost | per SMS, including abandoned sign-ups | none |
| Depends on | a Google project, billing, SMS delivery to KZ numbers | nothing |
| App work | two packages, config file, new provider | one new provider |
| Available | when the account and billing exist | today |

**Recommended:** build ours now so the app is genuinely connected, then add SMS
verification later behind the *same* endpoint — a Kazakh gateway (Mobizon,
SMSC.kz) or Firebase itself. The app does not change again when that happens,
because it is already talking to our server rather than to a provider.

The honest cost of that order: until SMS is added, somebody could sign up with a
number that is not theirs. For a health record that matters eventually. It does
not matter more than having no server at all, and it is reversible.

## What this does not cover

- **Cost.** Firebase phone auth bills per SMS. A test code costs the same as a
  real one, and an abandoned sign-up costs the same as a completed one.
- **The other keys.** Anthropic (the assistant), Telegram (lead alerts) and
  Kaspi (payment link) are entered in the panel under Магазин → Настройки and
  take effect on the next restart. None of them is on this critical path.
- **Offsite backups.** Still same-box only. A host that dies takes the database
  and every backup of it. That is a separate item and it does not wait on
  Firebase.
