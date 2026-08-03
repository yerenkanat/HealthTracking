# Security follow-ups — ana-bala.kz

State as of **2026-08-03**, after the landing went live on `188.137.231.252`.

Nothing here is a hypothetical hardening exercise. Items 1–3 are open now and
each has a concrete consequence; 4–6 are smaller.

---

## 1. Rotate the root password — it has been pasted into a chat twice

**Status:** open. **Who:** owner.

The server's root password was shared in conversation on 2026-07-29 and again on
2026-08-03, so it must be treated as compromised regardless of who saw it. It is
deliberately not written down in this repo or in any agent memory.

```bash
ssh root@188.137.231.252 'passwd'          # new password, not reused anywhere
ssh-copy-id -i ~/.ssh/<yourkey>.pub root@188.137.231.252
# then, in /etc/ssh/sshd_config:
#   PasswordAuthentication no
#   PermitRootLogin prohibit-password
ssh root@188.137.231.252 'systemctl reload sshd'
```

Do the key first and confirm it works in a **second terminal** before disabling
passwords, or a typo locks everyone out of the box.

---

## 2. Staff auth does not exist, so `/admin*` is closed — and the leads queue with it

**Status:** open, and it is blocking real work. **Who:** developer.

`authAdmin` trusts the `x-staff-id` / `x-staff-role` headers outright. There is
no verifier behind them, and `authPosture()` hardcodes `adminStub = true` for
that reason — it is not an env flag, so it cannot be waved through.

Consequence: `/admin*` returns 404 at the edge, which means **nobody can read
the leads the landing page is collecting**, or set the WhatsApp number in
`shop_settings`. The form works and writes to `shop_leads`; the queue is simply
unreadable until this is built.

Two ways out, either acceptable:

- **Quick:** put the admin panel on `admin.ana-bala.kz` behind Caddy
  `basic_auth`, as `deploy/Caddyfile` already sketches. The header stub stays,
  but the edge password gates it. Good enough for a small staff.
- **Proper:** implement a real staff verifier, flip `adminStub` in
  `authPosture.ts`, and let the boot guard pass.

Until one of those ships, read leads directly:

```bash
docker exec umay-db psql -U umay -d umay \
  -c "SELECT created_at, customer_name, phone, package, locale, status FROM shop_leads ORDER BY created_at DESC;"
```

---

## 3. The app API is closed for the same reason

**Status:** open by design. **Who:** developer.

`authUser` is a header stub until `REAL_AUTH=1` plus a Firebase service account.
While it is open, anyone can read any family's data by typing a header — this
was live for a few hours on 2026-08-03 and is now closed:

```bash
curl -H 'x-user-id: <any id>' https://ana-bala.kz/children    # was 200, now 404
```

The edge serves an allow-list (`/`, `/landing/*`, `/shop/*`, `/health`,
`/ready`); everything else 404s. See `docs/DEPLOY.md` §9 for the exact order of
operations to open it. **The Flutter app cannot point at production until then.**

---

## 4. HSTS is `max-age=0`

**Status:** intentional, revisit. **Who:** developer.

Deliberate for the first deploy: a bad certificate with a live `max-age` traps
every visitor on a broken site for the cached duration. Raise it to `31536000`
once HTTPS has been stable for about a week, in `deploy/landing-takeover.sh`.

## 5. The test CRM's Supabase is still published on `:8081`

**Status:** open. **Who:** owner/developer.

`0.0.0.0:8081` proxies to that stack's Kong. It predates our deployment and was
carried over verbatim rather than changed under a landing-page task, but it is a
second front door on the box and nothing of ours needs it. If the CRM test
instance is finished with, remove the `:8081` site block and stop its containers:

```bash
docker ps --filter label=com.docker.compose.project=supabase
```

## 6. Postgres credentials

**Status:** fine, noted. `/etc/umay/backend.env` is `chmod 600` and its password
was generated on the box, never typed into a chat. `umay-db` publishes no port —
it is reachable only from the `supabase_default` Docker network.

---

## Verifying the current posture

```bash
bash /opt/umay/deploy/landing-takeover.sh          # prints the checks below
curl -s -o /dev/null -w '%{http_code}\n' https://ana-bala.kz/admin/ui                 # 404
curl -s -o /dev/null -w '%{http_code}\n' -H 'x-user-id: x' https://ana-bala.kz/children  # 404
curl -s -o /dev/null -w '%{http_code}\n' https://ana-bala.kz/                          # 200
```
