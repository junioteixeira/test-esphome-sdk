"""The SDK's own boot actions, under a key that a device's config does not write.

`sdk_boot:` takes the same automations as `esphome: on_boot:` and runs them the same way — each is
ESPHome's own `StartupTrigger`, a component whose `setup()` fires the automation at its priority —
so moving an action here changes nothing about when or how it runs.

What changes is who owns the key. `esphome:` belongs to the device's config, which is merged over
the SDK's packages, and ESPHome's `merge_config` (ESPHome 2026.9.1, `config_helpers.py`) returns the
newer value outright when the two sides are not both mappings or both lists. A config that writes
its own `on_boot` as a single mapping therefore REPLACES every module's `on_boot` list instead of
adding to it, with no warning, and the SDK's boot actions never run. Nothing outside the SDK writes
`sdk_boot:`, so a module's actions here survive whatever a config puts under `esphome:`.

Modules write it in the list form, like every other automation: two modules each writing a mapping
here would replace each other in exactly the same way.
"""

import esphome.automation as automation
import esphome.codegen as cg
import esphome.config_validation as cv
from esphome.const import CONF_PRIORITY, CONF_TRIGGER_ID

CODEOWNERS = ["Junio Teixeira"]
MULTI_CONF = True

StartupTrigger = cg.esphome_ns.class_(
    "StartupTrigger", cg.Component, automation.Trigger.template()
)

CONFIG_SCHEMA = automation.validate_automation(
    {
        cv.GenerateID(CONF_TRIGGER_ID): cv.declare_id(StartupTrigger),
        cv.Optional(CONF_PRIORITY, default=600.0): cv.float_,
    },
    single=True,
)


async def to_code(config):
    trigger = cg.new_Pvariable(config[CONF_TRIGGER_ID], config[CONF_PRIORITY])
    await cg.register_component(trigger, config)
    await automation.build_automation(trigger, [], config)
