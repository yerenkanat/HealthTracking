# Putting the landing page on `ana-bala.kz` (and taking it back off)

`deploy/landing-stack.sh` makes the backend **exist**. This step makes it
**reachable** — and it is the only part that touches something already running,
so it is written to be undone in one command.

## The situation

`ana-bala.kz` is served by `aiti_caddy`, the Caddy container of the **Aiti.kz
CRM** — a live product with its own self-hosted Supabase (Postgres, auth,
storage, realtime), a WhatsApp session DB and a CRM API. Its Caddyfile names
`ana-bala.kz, www.ana-bala.kz` explicitly; this is a deliberate deployment, not
stale DNS.

So the landing cannot simply "take the domain" without deciding what happens to
that CRM. What it *can* do safely is take the paths the CRM does not use.

| Path | Owner after this change |
| --- | --- |
| `/` (exact) | **landing page** |
| `/landing/*` | **landing** (fonts, images, React, the runtime) |
| `/shop/*` | **landing** (the lead form `POST /shop/leads`, the OG image, product pages) |
| `/api/v1/*`, `/api/wa/*`, `/rest/*`, `/auth/v1/*`, `/storage/*` | CRM — untouched |
| `/assets/*`, `/videos/*`, every other path | CRM SPA — untouched |

Only the **bare root** changes hands. The CRM's own deep links (`/login`,
`/dashboard`, …) still hit its SPA fallback, and every API it depends on is
untouched. Someone typing `ana-bala.kz` now lands on the Ana-Bala page.

> **`/admin/*` and the app API are deliberately NOT routed.** The backend's
> staff auth is still the `x-staff-role` header stub — anyone who could reach
> `/admin/ui` would have full admin. Keeping it off the public proxy is what
> makes running without `NODE_ENV=production` acceptable here. Do not add an
> `/admin` route until real staff auth exists (see docs/DEPLOY.md §5).

## Apply

The Caddyfile lives on the host at `/opt/aiti/app/docker/Caddyfile` and is
mounted into the container.

1. **Back it up** (dated, so several attempts do not overwrite each other):
   ```bash
   cp -a /opt/aiti/app/docker/Caddyfile \
         /opt/aiti/app/docker/Caddyfile.bak.before-umay-landing-$(date +%F-%H%M)
   ```

2. Inside the `ana-bala.kz, www.ana-bala.kz { … }` block, **immediately before**
   the final catch-all `handle { root * /app/dist … }`, insert:

   ```caddyfile
   # ---- Ana-Bala landing page (umay-backend) --------------------------------
   # Order matters in Caddy: these must sit BEFORE the SPA catch-all, and after
   # the CRM's own /api, /rest, /auth, /storage handles (which are above).
   handle / {
       reverse_proxy umay-backend:8080
   }
   handle /landing/* {
       reverse_proxy umay-backend:8080
   }
   handle /shop/* {
       reverse_proxy umay-backend:8080
   }
   ```

3. Reload without dropping connections:
   ```bash
   docker exec aiti_caddy caddy reload --config /etc/caddy/Caddyfile
   ```

4. Verify:
   ```bash
   curl -sS https://ana-bala.kz/ | grep -o '<title>[^<]*</title>'   # Ana-Bala …
   curl -s -o /dev/null -w '%{http_code}\n' https://ana-bala.kz/login   # CRM still 200
   ```

## Roll back

```bash
cp -a /opt/aiti/app/docker/Caddyfile.bak.before-umay-landing-<stamp> \
      /opt/aiti/app/docker/Caddyfile
docker exec aiti_caddy caddy reload --config /etc/caddy/Caddyfile
```

The CRM is serving the root again within a second. To remove the backend too:

```bash
docker rm -f umay-backend umay-db      # add: docker volume rm umay_pgdata
```

## The decision this defers

Two products currently share one hostname. That works, but it is not where this
should end up. Pick one:

- **CRM moves** to `crm.ana-bala.kz` (or its own domain) and `ana-bala.kz`
  becomes wholly the Ana-Bala product — then the app API (`/api/v1/*`) can also
  live here, which it cannot today because the CRM already uses that prefix.
- **Landing moves** to its own domain and the CRM keeps this one.

Until that is settled the Flutter app must **not** point `API_BASE` at
`https://ana-bala.kz` — `/api/v1/*` there is the CRM's, not ours.

## `aiti_caddy` reports "unhealthy". It is not.

`docker ps` has shown the proxy as unhealthy since the day it started — 8928
consecutive failures and counting. The site is fine; the healthcheck is wrong.

It probes Caddy's admin API:

    wget -q --spider http://localhost:2019/config/ || exit 1

which refuses inside that container, and has never once succeeded. The admin
API itself works — `docker exec aiti_caddy caddy reload` uses it and that is how
every config change in this repo is applied.

It is **not** fixed here because the healthcheck is baked into the container's
config, so changing it means recreating the one container that is serving
ana-bala.kz — a real outage risk to silence a cosmetic flag on a container
inherited from the CRM stack.

What matters is covered properly instead: `deploy/uptime-check.sh` requests the
landing over TLS *through this proxy* every five minutes, which tests what the
healthcheck was reaching for and more.

If the proxy is ever recreated for another reason, drop the healthcheck or point
it at `https://ana-bala.kz/` — and until then, do not spend an afternoon on this
flag the way it invites you to.
