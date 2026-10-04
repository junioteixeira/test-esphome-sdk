# criotive ESPHome SDK

Shared ESPHome configuration for criotive firmware, consumed through ESPHome's native
[`packages:`](https://esphome.io/components/packages.html) mechanism. The firmware-generation path
and the build service assemble a device's `main.yaml` by importing modules from this repository at a
pinned tag. No custom import machinery: ESPHome resolves, caches and merges the remote packages
itself.

## Start here — the recommended `main.yaml`

This is the bundle the criotive platform recommends for a board it flashes over USB and updates over
the air. It needs **one substitution, `device_name`** — the platform's build injects
`firmware_version`, and `sdk_ref` is passed through `vars:`.

```yaml
substitutions:
  device_name: greenhouse-1   # lower-case letters, digits and hyphens; unique per device

esp32:
  board: esp32-s3-devkitc-1   # or esp32dev, esp32-c3-devkitm-1, ...
  framework:
    type: esp-idf

packages:
  criotive:
    url: https://github.com/junioteixeira/test-esphome-sdk
    ref: v0.4.0
    files:
      - path: modules/core.yaml
        vars: {sdk_ref: v0.4.0}
      - path: modules/ciotcfg.yaml
        vars: {sdk_ref: v0.4.0}
      - path: modules/wifi.yaml
        vars: {sdk_ref: v0.4.0}
      - path: modules/criotive_mqtt.yaml
        vars: {sdk_ref: v0.4.0}
      - path: modules/ota.yaml
        vars: {sdk_ref: v0.4.0}
      - path: modules/improv_serial.yaml
        vars: {sdk_ref: v0.4.0}

# The device's own entities. Each publishes under the ESPHome object_id of its name:
# "Chip Temp" -> sensor/chip_temp (see "What each module publishes").
sensor:
  - platform: internal_temperature
    name: "Chip Temp"
    update_interval: 30s
```

What that gives the device, with nothing else to supply:

- **Wi-Fi through Improv over the USB cable**, right after the flashing tool writes the image, on the
  console ESPHome picks for the variant — the native USB-Serial/JTAG port on an ESP32-S3 or C3,
  UART0 (the USB-UART bridge) on an ESP32. No Wi-Fi credential is compiled in.
- **MQTT identity from the `ciotcfg` partition**, written by the flashing tool: broker, credentials,
  client id, topic prefix and CA. One image serves the whole fleet.
- **Over-the-air updates through the platform's MQTT `ota` command.** No OTA port is open on the
  LAN, and no OTA password exists to leak.
- `ref` and every `vars.sdk_ref` must be the **same tag** — a tag, never a branch (ESPHome caches a
  branch clone for a day, so `main` is not "latest").

Add a module only for a capability the device needs: `diagnostics.yaml` (device info, reset reason),
`controls.yaml` (remote restart / factory reset), `wifi_ap.yaml` (a fallback access point —
requires `wifi_ap_password`), `improv_ble.yaml` (provisioning from a phone). See
[Modules](#modules) and [What each module publishes](#what-each-module-publishes).

## This repository is public — nothing secret may ever be committed

This repository is **public from creation**. No credential is involved anywhere in the
fetch path, and no authentication is ever added — a private repo would force every clone to
authenticate, and a token in a generated `main.yaml` would be a token shown to the customer.

**Every credential reaches a device as a substitution, never as a value in a config in this
repository.** A value pushed to a public repo is permanent and is *not* revoked by deletion. No
substitution that carries a credential has a default: a missing required credential fails
validation loudly rather than shipping a public default password to every device that forgot to
override it.

## Supported scope: ESP32 only

The public SDK covers **xtensa-esp32** only. riscv32 (`mr60bha2dev`) and ESP8266
(`r`, `esp12`, `nodemcu32`) are out of scope and are never compile-tested here —
`ota.yaml`'s `http_request` OTA, `preferences` and parts of `wifi.yaml` genuinely differ on ESP8266.
Anyone using the SDK on an ESP8266 is off the supported path. ESP8266 can be added later if
customers ask.

Supported hardware:

| Hardware module | Board | Variant | Framework |
|---|---|---|---|
| `hds_v1_0` | `pico32` | `esp32` | `${framework_variant}` (default esp-idf) |
| `hds_v1_1` | `esp32dev` | `esp32` | `${framework_variant}` (default esp-idf) |

Each board is a single file whose esp32 framework is the `framework_variant` substitution, so one
board file serves both frameworks. The default is **esp-idf**; a device that wants the arduino
toolchain sets `framework_variant: arduino` (see "Hardware modules" below). Board and variant stay
concrete.

## Substitution contract

`core.yaml` is the one documented place answering *"what must every firmware supply?"*. Every
parameter arrives as a YAML `substitutions:` value — **nothing is a C++ preprocessor define**, because
the build path injects no compiler flags. Substitution names are `lower_snake_case`.

**"Required" is scoped to the module that uses it.** Only `device_name`, `firmware_version` and
`sdk_ref` are required by `core.yaml` and therefore by every device. The only other required
substitution is `wifi_ap_password`, and only for a device that imports `wifi_ap.yaml`.
`criotive_mqtt.yaml`, `ciotcfg.yaml`, `wifi.yaml`, `ota.yaml` and `improv_serial.yaml` require
nothing. A module must not make another module's inputs globally mandatory — that would defeat
opt-in composition. A device compiles only the modules it imports.

| Substitution | Required | Default | Notes |
|---|---|---|---|
| `device_name` | **yes** | — | ESPHome node name; also the MQTT topic prefix |
| `firmware_version` | **yes** | — | published as a text sensor |
| `sdk_ref` | **yes** | — | must equal the package `ref`; CI-enforced |
| `wifi_ssid` | no | *(empty)* | *(`wifi.yaml`)* station slot 1 — see **Up to three WiFi networks** |
| `wifi_password` | no | *(empty)* | required once slot 1 has an SSID; **no usable default, ever** |
| `wifi_ssid_2` | no | *(empty)* | station slot 2 |
| `wifi_password_2` | no | *(empty)* | required once slot 2 has an SSID |
| `wifi_ssid_3` | no | *(empty)* | station slot 3 |
| `wifi_password_3` | no | *(empty)* | required once slot 3 has an SSID |
| `wifi_ap_password` | **yes**, with `wifi_ap.yaml` | — | *(`wifi_ap.yaml`)* fallback AP; **no default, ever** — see **Improv** |
| `wifi_reboot_timeout` | no | `0s` _(safety)_ | *(`wifi.yaml`, `wifi_ap.yaml`)* — `0s` **disables** the WiFi reboot (offline survival) |
| `mqtt_reboot_timeout` | no | `0s` _(safety)_ | `0s` **disables** the MQTT reboot (offline survival) |
| `mqtt_discovery` | no | `true` _(convenience)_ | Home Assistant discovery |
| `ota_password` | no | *(empty)* _(safety)_ | *(`ota.yaml`)* empty **removes** the native ESPHome OTA port; set it to open the port, password-protected — see **Updating over the air** |
| `ota_attempts` | no | `50` _(safety)_ | safe-mode boot attempts — larger recovery budget (ESPHome stock is `5`) |
| `ota_http_timeout` | no | `15s` _(convenience)_ | *(`ota.yaml`)* `http_request` timeout for the OTA download |
| `logger_level` | no | `NONE` _(safety)_ | logging is **off by default** — see below |
| `logger_baud_rate` | no | `0` _(safety)_ | `0` **disables** the serial console (skips UART init); `improv_serial.yaml` turns `0` into `115200` — see below |
| `diagnostics_update_interval` | no | `60s` _(convenience)_ | *(`diagnostics.yaml`)* cadence for debug sensors a device attaches to the `debug` component — see below |

Defaults are tagged **_(safety)_** or **_(convenience)_**. A **safety** default encodes a deliberate
protective posture — offline survival (`*_reboot_timeout: 0s`), production-quiet logging
(`logger_level: NONE`, `logger_baud_rate: 0`), a larger recovery budget (`ota_attempts`) — and should
not be overridden without a specific reason; the same holds for the hardware-file safety defaults
(`framework_variant: esp-idf` and `ota_rollback: true`, which ship OTA rollback protection, and
`can_resistor_status: ALWAYS_ON`). A **convenience** default is just a sensible starting value
(`mqtt_discovery`, `ota_http_timeout`) that a device overrides freely.

The serial console's **port** is not a substitution: `core.yaml` leaves `logger: hardware_uart:`
unset, so ESPHome picks the variant's own console, and a device that needs another one writes
`logger: hardware_uart: <port>` in its own config — see **The serial console**.

**No credential has a default, and no credential is a substitution at all.** A default password in a
public repo is a default password in every device that forgets to override it — and a *supplied*
password is a password compiled into an image that can then serve only the one device it was
compiled for. Neither problem exists now: the broker, its port, the credentials, the client id, the
topic prefix and the trust anchor all arrive at runtime from the `ciotcfg` partition. The one
credential that remains a substitution, `wifi_ap_password`, has no default, and the negative-fixture
harness proves it fails validation when omitted. `ota_password`'s empty default is not a default
password: an empty value removes the port it would protect.

### Up to three WiFi networks — and the provisioning-only mode

`wifi.yaml` configures **up to three** candidate station networks, in three slots:
`wifi_ssid`/`wifi_password`, `wifi_ssid_2`/`wifi_password_2`, `wifi_ssid_3`/`wifi_password_3`. A slot
is used only when its SSID is non-empty, so a single-network device fills slot 1 and ignores the
rest, and filling slots 1 and 3 yields a two-entry list with no gap.

```yaml
substitutions:
  wifi_ssid: site-main
  wifi_password: main-network-password
  wifi_ssid_2: site-backup          # optional; omit the pair entirely to leave the slot unused
  wifi_password_2: backup-network-password
```

**Order is not priority.** ESPHome scans and connects to the best network it can see among those
configured, so the slots are alternatives rather than a fallback chain. Three is a product choice,
not a platform limit — ESPHome's own cap is `MAX_WIFI_NETWORKS = 127`.

**A slot is all-or-nothing.** Every slot is optional and defaults to empty, which is *not* a
credential default: an empty SSID is unusable, and no password is usable without its SSID. But a
password set against an **empty SSID** is a hard `esphome config` failure, via the same `1/0` guard
idiom used for required substitutions. That keeps the likely misconfiguration — a forgotten or
mistyped SSID name — loud. The case it cannot catch is a typo in *both* names of a pair, which
leaves the slot silently unused.

**Leaving every slot empty is supported**, and is how a device ships when WiFi is provisioned in the
field — through Improv or the captive portal — rather than baked into the firmware. It then needs at
least one provisioning route (`improv_serial.yaml`, `improv_ble.yaml` or `wifi_ap.yaml`); with none,
ESPHome refuses the config (`Please specify at least an SSID or an Access Point to create.`). It is not simply "the same
config minus the credentials" — it changes where ESPHome keeps the credentials Improv or the
captive portal saves (`wifi_component.cpp:648`):

```cpp
uint32_t hash = this->has_sta() ? App.get_config_version_hash() : 88491487UL;
this->pref_ = global_preferences->make_preference<wifi::SavedWifiSettings>(hash, true);
```

`get_config_version_hash()` is an FNV-1a over the **entire rendered config dump**
(`core/__init__.py:706`). So:

- **With any slot filled**, captive-portal credentials are keyed to that exact config and are
  silently dropped by *any* change to it — a new entity, an ESPHome upgrade, or simply a
  `firmware_version` bump, which means **every OTA release**. The device then falls back to the
  configured slots. Fine when the slots are the real networks; surprising if someone re-provisioned
  a unit by hand and expected it to stick.
- **With no slot filled**, `has_sta()` is false at boot, the key is the constant `88491487UL`, and
  the saved credentials survive OTAs and config changes.

Either way the captive-portal network **replaces** the configured slots rather than joining them:
`WiFiComponent::start()` applies the saved credentials through `set_sta()`, which begins with
`clear_sta()` (`wifi_component.cpp:1003`).

### Improv — provisioning over the cable, and over BLE

Three optional modules provision Wi-Fi on a device that has none: `modules/improv_serial.yaml`
([Improv](https://www.improv-wifi.com/) over the USB cable), `modules/improv_ble.yaml` (Improv over
Bluetooth LE) and `modules/wifi_ap.yaml` (a fallback access point with a captive portal). They answer
different moments, and a device may import any combination — see
`tests/validate/improv_serial_and_ble.yaml`.

| | reaches the device | good for | grants whoever reaches it |
|---|---|---|---|
| `improv_serial` | the USB cable already attached | the flashing tool, the moment after it writes | Wi-Fi credentials |
| `improv_ble` | Bluetooth, no cable, no app | a board already inside an enclosure | Wi-Fi credentials |
| `wifi_ap` | its own fallback AP, from anything with Wi-Fi | the field, months later, no cable | Wi-Fi credentials **and a firmware upload** |

**The criotive platform's flashing tool provisions over `improv_serial`**, right after it writes the
image, which is why the recommended bundle imports it and nothing else.

**`wifi_ap.yaml` is opt-in, and its password is required with no default.** ESPHome's
`captive_portal` auto-loads `ota.web_server` (ESPHome 2026.9.1, `captive_portal/__init__.py`), so the
portal also serves `/update` with no authentication of its own. An open AP would let anyone in radio
range flash an offline device — and a replacement image can read the `ciotcfg` partition, which holds
the broker credentials. The password is compiled into the image, so every device built from one
config shares it: it is a fleet secret, kept out of any stored or shared config. That is a real cost,
and it is why the platform's flow does without the AP.
Improv only offers provisioning while the device has no network it can join, so on a device whose
station slots are filled it is inert rather than broken, and `esp32_improv` waits out ESPHome's
`wifi_timeout` (90s) before it starts advertising.

**`improv_serial` opens the serial console itself.** Improv talks over the logger's port, and
`core.yaml` defaults `logger_baud_rate` to `"0"`, which never opens it. Since `0` is the one rate
Improv cannot work with, importing `improv_serial.yaml` turns `0` into `115200` and leaves any non-zero
rate a device chose alone. Import it **after** `core.yaml`: a later package's `logger:` overrides an
earlier one, so listed first it is overridden back to `0` — ESPHome then refuses the config
(`improv_serial requires the logger baud_rate to be not 0`), loudly.

**The port is the variant's own console.** `core.yaml` leaves `logger: hardware_uart:` to ESPHome's
default — the native **USB-Serial/JTAG** port on an ESP32-S3, C3, C6 or H2, **USB-CDC** on an S2,
**UART0** on an ESP32. So on an ESP32-S3-DevKitC-1 Improv answers on the port labelled **USB** (the
native one), not on the **UART** port's USB-UART bridge. A board wired only through a bridge on UART0
— some C3 and S3 boards are — sets `logger: hardware_uart: UART0` in its own config. ESPHome rejects
`improv_serial` on an S3 whose console is `USB_CDC`.

**On `hds_v1_1`, the console and SW1 are the same pin.** Both own GPIO1, and this one fails
*silently*: the config validates, the board boots, and Improv never answers. Set
`hds_v1_1_sw1_enabled: false` on that board. `hds_v1_0` has no SW1 and needs nothing.
`tests/validate/improv_serial_hds_v1_1.yaml` is the fixture for exactly this trade.

**`improv_ble` pins `authorizer: none`**, so any phone in range may give Wi-Fi credentials to a
device that is not yet on a network — nothing more, unlike the fallback AP — and it is the only
setting that works for a board with no button exposed. A room that has a button and wants a physical press in the loop
overrides `esp32_improv:` in its own config with an `authorizer:` naming that binary sensor.

**BLE costs flash.** The stack is several hundred kilobytes on top of the image, and a project near
its app partition fails to *link* rather than fail to validate — `esphome config` cannot see it, so
the real compile in `release-gate.yml` is what proves it fits.

### A device never reboots through an outage — offline survival is an invariant

**A device MUST continue operating indefinitely while offline, without rebooting.** Field devices on
unreliable uplinks must ride out an outage rather than power-cycle through it. This is not a
preference; both reboot timeouts are pinned to `0s` for exactly this reason.

- `wifi_reboot_timeout` and `mqtt_reboot_timeout` both default to **`0s`**, which **disables** the
  respective connectivity reboot outright. Verified against ESPHome 2026.5.1 source — both components
  guard `App.reboot()` with `reboot_timeout_ != 0` (`wifi/wifi_component.cpp:867`,
  `mqtt/mqtt_client.cpp:418`), so `0s` makes the reboot branch unreachable. ESPHome's stock default
  is `15min` for both; leaving that in place would power-cycle a device every 15 minutes it is
  offline. Both stay overridable per device — only the default is pinned to `0s`.
- **No component may introduce a connectivity-driven reboot.** `ota.yaml`'s rollback watchdog is
  gated so it only ever affects a firmware image still pending verification right after an OTA — a
  confirmed image that is merely long-offline is never rolled back (see the OTA rollback section).
- **Regression guard.** `scripts/check-offline-survival.sh` (wired into `validate.yml`, with a
  self-test proving it fails on a known-bad `reboot_timeout: 15min`) fails the build if any
  `reboot_timeout` default under `modules/` or `hardware/` resolves to a non-zero value.

#### "Never auto-publish": use `update_interval: never`

A "never auto-publish" periodic sensor must **not** be expressed with a magic maximum-interval
number. ESPHome's `update_interval: never` literal says exactly that, far more clearly, and is used
at every such site here (`firmware_version`, `sensor_boots`, `ota_status`, `google_location`). Future
entities that should publish only on an explicit `publish_state()` must use `never`, not a numeric
sentinel.

### Logging is off in production by default

`logger_level` defaults to **`NONE`**: a device ships silent and its `logger:` emits nothing until a
consumer raises the level **deliberately**, per device — never on by default. A chatty default is not
free: it costs flash, CPU and (when a device also publishes logs) broker traffic on every unit that
forgot to turn it down.

To raise it, set the substitution per device to one of ESPHome's levels — `INFO`, `DEBUG`,
`VERBOSE` or `VERY_VERBOSE`:

```yaml
substitutions:
  logger_level: DEBUG   # opt in per device; production stays NONE
```

The knob is unchanged — only its default flipped from `INFO` back to `NONE`.

#### The serial console — `logger_baud_rate` and `logger: hardware_uart:`

`logger_level` gates which records are ever *produced*; `logger_baud_rate` gates whether a UART
*console* exists to print them on. They are **independent**, and the console is **off by default**:
`logger_baud_rate` defaults to **`0`**, which skips UART init entirely (ESPHome 2026.5.1 guards it
with `if (this->baud_rate_ > 0)` and `0` still validates, since the field is `positive_int`
= `int_range(min=0)`). So **raising serial logs takes both knobs** — a non-`NONE` `logger_level`
*and* a non-zero `logger_baud_rate`:

```yaml
substitutions:
  logger_level: INFO       # gate record production
  logger_baud_rate: "115200"  # AND open the UART console — both are required
```

The console's **port** is ESPHome's per-variant default: `core.yaml` sets no `hardware_uart`. On the
ESP32 boards in `hardware/` that is **`UART0`**, the only console they can actually use —
`UART1`/`UART2`'s default pins are wired to flash on these modules and the logger schema exposes no
`tx_pin` override. On an ESP32-S3 or C3 it is the native USB-Serial/JTAG port. A device that needs
another port says so in its own config, which merges over `core.yaml`'s `logger:`:

```yaml
logger:
  hardware_uart: UART0   # e.g. an S3 board reached only through its USB-UART bridge
```

**A serial console and a GPIO1 button are mutually
exclusive — a hardware constraint, not a configuration choice.** `UART0`'s TX is **GPIO1 (U0TXD)**,
the same pin `hds_v1_1`'s on-board **SW1** button uses. `UART1`/`UART2`'s default pins are wired to
flash on typical modules and the logger schema exposes no `tx_pin` override, so there is no way to
keep both. **Raising `logger_baud_rate` does NOT free GPIO1** — SW1 still owns the pin whenever the
SW1 `binary_sensor` exists, so the baud rate is *not* the SW1 opt-out. The opt-out is the
compile-time **`hds_v1_1_sw1_enabled`** flag: set it `false` (unquoted) to drop SW1, and a device that
needs serial logs also sets a real `logger_baud_rate` (see the [SW1 / GPIO1](#sw1--gpio1--gated-by-a-compile-time-flag)
section for the full table). `esphome config` cannot catch the pin overlap — it is a
physical-pin conflict the schema never sees — so it is stated here as a hardware fact.

### Required substitutions fail loudly — the guard idiom

Merely *referencing* `${x}` does **not** make a substitution required. ESPHome 2026.5.1 runs the
substitution pass non-strict (`components/substitutions/__init__.py`): an undefined `${x}` only logs
a **warning** and leaves the literal text in place, so `esphome config` still exits 0 unless the
leftover literal happens to break a field's schema. `device_name` is the lucky case — it lands in
`esphome: name:`, whose identifier schema rejects the `${device_name}` literal. Every other required
substitution lands in a free-form string field that accepts the literal, so each is wrapped in a
guard:

```yaml
password: "${ wifi_ap_password if wifi_ap_password is defined else 1/0 }"
```

When the value is present the expression returns it unchanged; when it is missing the
`ZeroDivisionError` is re-raised as a hard `cv.Invalid` (the non-strict pass demotes `UndefinedError`
to a warning but re-raises every *other* expression error), so `esphome config` exits non-zero with
the offending expression — which names the variable — in the message. **Any module that adds a
required substitution to a free-form field must apply this guard** (`wifi_ap.yaml` does so for
`wifi_ap_password`). `tests/negative/` proves each required input fails when
omitted, and `scripts/check-negative.sh` (wired into `validate.yml`) asserts every negative fixture
exits non-zero.

### The MQTT identity comes from the `ciotcfg` partition

An SDK device is told who it is at flash time, not at compile time. `modules/ciotcfg.yaml` registers
a 128 KB data partition called `ciotcfg` and reads a record out of it at `setup_priority::BUS` —
ahead of the MQTT client's own `AFTER_WIFI` setup — writing seven values into the client before it
connects: broker address, port, username, password, client id, topic prefix, and the CA certificate
that validates the broker.

**That is why `criotive_mqtt.yaml` takes no credentials and pins no host.** It declares `broker:
"0.0.0.0"` because ESPHome's schema requires the key, and nothing else. One compiled image can
therefore serve an entire fleet, and the same image can serve more than one environment: the host and
the anchor that validates it travel together in the record instead of being derived from a
compile-time switch.

**The anchor still moves with the host** — that requirement did not go away, it moved. A broker
address and a trust anchor are not independently valid: they are signed by different private CAs, so
pairing one deployment's host with another's certificate fails every handshake. What changed is where
the pairing is enforced. It used to be a `1/0` guard in this file; it is now the responsibility of
whatever writes the record, which is the only thing that knows which deployment a given device
belongs to.

**Port `8883` does not enable TLS, and neither does anything in this repository.**
`mqtt_backend_esp32` selects `MQTT_TRANSPORT_OVER_SSL` when `ca_certificate_` holds a value and
`MQTT_TRANSPORT_OVER_TCP` when it does not, at runtime. The certificate in the record is what
encrypts the transport. A record without a usable `ca` is refused outright rather than downgraded.

**Failure is closed, and loud.** A missing partition, an absent or corrupt record, a format version
this firmware does not understand, or any required field blank — each disables MQTT entirely and
marks the component failed. The client is never enabled, so it never dials the placeholder address:

```
[E][ciotcfg:091]: 'ciotcfg' carries no record; the device was flashed without its credentials
[E][ciotcfg:197]:   no usable identity; MQTT is disabled
```

**The client id is no longer a substitution.** It comes from the record, and it is deliberately kept
independent of the topic prefix — some brokers require `client_id == username` and reject a mismatch
at CONNACK, and some use the client id to namespace topics, so whoever writes the record decides both
rather than deriving one from the other. Note that `set_topic_prefix()` does not rewrite the birth,
will and shutdown topics: ESPHome derives those at code generation time, so the component sets all
three explicitly from the record's prefix. Without that, every device sharing an image would report
its availability on one topic.

**A device already in the field does not gain this over the air.** The partition table is written
only by the factory image, over serial; an OTA writes inside the app slot of the table already on the
chip. Migrating an existing device means a cable.

### MQTT log publishing is off by default

`criotive_mqtt.yaml` ships with MQTT log publishing off: **no device streams its logs to MQTT unless
a consumer opts in.**

This is not the same as omitting the key. ESPHome's `mqtt` component (`mqtt/__init__.py`,
`validate_config`) **re-injects** a default `${topic_prefix}/debug` log topic (with `retain: true`)
whenever a `topic_prefix` is set, so merely deleting `log_topic` would leave every device publishing
its logs. Disabling requires the key to be **present but empty** — `log_topic:` with a null value —
which drives the codegen branch `if not log_topic: disable_log_message()`. `esphome config` over
`tests/validate/mqtt_ota.yaml` proves it: the dumped `mqtt:` shows `log_topic: null` and no `/debug`
topic.

**Opting in (per device).** A consumer that wants a device's logs on the broker sets **two** things
in that device's config: its own `mqtt: log_topic:` block (which merges over the module's null) **and**
a non-`NONE` `logger_level`. Both are needed — the global `logger:` level gates which records are ever
produced, so a `log_topic` with `logger_level: NONE` (the default) publishes nothing and the topic
stays silent:

```yaml
substitutions:
  logger_level: INFO   # or DEBUG/VERBOSE/VERY_VERBOSE — REQUIRED, or nothing is published
mqtt:
  log_topic:
    topic: ${device_name}/debug
    qos: 0
    retain: false      # REQUIRED for a log topic — see below
```

`retain` **must be `false`** here. Retain is correct for birth / will / shutdown, where the retained
message is the device's *current* online state a new subscriber should see immediately. A log topic
is a rolling stream: each line overwrites the last, so a retained log topic makes the broker replay
one arbitrary, stale log line to every new subscriber — never what a log consumer wants.
`tests/validate/mqtt_log_optin.yaml` exercises this opt-in path.

### Updating over the air — the MQTT `ota` command

The platform updates a device by publishing one JSON message on its system `command` topic
(QoS 1); `criotive_mqtt.yaml` subscribes, and `ota.yaml`'s `script_ota_from_command` flashes:

```json
{"command": "ota",
 "url": "https://<platform>/api/ota/<version>/firmware.bin?ticket=<single-use ticket>",
 "md5": "<hex digest of the image>"}
```

- `command`, `url` and `md5` must all be strings, or the message is ignored — other system commands
  share the topic, and a partial `ota` payload is never half-acted on. Any other field (`deviceId`,
  `ticket`, `version`, ...) is tolerated and unused.
- The device fetches `url` **as given, with no HTTP Basic auth**. The ticket travels in the url's
  query string, and the platform answers with a redirect to blob storage: ESP-IDF 5.5.1 re-sends an
  `Authorization` header across that redirect and the storage service rejects any request carrying
  one, so credentials on the request would fail every update.
- **The url never reaches a log.** ESPHome 2026.9.1 prints a failing request's url under the
  `http_request` tag at ERROR and the OTA url under `http_request.ota` at INFO, and the platform
  ingests device logs. `ota.yaml` pins `logger: logs: http_request: NONE` and holds
  `http_request.ota` at `WARN` (or `logger_level`, when that is quieter). A device that raises one of
  these for debugging puts the ticket in its logs. `scripts/check-ota-url-only.sh` keeps both
  properties from regressing.
- Progress and the outcome go to the `ota_status` text sensor: `OTA start`, `OTA progress 42.0%`,
  `OTA end`, or `OTA update error <code>: <reason>`, where `<code>` is ESPHome's own and `<reason>`
  never contains the url — `18: download failed: no connection, HTTP error status or read error`
  covers a refused ticket and a broken link alike; `139: image does not match the md5` a corrupt or
  replaced image.

**`ota_password` — the native ESPHome OTA port.** `esphome run` and the dashboard upload over port
3232. Empty (the default), `ota.yaml` **removes** that platform rather than opening it without a
password: an unprotected port lets anyone on the LAN flash the device, and through the new image
read the `ciotcfg` partition. Set `ota_password` to keep the port for local development; like any
compiled-in secret, every device built from that config shares it.

The legacy download path — the `OTA HTTPS prod` text entity, `perform_ota_update` and the
`ota_http_server` / `ota_http_server_test` substitutions — is retired. The platform never commanded
it; the `ota` command above is the only remote update route.

### OTA rollback watchdog is offline-safe

`ota.yaml` arms a 300s post-boot rollback watchdog and `criotive_mqtt.yaml` cancels it once the
broker is reached — so a freshly-flashed image that cannot reach the broker rolls back to the last
known-good build. Audited against the offline-survival invariant: ESP-IDF's
`esp_ota_mark_app_invalid_rollback_and_reboot()` does **not** check the running image's OTA state, so
unguarded it would roll back even a **confirmed** image whenever a rollback target exists — rebooting
a healthy device that merely power-cycled during an outage and can't reach the broker within 300s.
The watchdog is therefore gated on `ESP_OTA_IMG_PENDING_VERIFY` (ESP-IDF's own idiom in
`esp_ota_begin`): only a freshly-flashed, not-yet-verified image can roll back; a confirmed,
long-offline image is never touched. OTA safety is preserved and offline survival is guaranteed.

That gate only holds if **nothing confirms the image before the broker does**. ESPHome's `safe_mode`
auto-confirms the running image on a timer — `esp_ota_mark_app_valid_cancel_rollback()` after
`boot_is_good_after`, whose stock default is `1min` — and on esp-idf (where the board files pin
`esp32: framework: advanced: enable_ota_rollback: true`, defining `USE_OTA_ROLLBACK`, so `esp32/hal.cpp`
guards its own immediate boot-time mark-valid with `#ifndef USE_OTA_ROLLBACK` and defers to safe_mode)
that timer is the only early confirmer. At the stock 1 minute the image would already be
`ESP_OTA_IMG_VALID` four minutes before the 300s watchdog fires, so its `PENDING_VERIFY` gate could
never trigger and a genuinely bad OTA would silently survive. `ota.yaml` therefore sets
`safe_mode: boot_is_good_after: 330s` — past the watchdog — so the **broker**, not a boot timer, owns
validity confirmation for the whole window. The trade-off is twofold. First, on esp-idf a
freshly-flashed image stays subject to bootloader rollback-on-reboot until it either reaches the
broker or survives 330s, slightly longer than ESPHome's default; an image that has already confirmed
(reached the broker once, or lived past 330s) is `ESP_OTA_IMG_VALID` and is never rolled back by this
mechanism. Second — and this affects **every** boot, not just a freshly-flashed one — `safe_mode`
clears its boot-loop counter inside the same `mark_successful()` that confirms the image, so raising
`boot_is_good_after` from ESPHome's stock `1min` to `330s` also delays that counter reset to 330s on
each boot. A device that power-cycles repeatedly within 330s of boot therefore accumulates those boots
toward safe mode even though it is otherwise healthy. The SDK's `num_attempts: 50` (ten times
ESPHome's stock `5`) absorbs this: fifty sub-330s power-cycles in a row would be required before
safe mode triggers, far beyond any normal power event. The `check-rollback-timing.sh` gate fails the
build if `boot_is_good_after` ever drops to or below the watchdog delay, so the confirmation ordering
can never silently regress.

## `${sdk_ref}` — pinning the components with the YAML

ESPHome treats `packages:` and `external_components:` as **independent** git sources: a module
fetched at `@<ref>` does *not* pass that ref to an `external_components:` block inside it. Left
implicit, a module's C++ component would follow the default branch while its YAML is pinned. The SDK
threads the ref through ESPHome's per-file `vars:` — the consumer passes `vars: {sdk_ref: <ref>}`
once and every module writes `ref: ${sdk_ref}`:

```yaml
external_components:
  - source:
      type: git
      url: https://github.com/junioteixeira/test-esphome-sdk
      ref: ${sdk_ref}
    components: [google_location]
```

Every module's `external_components` names this repository: a ref that exists only here — a release
tag cut here — cannot be resolved from any other.

CI (`scripts/check-sdk-ref.sh`) asserts every validate config's `vars.sdk_ref` equals its package
`ref`, and that no module hard-codes a ref.

## Automations use explicit list syntax

Package merging happens on **raw YAML, before** ESPHome normalizes a single-automation mapping into
a list. So every automation-shaped `on_*` key (`on_boot`, `on_shutdown`, `on_connect`, `on_value`,
…) must use the **sequence** form, or two modules' automations merge as dicts and silently collapse:

```yaml
# CORRECT — stacks into two automations, priorities preserved
esphome:
  on_boot:
    - priority: 600
      then: [...]
```

CI (`scripts/check-automation-syntax.sh`) enforces this across `modules/` and `hardware/`.

## Versioning

- Every generated config **pins an exact tag** (`@v0.1.0`), never a branch. A device never changes
  because the SDK moved; upgrading is an explicit platform action, and therefore also a migration
  point.
- **Semantic versioning over the substitution contract.** The SDK's public surface is the set of
  substitutions a config supplies: renaming or removing one — required *or* optional — is a
  breaking change plus a migration of stored configs. Removing an *optional* one is the worse case,
  because the value a stored config sets is not rejected, it is silently ignored and the device
  takes a different default.
- **Pre-1.0 the number answers one question:** *is it safe to re-pin?*

  | bump  | means                                                                   |
  |-------|-------------------------------------------------------------------------|
  | minor | **migration required** — a breaking change to the substitution contract  |
  | patch | **safe to re-pin** — features and fixes                                  |

- The first tag is **`v0.1.0`** — the module boundaries have not survived a real product yet.
- Versions are computed from [Conventional Commit](https://www.conventionalcommits.org/) subjects
  by [release-please](https://github.com/googleapis/release-please), which keeps a release PR open
  carrying the proposed version and the generated `CHANGELOG.md`; merging that PR is what publishes
  a tag. `scripts/check-contract-diff.sh` fails any PR whose substitution-contract change is
  breaking without a commit that declares it breaking, so the computed number cannot disagree with
  what actually changed. See [`AGENTS.md`](AGENTS.md) for the commit convention and release steps.
- **No secrets, ever.** Every credential arrives as a substitution; a value committed to a public
  repo is permanent and cannot be revoked by deletion.

## Repository layout

```
esphome-sdk/
  README.md                     # this file — substitution contract, scope, versioning
  AGENTS.md                     # commit convention, release process, gate index
  modules/                      # shared + optional-hardware modules
  hardware/                     # per-board files: hds_v1_0/1_1/2_0 (framework via ${framework_variant}),
                                #   hds_v1_1's SW1 flag, and each board's slot pin table
  components/                   # ESPHome custom components (C++)
  tests/validate/               # minimal configs exercised by CI (see tests/validate/README.md)
  tests/negative/               # configs that MUST fail (missing required substitutions)
  scripts/                      # CI gate scripts, each with a --self-test
  version.txt                   # current version, maintained by release-please
  CHANGELOG.md                  # generated by release-please
  release-please-config.json    # versioning policy (pre-1.0 bump mapping, changelog sections)
  .github/workflows/            # validate (PR), release-gate (main: compile then release), release (tag)
```

## Continuous integration

Every gate is a script under `scripts/` carrying a `--self-test` that proves its own FAIL paths;
CI runs the self-test before the real check, so a gate that has been defanged fails loudly instead
of passing silently.

- **`validate.yml`** — every pull request. Materializes the PR head SHA into each validate config's
  package `ref` and `vars.sdk_ref`, runs `esphome config` over `tests/validate/`, and runs the
  `check-automation-syntax.sh`, `check-button-platform.sh`, `check-sdk-ref.sh`,
  `check-negative.sh`, `check-offline-survival.sh`, `check-rollback-timing.sh`,
  `check-ota-url-only.sh` and `check-contract-diff.sh` gates. This validates the *revision under
  test*, never a published tag.
- **`release-gate.yml`** — every push to `main`. `compile` runs the real `esphome compile`, one
  parallel job per fixture (the list is discovered, not hardcoded, so a new fixture cannot escape
  the gate); `negative` runs the executable negative harness; `gates` re-runs every invariant script
  plus the contract gate against the last published tag. `release` (release-please, which maintains
  the release PR and creates the tag) **needs** all three. Merging the release PR is itself a push to `main`, so the commit that gets
  tagged is compiled first — if it does not build, no tag is ever created. This is the gate that can
  still **stop** a bad release, rather than merely report one.
- **`release.yml`** — a published tag, or `workflow_dispatch` with a tag input. Re-verifies a tag
  end-to-end. Belt-and-braces: by the time it runs the tag is already public and permanent, which is
  why the blocking compile lives in `release-gate.yml`.

CI validates against ESPHome **2026.5.1** (pinned in each workflow). This is the version the SDK is
checked and compiled against; it is not a claim about which ESPHome version any build service
installs.

## Modules

Each module group below owns a section here; later work appends to its own group without
restructuring the others.

### Shared modules

- `core.yaml` — substitution contract, `esphome:`, device identity, firmware_version, boot counter,
  `preferences`, `logger`, `time`/sntp. Mandatory for every device; imports nothing.
- `ciotcfg.yaml` — the `ciotcfg` partition and the component that writes the MQTT identity into the
  client before it connects. Needs `criotive_mqtt.yaml`.
- `wifi.yaml` — `wifi:` with up to three station slots, wifi_info text sensors, wifi signal sensor.
  No provisioning route of its own: with every slot empty, import `improv_serial.yaml`,
  `improv_ble.yaml` or `wifi_ap.yaml`.
- `wifi_ap.yaml` — the fallback access point (`criotive - <device_name>`), its captive portal and the
  AP-name lambda. Requires `wifi_ap_password`; see **Improv**.
- `criotive_mqtt.yaml` — mqtt client, birth / last-will / shutdown messages, `on_connect`, and the
  system `command` subscription that dispatches the `ota` command. Needs `ota.yaml` and
  `ciotcfg.yaml`.
- `ota.yaml` — `safe_mode`, the `http_request` OTA platform, the native ESPHome OTA platform only when
  `ota_password` is set, `ota_status`, `script_ota_from_command`, the rollback watchdog, and the log
  levels that keep the OTA url out of the logs. See **Updating over the air**. The rollback watchdog
  armed on boot here is cancelled by `criotive_mqtt.yaml`'s `on_connect` once the broker is reached.
- `improv_serial.yaml` — Improv over the serial console; opens the console at `115200` when
  `logger_baud_rate` is `0`. Import after `core.yaml`.
- `improv_ble.yaml` — Improv over Bluetooth LE (`esp32_improv`, `authorizer: none`).
- `diagnostics.yaml` — `debug` platform, device info, reset reason. Its `debug` component polls on
  `diagnostics_update_interval` (default `60s`). The interval is neither `0s` nor `never` on purpose:
  ESPHome coerces a 0 ms interval to **1 ms** (a 1 kHz wakeup on every device), while `never` would
  silence any numeric debug sensors — free heap, loop time, cpu frequency — that a **consuming**
  firmware attaches to this same component, since `DebugComponent::update()` is the only place those
  publish. The module's own two text sensors are unaffected either way: they publish from
  `dump_config()` at boot. A device with no debug sensors may set `never`.
- `controls.yaml` — shutdown / restart / safe-mode / factory-reset. Each is a visible
  `ack_button` whose `on_press:` waits 500ms and then presses an `internal: true` action
  platform. The split is what makes a remote press confirmable at all: the action platform
  reboots or wipes the device, and only the `ack_button` in front of it can publish that the
  press landed. The delay lets that publish reach the socket before the action kills the MQTT
  client. Declares `ack_button`'s `external_components` and an empty `safe_mode:` itself, so
  importing this module is enough; `ota.yaml`'s `safe_mode` settings win when both are imported.
- `location.yaml` — `google_location`, its `ack_button` Location Request, and the
  `external_components` for both. It retains ESPHome's full connection scan, accepts the platform's
  `{"command":"fetch_location"}` system command on `command`, and publishes the result on
  `<topic_prefix>/telemetry` as `location_parameters`. `location_system_command_topic` can override
  the bare command topic for a broker without a listener mountpoint.

### What each module publishes

ESPHome publishes an entity at `<topic_prefix>/<component>/<object_id>/state`. The **object_id is
the entity's `name:` in snake_case**: upper-case letters lowered, spaces turned into `_`, and every
character other than `a-z`, `0-9`, `-` and `_` replaced by `_` (ESPHome 2026.9.1,
`to_snake_case_char` / `to_sanitized_char` in `core/helpers.h`) — `"Chip Temp"` becomes `chip_temp`.
That object_id is the entity's wire name on the criotive platform. A `text_sensor` publishes under
the MQTT component `sensor`, not `text_sensor`. An `internal: true` entity publishes nothing.

| Module | `name:` | ESPHome domain (MQTT component) | object_id |
|---|---|---|---|
| `core.yaml` | Firmware Version | text_sensor (`sensor`) | `firmware_version` |
| `core.yaml` | Boots | sensor | `boots` |
| `wifi.yaml` | WiFi IP Address | text_sensor (`sensor`) | `wifi_ip_address` |
| `wifi.yaml` | WiFi Connected SSID | text_sensor (`sensor`) | `wifi_connected_ssid` |
| `wifi.yaml` | WiFi Connected BSSID | text_sensor (`sensor`) | `wifi_connected_bssid` |
| `wifi.yaml` | WiFi Mac Address | text_sensor (`sensor`) | `wifi_mac_address` |
| `wifi.yaml` | WiFi Signal Sensor | sensor | `wifi_signal_sensor` |
| `ota.yaml` | OTA status | text_sensor (`sensor`) | `ota_status` |
| `diagnostics.yaml` | Device Info | text_sensor (`sensor`) | `device_info` |
| `diagnostics.yaml` | Reset Reason | text_sensor (`sensor`) | `reset_reason` |
| `controls.yaml` | System Shutdown | button (`ack_button`) | `system_shutdown` |
| `controls.yaml` | System Restart | button (`ack_button`) | `system_restart` |
| `controls.yaml` | System Restart Safe Mode | button (`ack_button`) | `system_restart_safe_mode` |
| `controls.yaml` | System Factory Reset | button (`ack_button`) | `system_factory_reset` |
| `location.yaml` | Location Request | button (`ack_button`) | `location_request` |

`ciotcfg.yaml`, `wifi_ap.yaml`, `criotive_mqtt.yaml`, `improv_serial.yaml`, `improv_ble.yaml` and
the driver modules (`ack_button`, `linear_motor`, `medeawiz`, `phone`, `tca8418`) publish no entity
of their own. `location.yaml`'s `Google location` text sensor is internal; its result arrives as
`location_parameters` on `<topic_prefix>/telemetry`.

A device's own entity whose object_id equals one of these collides with it. Wi-Fi signal and boot
count are already published — a device does not need its own.

### Optional entity modules

Not drivers for hardware, but entity platforms that change how an entity behaves on the wire. Like
the hardware modules they declare only their `external_components` source, pinned to `${sdk_ref}`;
the entities themselves stay in the device's own config.

- **`ack_button.yaml` — a button that acknowledges its press on the state topic.** A stock ESPHome
  button is write-only: `mqtt_button.cpp` sets `SendDiscoveryConfig::state_topic = false` and the
  component never publishes, because Home Assistant models a button as a trigger with no state. The
  criotive platform disagrees — it binds a discovered component to its `state_topic` and confirms a
  command by reading telemetry back from it, so an awaited press on a stock button can only ever
  time out. **Import it when** the platform (or any consumer) needs to know a button press
  landed. Then declare buttons with `platform: ack_button` instead of `platform: template`:

  ```yaml
  button:
    - platform: ack_button
      name: "Abrir Solenoide"
      on_press:
        - then:
            - switch.turn_on: solenoide
  ```

  It is the stock button in every other respect. The schema, entity registration and the
  `button.press:` action all come from `esphome.components.button` unmodified, so every option a
  button accepts — `icon`, `device_class`, `entity_category`, `internal`, `disabled_by_default`,
  `qos`, `retain`, `availability`, `state_topic`, `command_topic` — works here too, and an ESPHome
  release that adds one adds it here on the same day. The only override is the MQTT companion class,
  swapped through the `mqtt_id` the button schema already declares.

  Four behaviours are worth knowing:

  - **Every press acknowledges**, not only one arriving on the command topic. A physical input
    firing `button.press:` and an automation pressing it publish the same `PRESS`, the way a switch
    publishes its state whatever moved it.
  - **The ack is published before the `on_press:` automations run**, because it happens in
    `press_action()` and `Button::press()` calls that first. An automation that blocks — or never
    returns — therefore cannot leave a press unacknowledged. This is ordering, not delivery:
    `publish()` queues the message and the client still has to reach the socket, so an automation
    that reboots or cuts power in the same loop iteration can still cut it off in flight. For those,
    keep the `- delay: 500ms` idiom `controls.yaml` uses in front of every shutdown and restart.
  - **The ack is not retained**, unlike every other MQTT entity's state. A press is an event, and a
    retained `PRESS` would be redelivered to every future subscriber, so each reconnect would read
    as a fresh press. An explicit `retain: true` still wins if a device wants the old behaviour.
  - **A config whose ack lands on its own subscription is rejected**, because MQTT has no no-local
    option: the broker would echo each ack back as a new press and the button would run forever.
    The defaults can never collide, so this only bites a device that overrides the topics — and it
    catches wildcards, not just equal strings, since `command_topic` is a subscription filter and
    `.../+` swallows an ack as surely as `.../state` does. Lambda topics are resolved on device and
    cannot be checked here.

  With no `mqtt:` in the config there is no companion and this is an ordinary button,
  indistinguishable from `platform: template`.

- **`linear_motor.yaml` — a DC linear actuator on an H-bridge, as a `switch`.** Open-loop: ON drives
  out, OFF drives back, each for its own time, then both outputs are driven together and it holds.
  **Import it when** a room moves a drawer, hatch or slot with the H Bridge module.

  ```yaml
  switch:
    - platform: linear_motor
      name: "Motor Linear da gaveta"
      id: motor_linear
      pin_a: ${slot_2_h_bridge_out_1}
      pin_b: ${slot_2_h_bridge_out_2}
      travel_time: 10s      # retract_time overrides it for the return stroke
  ```

  Three behaviours are worth knowing:

  - **Every command drives**, not only a change of state, so a reset can retract an actuator it
    already believes retracted. The repeat publishes nothing, because `Switch::publish_state`
    deduplicates — a re-drive is invisible to the platform.
  - **Reversing cancels the previous stroke's end-of-travel**, which would otherwise brake in the
    middle of the new movement.
  - **`restore_mode` defaults to `ALWAYS_OFF`**, so boot drives to the retracted end. Open-loop that
    is the only way to reach a known position.

  Use `linear_motor.is_moving` to hold a room reset open until the stroke has finished:

  ```yaml
  - wait_until:
      condition:
        not:
          linear_motor.is_moving: motor_linear
      timeout: 15s
  ```

  Not ESPHome's `hbridge` switch, which rests both outputs LOW, no-ops a repeated command and is
  `final`; nor a `time_based` cover, which the criotive platform maps to an opaque Object variable
  instead of a bindable `switch`.

  **The SDK holds itself to this.** `check-button-platform.sh` fails the build if any button in
  `modules/` or `hardware/` is visible to the platform — that is, not `internal: true` — and is not
  an `ack_button`. `controls.yaml` is the shape to copy: a visible `ack_button` in front of an
  `internal: true` action platform. The rule is not a ban on the `button:` key, because
  `platform: shutdown` / `restart` / `safe_mode` / `factory_reset` genuinely perform the reboot and
  the wipe that `ack_button` cannot; `internal: true` is what makes them invisible to the platform,
  and therefore exempt from having to answer it.

### Optional hardware modules

A device imports one of these **only if it has that hardware** — they are drivers, not business
logic, and are not replaceable by standard switches. Each module declares **only** its own
`external_components` source (pinned to `${sdk_ref}`); it does **not** instantiate the component,
because the instance is inherently device-specific (I2C address, UART bus, which pins, key layout).
A device imports the module to make the driver available and then declares the instance in its own
private config. Each has a validate fixture under `tests/validate/` that instantiates it, so release
CI compiles the C++ at least once per release.

- **`tca8418.yaml` — TCA8418 I2C GPIO expander.** `TCA8418Component` extends
  `gpio_expander::CachedGpioExpander<uint32_t, 32>` and registers `TCA8418GPIOPin` as a real
  `GPIOPin`, adding 18 pins (ROW0–ROW7, COL0–COL9) over I2C that any component can use as a pin
  source — a `binary_sensor`/`switch` on `platform: gpio`, etc. A general capability, unrelated to
  ESPHome's native `matrix_keypad`/`key_collector` (those *scan* a keypad matrix; this *provides*
  pins). **Import it when** a board runs short on native GPIO. The
  component AUTO_LOADs `gpio_expander` and DEPENDS on `i2c`, so the device must also declare an
  `i2c:` bus. Instantiate `tca8418:` with the board's address, then reference a pin as
  `pin: {tca8418: <id>, number: 0-17, mode: {...}}`.
- **`medeawiz.yaml` — MedeaWiz Sprite 4K serial video-player driver.** Controls a Sprite (DV-S4)
  over its TTL serial port with a bespoke single-byte protocol (play file N, seek, volume,
  request position/duration, end-of-file feedback); no ESPHome-native equivalent exists. **Import
  it when** the device drives a MedeaWiz Sprite. DEPENDS on `uart`, so the device must declare a
  `uart:` bus **with a tx pin** (the Sprite receives commands on tx). Instantiate `medeawiz:` on
  that bus and use its actions (`medeawiz.play_file`, `medeawiz.seek`, …) and triggers
  (`on_file`, `on_end_of_file`).
- **`phone.yaml` — matrix-keypad "phone" keypad driver.** Scans a keypad matrix (or individual column
  buttons when no rows are given), debounces presses, tracks on/off-hook from an optional
  `binary_sensor`, and matches typed sequences against configured passwords, firing right/wrong
  triggers. No ESPHome-native component does this. **Import it when** the device drives a keypad
  "phone" device. Instantiate `phone:` with the concrete `rows`/`columns` pins (plain `GPIOPin`s — so
  they may be native GPIO **or** a `tca8418` expander pin), the `keys` layout (length must equal
  rows × columns), and any hook sensor / passwords / automations the device needs.

  **A password may be templatable.** `password:` accepts a lambda as well as a literal, and it is
  resolved on every submission — so `password: !lambda "return id(my_text).state;"` lets an operator
  change the code from a `text:` entity without a reflash, while a literal still compiles to a
  constant. A prop whose codes are configured from the platform wants the lambda form.

  **`phone.submit` / `phone.clear` drive it from outside the matrix.** `enter_keys` and `clear_keys`
  can only name keys on the phone's own matrix, so a prop whose enter button is a separate GPIO — or
  whose reset is driven by an automation — has no key to name. The two actions submit and clear the
  accumulated input directly; `phone.submit` ignores empty input, exactly as the enter key does.

  **`sequence_timeout: 0s` disables the timeout.** The default is `3s`, after which a part-typed
  sequence is validated and cleared on its own. A prop whose enter button drives `phone.submit`
  wants that off, or a player typing a long code slowly has it submitted out from under them
  mid-entry. `0s` means the input stands until it is submitted or cleared explicitly.

  **`max_length` bounds the input.** The default `0` is unlimited, which is fine for a keypad
  whose codes end at an enter key pressed promptly, and wrong for one left in a public room:
  without a cap the accumulated string grows for as long as someone keeps pressing and is
  republished on every press. Set it to the longest password and further keys are ignored
  rather than truncated, so overshooting by one does not turn an already-complete code into a
  failed one.

  **Prefer `on_no_match` to a per-password `on_password_wrong`.** The per-entry trigger fires once
  for **every** entry the input did not match, so with N passwords configured a single wrong code
  fires it N times — right when the passwords are independent locks, wrong when they are
  alternatives (one keypad, one code per colour). The component-level `on_no_match` fires exactly
  once per submission that matched nothing, which is what a single wrong-code effect should hang on.

### Hardware modules

A hardware module owns the platform component (`esp32:`) and the board's own I/O. Board and variant
are **concrete** — never a `${...}` board/variant substitution. The build **framework** is the one
esp32 field that varies per device, so it is the `framework_variant` substitution consumed inside the
board file's own `esp32.framework.type` (default `esp-idf`, declared in `core.yaml`). A device imports
exactly one hardware module. The ESP32-only scope excludes the `mr60bha2dev`, `r`, `esp12` and
`nodemcu32` boards.

| Module | board | variant | framework | board revision |
|---|---|---|---|---|
| `hds_v1_0.yaml` | `pico32` | `esp32` | `${framework_variant}` (default esp-idf) | v1.0 |
| `hds_v1_1.yaml` | `esp32dev` | `esp32` | `${framework_variant}` (default esp-idf) | v1.1 |

- `hds_v1_0.yaml` — CAN termination resistor on GPIO12.
- `hds_v1_1.yaml` — the CAN termination resistor on GPIO12, and the on-board SW1 button on GPIO1
  gated by the compile-time `hds_v1_1_sw1_enabled` flag (default `true`; see "SW1 / GPIO1" below).

**CAN termination — `can_resistor_status`.** `hds_v1_0` and `hds_v1_1` carry the CAN bus
termination resistor and own an optional `can_resistor_status` substitution (default `ALWAYS_ON`)
that sets its restore mode. Only the two endpoint nodes of a CAN segment should terminate; a node
wired mid-bus **must** override `can_resistor_status: ALWAYS_OFF`, or two terminators become three
and the bus is corrupted. The two v1 validate fixtures exercise both values — `hds_v1_0` at the
`ALWAYS_ON` default and `hds_v1_1` overriding to `ALWAYS_OFF`.

**OTA visual feedback / LED ownership.** If a hardware file has indicator LEDs it owns its own OTA
visual feedback and drives those LED ids itself — no module reaches into a hardware id. None of
these boards has indicator LEDs, so none ships OTA LED feedback and `ota.yaml` keeps no reference to
any hardware id.

#### Framework selection — `framework_variant`

Board and variant are concrete, but the build **framework** is a per-device choice, so it is a single
`framework_variant` substitution consumed inside the board file's own `esp32.framework.type` rather
than a doubled `_idf` board file. `core.yaml` declares the DEFAULT (`framework_variant: esp-idf`); a
device overrides it per device with `framework_variant: arduino`. One board file therefore serves both
frameworks, and the board/variant/framework stay a single logical block in one place. The valid tokens
are `esp-idf` and `arduino`; substitution is textual and runs before schema validation, so the
resolved literal is what the esp32 schema checks — the same mechanism `can_resistor_status` already
uses.

**The default is `esp-idf`.** Earlier revisions of these board files defaulted to arduino; a device
that relied on that must now set `framework_variant: arduino` explicitly. The framework choice has one
behavioural consequence in the shared modules: `ota.yaml`'s post-boot **rollback watchdog and
`criotive_mqtt.yaml`'s MQTT confirmation are both compiled inside `#ifdef USE_ESP_IDF`**. So on an
**arduino** build they are compiled out entirely and the build carries no post-OTA rollback
protection; on an **esp-idf** build they are active and guard a freshly-flashed image (see the OTA
rollback section). Because the default is esp-idf, a default build ships that protection; a device
that opts into arduino gives it up.

The rollback SUPPORT flag itself — `esp32: framework: advanced: enable_ota_rollback` — is NOT
esp-idf-only, however. ESPHome 2026.5.1 emits its `USE_OTA_ROLLBACK` define and
`CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE` sdkconfig option for **both** frameworks (the
`enable_ota_rollback` branch in `components/esp32/__init__.py`'s `to_code` runs unconditionally, not
under the esp-idf-only branch). `USE_OTA_ROLLBACK` makes `esp32/hal.cpp` defer boot-time image
confirmation to `safe_mode` and arms bootloader rollback. If it were left on for arduino — where the
watchdog and the broker's confirmation are compiled out — a healthy freshly-flashed image that
power-cycled within `boot_is_good_after` would be rolled back by the bootloader with nothing able to
confirm it early. So the board files drive `enable_ota_rollback` from the **`ota_rollback`
substitution** (default `true`), and an **arduino device must pair `framework_variant: arduino` with
`ota_rollback: false`** — leaving `USE_OTA_ROLLBACK` undefined so `hal.cpp` confirms at boot and no
rollback machinery is compiled at all. Rollback protection therefore lives only on esp-idf, as stated.
The `framework_variant: arduino` validate fixture exercises exactly that pairing, and the default
(esp-idf) fixtures cover the rollback path; release CI compiles each for real.

#### SW1 / GPIO1 — gated by a compile-time flag

The v1.1 board has an on-board push button, **SW1**, on **GPIO1** — which is the ESP32's **U0TXD**
(primary UART TX). Configuring SW1 as a GPIO input takes GPIO1 away from the UART, so **the serial
console goes silent** on that board. Raising `logger_baud_rate` does **not** change that — SW1 owns
GPIO1 for as long as its `binary_sensor` exists, so the baud rate is not the opt-out. Because the
trade-off must be a deliberate choice, SW1 is wired in the board file behind a single flag,
**`hds_v1_1_sw1_enabled`** (default `true`), so the board stays **one YAML file** — the product
requirement is exactly one file per hardware.

The flag works through ESPHome's `!remove`: SW1 is declared with a stable `id: sw1_button`, and a
second `binary_sensor` item carries
`id: !remove '${"sw1_button" if hds_v1_1_sw1_enabled | string | lower in ["false", "0", ""] else false}'`.
The substitution pass expands substitutions inside a `!remove` value and evaluates the expression, so
a falsy flag makes the target resolve to `sw1_button` and SW1 (with its `on_click`) is dropped;
anything else resolves to the string `false`, which matches no id and is a no-op, so SW1 stays.

The comparison is against the **falsy spellings** rather than a truthiness test, because a
consumer's substitutions are frequently strings and a non-empty string is truthy. ESPHome's own
`-s key value` always yields a string, so a truthiness test made the flag impossible to set from the
command line — `-s hds_v1_1_sw1_enabled false` left SW1 enabled with no error. A YAML boolean
`false`, the string `"false"` (any case), `"0"` and `""` all disable SW1 now. It is a flag rather than a commented-out block because the SDK is consumed as a **remote git
package** — a device cannot edit or comment `hds_v1_1.yaml` at all, but it can set a substitution in
its own config.

Pick **one** in the device's own config:

| Goal | `hds_v1_1_sw1_enabled` | `logger_baud_rate` | `controls.yaml` |
|---|---|---|---|
| **normal device** | `true` (default) | `0` (default — console off) | required |
| **reading serial logs** | `false` (or `"false"` / `"0"` / `""`) | a real rate, e.g. `115200` | not needed |

- In the **normal** row SW1 works and the console is off, because GPIO1 (U0TXD) is taken by the
  button. `controls.yaml` is required because SW1's `on_click` presses `button_restart` on a short
  click and `button_factory` on longer holds, both owned by `controls.yaml` by id.
- In the **reading serial logs** row SW1 is removed, GPIO1 stays on the UART and the console prints.
  A device sets `hds_v1_1_sw1_enabled: false` **plus** a real `logger_baud_rate`.

Both rows are covered by validate fixtures: `hds_v1_1_sw1.yaml` (enabled, the default) and
`hds_v1_1_sw1_disabled.yaml` (disabled, console on, and no `controls.yaml`).

One footgun to know:

- **A mistyped flag name (or id) is a silent no-op** — the `!remove` matches nothing and SW1 stays
  enabled, with no error. Check the generated config if you expected the console back and it is still
  silent.

It is a **compile-time** choice: switching sides changes which firmware is built, so it needs a
**rebuild**, not live pin multiplexing. Do **not** work around the conflict by relocating SW1 to a
spare pin — a floating input can spuriously fire, and SW1's handlers press restart / factory-reset.
See the "serial console" note under
[Logging](#logging-is-off-in-production-by-default).

#### Slot pin tables — `slot_<n>_<module>_<signal>`

Each board file also carries a static table of **slot pin substitutions**. A board has a set of
numbered module slots; a pluggable module wired into a slot exposes named signals; and each
`slot_<n>_<module>_<signal>` substitution resolves that signal, for that module in that slot, to the
physical GPIO it lands on. Names are `lower_snake_case`. For example, a Double Relay wired into slot 3
uses `${slot_3_double_relay_relay_1}` for relay 1's pin; an Audio module's RX in slot 7 uses
`${slot_7_audio_rx}`. Only combinations that physically fit a board are listed, and each board's table
is board-specific — the same module in the same slot resolves to different pins on different boards.

The values are **static data**, transcribed from the board's slot/module definitions and cross-checked
against them; there is no generator, codegen step or regeneration procedure in this repository. Which
slot actually holds which module is the **consumer's** responsibility: the SDK never sees a device's
populated slot map, so it **cannot** validate that `slot_3_double_relay_*` is used on a board whose
slot 3 really holds a Double Relay. A tool that consumes an explicit populated slot map could enforce
that pairing; this SDK does not, so it becomes authoring discipline. `esphome config` still catches a
**mistyped** name (its `${...}` stays a literal
and fails the pin schema), which the `slot_pins_*` validate fixtures exercise — one substitution per
module type per board — but it cannot catch a *wrong-but-valid* slot choice.
