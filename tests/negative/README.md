# Negative fixtures — configs that MUST fail `esphome config`

Each file here breaks **exactly one** rule the SDK enforces at config time, and therefore must make
`esphome config` exit non-zero. `scripts/check-negative.sh` runs `esphome config` over every file
here and fails if any one succeeds; it is wired into `validate.yml`.

Two kinds of rule live here:

- **The substitution contract** — `omit_*.yaml` omits a required substitution, `orphan_wifi_*.yaml`
  half-fills a WiFi station slot. These are the proof the contract is enforced: if one were to
  *succeed*, a required input silently gained a default — exactly the "public default password in
  every device" failure the contract forbids. `check-contract-diff.sh --negative-parity` holds this
  set in step with the required substitutions derived from `modules/`, so it looks at `omit_*.yaml`
  and nothing else.
- **Component invariants** — a rule a component enforces in its own `CONFIG_SCHEMA`, which has no
  substitution to omit. `ack_button_shared_topic.yaml` and `ack_button_wildcard_topic.yaml` are the
  first: an `ack_button` whose acknowledgement would land back on its own subscription must not
  validate. These are named after the component and the invariant, never `omit_*`, so the parity
  gate keeps ignoring them. They source the component through a **local** `external_components`
  path and write the rest of the device out in full, importing no module: `modules/ack_button.yaml`
  fetches the component over git, and so does `core.yaml` (for `sdk_boot`) — a fixture that failed
  on an unreachable ref would pass this suite while proving nothing.

Unlike the positive fixtures in `tests/validate/`, these import the modules with a **local
`!include`** (`../../modules/*.yaml`) rather than the GitHub `packages:` path. That keeps them
hermetic — they exercise the contract with no network fetch and no `__SDK_REF__` materialization, so
they run identically locally and in CI (`check-sdk-ref.sh` does not scan this directory).

The `local-test` ref they pass exists on no remote, so a fixture must fail **before** ESPHome loads
`external_components` — at substitution time, through the guard idiom — or it fails on the fetch
instead of on its rule. `check-negative.sh` reports any fixture that started a git clone as a
failure of the suite, not a pass.

Every fixture except `omit_sdk_ref.yaml` threads `vars: {sdk_ref: local-test}` into the includes,
because `sdk_ref` is itself a required substitution (guarded in `core.yaml`): without it, *every*
fixture would fail on the missing `sdk_ref` instead of on the one input it is meant to test.
`omit_sdk_ref.yaml` is the fixture that deliberately withholds it from `core.yaml`.

Coverage: omitting `device_name`, `firmware_version` or `sdk_ref` (core.yaml), or
`wifi_ap_password` (wifi_ap.yaml — the fallback AP is opt-in, and once imported its password has no
default).

The `orphan_wifi_password*.yaml` pair covers the WiFi station slots instead. The slots themselves are
optional — a device may legitimately fill one, three or none of them — so there is no "omitted
`wifi_ssid`" failure to test; what the contract enforces is that a slot is **all-or-nothing**. Each
fixture sets a slot's password with no SSID (slot 1 in one, slot 2 in the other) and must fail. That
is the guard against a forgotten or mistyped SSID name quietly turning a configured network into no
network at all.

`criotive_mqtt.yaml` and `ota.yaml` require nothing: the MQTT identity comes from the `ciotcfg`
partition, and `ota_password` is optional — left empty, it removes the native OTA port rather than
opening it.
