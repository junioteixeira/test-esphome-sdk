#pragma once

#include "esphome/core/defines.h"

#ifdef USE_ESP32

#include "esphome/core/component.h"

#include <cstddef>
#include <cstdint>
#include <string>

namespace esphome::ciotcfg {

/// Wire format of the record, mirrored by DemoFirmwareConfigBlob.cs on the platform side. The two
/// are one format described in two languages: a change to either needs a FORMAT_VERSION bump in
/// both, and a device rejects a record whose version is newer than this.
///
/// 0x00  4  magic "CIOT"
/// 0x04  2  format version
/// 0x06  2  reserved (0)
/// 0x08  4  payload length
/// 0x0C  4  CRC-32 (ISO-HDLC) of the payload
/// 0x10  n  UTF-8 JSON payload
static constexpr size_t HEADER_SIZE = 16;
static constexpr uint16_t FORMAT_VERSION = 1;

/// Reads the per-device MQTT identity out of the `ciotcfg` partition and writes it into the MQTT
/// client before it connects.
///
/// Fail-closed: importing this component means the identity comes from flash, so an absent, corrupt
/// or incomplete record disables MQTT rather than letting the compiled placeholders reach a broker.
class CiotCfg : public Component {
 public:
  void setup() override;
  void dump_config() override;

  /// BUS (1.0) rather than the default, because MQTT sets up at AFTER_WIFI (-1.0) and ESPHome runs
  /// higher priorities first. Every value this writes must already be in place by then.
  float get_setup_priority() const override { return setup_priority::BUS; }

 protected:
  bool load_();
  bool apply_(const uint8_t *payload, size_t length);

  std::string client_id_;
  std::string host_;
  uint16_t port_{0};
};

}  // namespace esphome::ciotcfg

#endif  // USE_ESP32
