# SmartParcel — OSCORE / oscore-server edition

On-device Neuton classification on a **Thingy:91 X**, direct **OSCORE/CoAP** to
[oscore-server](https://github.com/joncloud-dev/oscore-server) (no nRF Cloud), and a
live parcel-handling dashboard at `/`.

```
Thingy:91 X ── LTE-M ── OSCORE POST /t (class change only) ──► oscore-server
                                                                 │ hooks → classifications
                                                                 ▼
                                              browser ◄── realtime ── dashboard (/)

```

This repo is the cloud product + a **prebuilt firmware hex**, modeled on
[jhn-nordic/packet_handling_demo](https://github.com/jhn-nordic/packet_handling_demo)
(nRF Cloud) and [joncloud-dev/water-temp](https://github.com/joncloud-dev/water-temp)
(extension layer on the released server image).

## Step 1: What you need

- A host for **oscore-server** (Fly.io account, or Docker on a machine with UDP 5683 open)
- **flyctl** and/or **docker**
- **curl**, **jq**, **openssl**
- Nordic **Thingy:91 X**, debug probe (e.g. nRF9151 DK), SWD cable — or skip hardware and use `scripts/send-test.sh --demo`

## Step 2: Configure

```bash
git clone <this-repo> packet_handling_demo_oscore
cd packet_handling_demo_oscore
cp .env.example .env
```

Edit `.env`:

| Variable | Purpose |
|----------|---------|
| `OSCORE_SERVER_VERSION` | Pin from [releases](https://github.com/joncloud-dev/oscore-server/releases) |
| `PB_OSCORE_KEK` | `openssl rand -hex 32` — never rotate after devices are provisioned |
| `FLY_APP`, `FLY_REGION` | For Fly deploy (globally unique app name) |
| `PB_ADMIN_EMAIL`, `PB_ADMIN_PASSWORD` | PocketBase admin at `/_/` |

## Step 3: Deploy the backend

**Fly.io (recommended for demos with a real device):**

```bash
fly auth login
scripts/fly-deploy.sh
```

Note the **dedicated IPv4** printed at the end — devices use it for `smartparcel server <ip>`.

**Local Docker:**

```bash
docker compose up -d
docker compose exec oscore-server \
  oscore-server superuser upsert you@example.com 'a-strong-password' --dir=/pb_data
```

Dashboard: http://localhost:8090/ — Admin: http://localhost:8090/_/

## Step 4: Provision a parcel

```bash
OSCORE_URL=http://localhost:8090 \
OSCORE_EMAIL=you@example.com OSCORE_PASSWORD='a-strong-password' \
  ./scripts/provision-parcel.sh parcel-01 "Demo parcel"
```

On Fly, set `OSCORE_URL=https://<FLY_APP>.fly.dev` and pass the IPv4 as the 4th argument or `SERVER_IPV4`.

## Step 5: Flash the Thingy:91 X

See [firmware/README.md](firmware/README.md). Program `firmware/smartparcel_oscore.hex` over SWD
(merged image — not USB recovery).

## Step 6: Device shell

After LTE attach, run the commands printed by `provision-parcel.sh`:

```
oscore provision …
smartparcel server <server-ipv4>
reboot
```

The firmware sends **only** classification uplinks (CBOR keys 30–35 on `POST /t`).

## Step 7: Verify

1. Open the dashboard URL.
2. Move the parcel — state should update within seconds.
3. Without hardware: `OSCORE_EMAIL=… PB_ADMIN_PASSWORD=… scripts/send-test.sh --demo`

**OSCORE path test:** copy client context to `scripts/oscore-client-context/` (see README there), then:

```bash
pip install cbor2 aiocoap
OSCORE_HOST=127.0.0.1 python3 scripts/sim-parcel.py --cycles 1
```

## Wire format (classification)

| CBOR key | Field |
|----------|--------|
| 30 | class index 0–6 |
| 31 | confidence 0–1 |
| 32 | event sequence |
| 33 | inference age (ms) |
| 34 | prior RTT (ms) |
| 35 | packed class probabilities |

States: idle, shaking, impact, freefall, carrying, car, placed.

## Repository layout

| Path | Role |
|------|------|
| `pb_hooks/` | Project telemetry → `classifications` |
| `pb_migrations/` | `smartparcel` profile + collections |
| `pb_public/` | Dashboard |
| `docker-compose.yml` | Pinned `ghcr.io/joncloud-dev/oscore-server` image |
| `Dockerfile`, `fly.toml` | Fly image (extensions baked in) |
| `scripts/` | Deploy, provision, REST demo, OSCORE sim |
| `firmware/` | Prebuilt hex + flash notes |

## Troubleshooting

| Symptom | Check |
|---------|--------|
| Device log: server IP not configured | `smartparcel server <ipv4>` then reboot |
| OSCORE / replay errors | Do not lose `pb_data`; reset client `sequence.json` if needed |
| Dashboard empty, sim works | Profile `smartparcel` on device; hook backfill: `POST /api/smartparcel/backfill` |
| Fly: no UDP | Dedicated IPv4 + port 5683; server binds `fly-global-services:5683` |

## License

MIT — see [LICENSE](LICENSE). The oscore-server binary/image is under its
[Binary License](https://github.com/joncloud-dev/oscore-server/blob/main/LICENSE-BINARY.txt).
