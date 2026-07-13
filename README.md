# BlueOS Site Stack — Mosquitto + InfluxDB 1.8 + Telegraf

A single BlueOS extension that runs **Mosquitto**, **InfluxDB 1.8**, and
**Telegraf** together in one container on the onboard computer (Raspberry Pi
3B+ / 4 / 5). Install it once and ESPHome devices on the LAN publish MQTT
telemetry that auto-ingests into a local time-series database — no tokens, no
manual wiring, no Home Assistant required.

```text
ESPHome / other extensions  →  Mosquitto (:1883)  →  Telegraf  →  InfluxDB 1.8 (:8086)
                        (all three run inside this one container)
```

This is the **product** extension. It combines the standalone engineering
repos [`blueos-mosquitto`](https://github.com/vshie/blueos-mosquitto) and
[`blueos-influxdb`](https://github.com/vshie/blueos-influxdb) into the single
image operators actually install. See the workstation plan for the full
three-extension roadmap (`blueos-site-stack`, `blueos-site-ui`,
`blueos-site-esphome`).

## Features

- **Mosquitto MQTT** on host ports **1883** (TCP) and **9001** (WebSockets),
  anonymous LAN access for v0.1.
- **InfluxDB 1.8** on host port **8086**, database `esphome` created
  automatically, HTTP auth disabled for LAN v0.1.
- **Telegraf**, pre-configured to subscribe to ESPHome topics *and* a
  documented convention for other BlueOS extensions — see
  [Topic conventions](#topic-conventions) below.
- **Zero cross-container networking** — Mosquitto, InfluxDB, and Telegraf all
  run in the same container and talk over `127.0.0.1`, so there's nothing to
  misconfigure between services.
- **Status page** on the dynamically mapped container port **80** (BlueOS
  "Open" link) showing live broker/DB status and the topic cheat-sheet.
- **BlueOS sidebar** via `/register_service` (name **Site Stack**) — see
  [Web Interface (HTTP Server)](https://blueos.cloud/docs/latest/development/extensions/#web-interface-http-server).
- **Persistent data** under `/usr/blueos/extensions/site-stack/` on the
  vehicle / site computer (separate subfolders for Mosquitto and InfluxDB).
- **Multi-arch images**: `linux/arm/v7`, `linux/arm64/v8`, `linux/amd64`.

**Why Influx 1.8, not 2.x?** InfluxDB 2.x has no `linux/arm/v7` image, which
would drop Pi 3B+ and 32-bit Pi 4 BlueOS installs. 1.8 keeps every common Pi
supported on one image.

## Ports

| Port | Binding | Use |
|------|---------|-----|
| `1883` | Host `1883` | MQTT TCP (ESPHome, `mosquitto_sub`, other extensions) |
| `9001` | Host `9001` | MQTT over WebSockets |
| `8086` | Host `8086` | InfluxDB HTTP API (also usable for Grafana) |
| `80` | Dynamic (`HostPort: ""`) | Status page (BlueOS sidebar "Open") |

## Manual install on BlueOS

Install **only** through BlueOS → **Extensions** → **Installed** → **+**.
Do **not** use a bare `docker run` — that skips Kraken registration, so the
extension will not appear under Installed and will **not** respawn after a
BlueOS reboot.

### 0. Remove conflicting extensions first

`blueos-site-stack` binds host ports **1883**, **9001**, and **8086**. If you
already have either of these installed, **disable or uninstall them first**:

| Old extension | Image | Conflict |
|---------------|-------|----------|
| Mosquitto MQTT Broker | `vshie/blueos-mosquitto` | `:1883`, `:9001` |
| InfluxDB + Telegraf | `vshie/blueos-influxdb` | `:8086` |

Site-stack replaces both. Persistence paths differ (`site-stack/…` vs
`mosquitto` / `influxdb`), so old broker/Influx data is not migrated
automatically.

### 1. Fill the install form

Open BlueOS → **Extensions** → **Installed** → **+** (bottom right) and enter:

| Field | Value |
|-------|--------|
| **Extension Identifier** | `vshie.sitestack` |
| **Extension Name** | `Site Stack (MQTT + InfluxDB)` |
| **Docker image** | `vshie/blueos-site-stack` |
| **Docker tag** | `main` |

> Prefer a SemVer tag (e.g. `0.1.0`) once one exists — SemVer tags also get
> `:latest` from CI. Until then use `main`.

### 2. Custom settings (permissions JSON)

Paste this JSON verbatim into **Custom settings**:

```json
{
  "ExposedPorts": {
    "80/tcp": {},
    "1883/tcp": {},
    "9001/tcp": {},
    "8086/tcp": {}
  },
  "HostConfig": {
    "ExtraHosts": ["host.docker.internal:host-gateway"],
    "PortBindings": {
      "80/tcp": [
        {
          "HostPort": ""
        }
      ],
      "1883/tcp": [
        {
          "HostPort": "1883"
        }
      ],
      "9001/tcp": [
        {
          "HostPort": "9001"
        }
      ],
      "8086/tcp": [
        {
          "HostPort": "8086"
        }
      ]
    },
    "Binds": [
      "/usr/blueos/extensions/site-stack/mosquitto:/mosquitto/data",
      "/usr/blueos/extensions/site-stack/influxdb:/var/lib/influxdb"
    ]
  }
}
```

Then confirm / install and wait for the image pull to finish.

### 3. Verify it is installed and will survive reboot

1. **Installed tab** — you should see **Site Stack (MQTT + InfluxDB)** listed
   and enabled (same place as Cockpit). If it is missing, the install did not
   go through Kraken; uninstall any hand-started container and use the **+**
   form above.
2. **Open** — use the extension’s Open / status link (dynamic host port for
   container port `80`) to load the status page.
3. **Survive reboot** — only Kraken-registered extensions restart with BlueOS.
   After a reboot, confirm the card is still under Installed and that
   `:1883` / `:8086` are listening again.

Quick checks from a laptop on the same LAN:

```bash
mosquitto_sub -h <blueos-ip> -t '#' -v
mosquitto_pub -h <blueos-ip> -t 'test/hello' -m 'ping'
curl "http://<blueos-ip>:8086/query?db=esphome" --data-urlencode "q=SHOW MEASUREMENTS"
```

### ESPHome

On the device YAML (broker = BlueOS Pi address on your LAN):

```yaml
mqtt:
  broker: 192.168.1.x
  # discovery: false
  topic_prefix: blueos/relay
```

Standard ESPHome MQTT topics (`<prefix>/sensor/<id>/state`,
`<prefix>/switch/<id>/state`, `<prefix>/status`, …) are auto-ingested — no
Telegraf changes needed.

## Topic conventions

Telegraf inside this extension subscribes to `blueos/#` using the patterns
below, so **any** publisher on the LAN that follows this convention gets
auto-ingested into InfluxDB's `esphome` database with zero configuration.
The prefix (`blueos/`) is configurable via the `MQTT_TOPIC_PREFIX` env var if
you need a different namespace.

### ESPHome devices (default ESPHome MQTT component topics)

| Topic pattern | Meaning | Influx measurement |
|----------------|---------|---------------------|
| `blueos/<node_id>/sensor/<object_id>/state` | Numeric sensor (float payload) | `esphome_sensor` |
| `blueos/<node_id>/switch/<object_id>/state` | Switch ON/OFF | `esphome_switch` |
| `blueos/<node_id>/binary_sensor/<object_id>/state` | Binary sensor ON/OFF | `esphome_switch` |
| `blueos/<node_id>/status` | Online/offline (LWT) | `esphome_status` |

This matches ESPHome's default MQTT topic layout when
`topic_prefix: blueos/<node_id>` is set on the device — no custom topics
required on the ESP side.

### Other BlueOS extensions (site-wide telemetry + commands)

To let **any** other BlueOS extension (battery monitor, bilge pump
controller, your own custom sensor bridge, …) contribute telemetry to the
same database — and optionally accept commands back — publish under
`blueos/ext/<extension-slug>/…`:

| Topic pattern | Meaning | Auto-ingested? |
|----------------|---------|-----------------|
| `blueos/ext/<slug>/<metric>/state` | One numeric metric per topic (float payload), e.g. `blueos/ext/battery-monitor/voltage/state` | Yes → measurement `blueos_ext_metric`, tagged by full topic |
| `blueos/ext/<slug>/json` | Structured JSON with multiple fields in one message, e.g. `{"voltage":12.6,"current":1.2}` on `blueos/ext/battery-monitor/json` | Yes → measurement `blueos_ext_json`, fields = JSON keys |
| `blueos/ext/<slug>/cmd/<action>/set` | Command / control channel — **your** extension subscribes to this and acts on it | No (not ingested; this is for control, not telemetry) |
| `blueos/ext/<slug>/status` | Online/offline for your extension | Yes → measurement `esphome_status` (shared with ESPHome LWT pattern) |

`<slug>` should be short, stable, and match your extension's Docker image
name (e.g. `battery-monitor`, `bilge-pump`, `site-ui`) so measurements/tags
stay predictable across a fleet of sites.

**Why this convention?** It lets `blueos-site-ui` (Grafana) and any future
extension build dashboards and controls against one shared broker + database
without every extension shipping its own Influx/Telegraf sidecar — install
this one extension, and everything else just publishes/subscribes to MQTT.

### Adding new ingestion patterns

If your extension's data doesn't fit the two patterns above, open a PR
against `config/telegraf.conf` in this repo (or run your own Telegraf
`inputs.mqtt_consumer` block against `<blueos-ip>:1883` from your own
extension) — the broker is shared and open on the LAN by design.

## Time sync — true timestamps without internet

Raspberry Pi has no battery-backed RTC. If the site has no internet NTP at
boot, the host clock is whatever `fake-hwclock` restored (stale) — every
InfluxDB/Telegraf timestamp is wrong for as long as that lasts. This
extension runs a small sidecar (`scripts/time_from_rtc.py`, stdlib-only, no
extra pip deps) alongside Mosquitto/InfluxDB/Telegraf that:

1. Subscribes to `blueos/+/sensor/rtc_epoch/state` (any ESPHome node with a
   real-time clock, e.g. `blueos-relay`'s DS3231 — see
   `blueos-site-esphome`'s `RTC Epoch` sensor) via the `mosquitto_sub` CLI
   already bundled in this image.
2. Every 30s, checks whether *this container* can reach the internet (TCP
   probes to a few public resolvers). If it can, it assumes the host's own
   NTP client is doing its job and does **not** touch the clock.
3. If there's no internet **and** a recent RTC sample is available **and**
   the drift exceeds 5s, it corrects the host clock with `date -u -s
   @<epoch>`.
4. Publishes its status to `blueos/ext/site-stack/json` (auto-ingested into
   InfluxDB via the existing "other extensions" JSON convention below) with
   fields `time_source` (`ntp` / `esp-rtc` / `esp-rtc-ok` /
   `esp-rtc-stale` / `esp-rtc-correcting` / `unknown`), `internet`,
   `drift_seconds`, `rtc_sample_age_seconds`, `clock_set_attempted`,
   `clock_set_ok`.

**Setting the host clock requires the `CAP_SYS_TIME` Linux capability**,
which this extension's default permissions request (`"CapAdd":
["SYS_TIME"]`). Without it, the sidecar still runs and reports accurate
status — it just can't actually correct the clock, and logs a clear message
the first time it tries. If you installed this extension before this
capability was added, edit its **Custom settings** in BlueOS → Extensions to
add `"CapAdd": ["SYS_TIME"]` under `HostConfig` and reinstall/recreate the
container to pick it up (a plain image update/restart does **not** change
an already-created container's capabilities).

Tunables (env vars, all optional): `TIME_SYNC_ENABLE` (default `true`),
`TIME_SYNC_DRIFT_THRESHOLD_S` (default `5`), `TIME_SYNC_CHECK_INTERVAL_S`
(default `30`), `TIME_SYNC_MAX_SAMPLE_AGE_S` (default `600`),
`TIME_SYNC_INTERNET_HOSTS` (default a few public DNS resolvers, `host:port`
comma-separated), `TIME_SYNC_TOPIC_FILTER` (default
`<prefix>+/sensor/rtc_epoch/state`).

Quick check from a laptop on the same LAN:

```bash
mosquitto_sub -h <blueos-ip> -t 'blueos/ext/site-stack/json' -v
```

## Zero-config wiring

Because Mosquitto, InfluxDB, and Telegraf are all in **one** container:

- Telegraf reaches Mosquitto and InfluxDB over `127.0.0.1` — no
  `host.docker.internal`, no Docker network configuration, no race between
  separately-started extensions.
- ESPHome devices and other extensions on the LAN/host still just point at
  the BlueOS Pi's IP on port `1883` (host-published), which is this
  container's Mosquitto.
- `ExtraHosts: host.docker.internal:host-gateway` is kept in the permissions
  JSON for compatibility with other extensions that may want to reach this
  stack from outside; it isn't required for the stack's own internal wiring.

## Building / releasing

Pushing to `main` (or a git tag) triggers `.github/workflows/deploy.yml`,
which uses
[`BlueOS-community/Deploy-BlueOS-Extension`](https://github.com/BlueOS-community/Deploy-BlueOS-Extension)
to build and push multi-arch images to Docker Hub.

| Platform | Hardware |
|----------|----------|
| `linux/arm/v7` | Raspberry Pi 3B+, Pi 4 32-bit BlueOS |
| `linux/arm64/v8` | Raspberry Pi 4 64-bit, **Raspberry Pi 5** |
| `linux/amd64` | Desktop / CI smoke |

**Repository secrets required:** https://github.com/vshie/blueos-site-stack/settings/secrets/actions

- `DOCKER_USERNAME` = `vshie`
- `DOCKER_PASSWORD` = Docker Hub [access token](https://hub.docker.com/settings/security) (same token used by `blueos-mosquitto` / `blueos-influxdb` can be reused)

Until those secrets are added, CI will fail at the push-to-Docker-Hub step —
the Dockerfile/README are still fully usable for a local build in the
meantime (see below).

Published as: **`vshie/blueos-site-stack:<branch-or-tag>`**.

## Local development

```bash
docker build -t blueos-site-stack:local .
docker run --rm \
  -p 1883:1883 -p 9001:9001 -p 8086:8086 -p 8080:80 \
  blueos-site-stack:local
# open http://localhost:8080 for the status page
# open http://localhost:8086/query?q=SHOW+DATABASES for Influx
```

## Provenance / credits

This is **not** a fork of the official `eclipse-mosquitto` or `influxdb`
Docker Hub images.

| Layer | Source |
|-------|--------|
| Base OS | Debian, via official [`influxdb:1.8.10`](https://hub.docker.com/_/influxdb) |
| MQTT broker | Debian apt package `mosquitto` → upstream **[Eclipse Mosquitto](https://mosquitto.org/)** |
| Time-series DB | Official [`influxdb:1.8.10`](https://hub.docker.com/_/influxdb) |
| Metrics agent | Binary copied from official [`telegraf:1.32`](https://hub.docker.com/_/telegraf) (Debian image — alpine lacks `linux/arm/v7`) |
| This repo | BlueOS wrapper (config, entrypoint, status UI, permissions labels) |

Eclipse Mosquitto is dual-licensed under
[EPL-2.0](https://www.eclipse.org/legal/epl-2.0/) /
[EDL-1.0](https://www.eclipse.org/org/documents/edl-v10.php). InfluxDB and
Telegraf are upstream MIT-licensed.

## v0.1 notes / roadmap

- Anonymous MQTT publish/subscribe and Influx HTTP API on the LAN — suitable
  for an isolated site/vehicle network. **Do not** expose ports `1883` or
  `8086` to the public internet. A password-file / auth release is planned
  for a later version.
- No TLS yet.
- Part of the three-extension BlueOS static-site stack:
  1. **`blueos-site-stack`** (this repo) — Mosquitto + Influx + Telegraf
  2. **`blueos-site-ui`** — Grafana (provisioned) + relay control page
  3. **`blueos-site-esphome`** — ESPHome Device Builder + bundled
     `blueos-relay` YAML, with the MQTT broker injected from BlueOS Beacon
     (`GET /hostname` → `{name}.local`) rather than a hardcoded
     `blueos.local`

## License

Extension packaging: community BlueOS extension conventions, same as
`blueos-mosquitto` / `blueos-influxdb`. Upstream Mosquitto remains
EPL-2.0/EDL-1.0; InfluxDB and Telegraf remain MIT.
