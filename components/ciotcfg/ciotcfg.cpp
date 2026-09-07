#include "ciotcfg.h"

#ifdef USE_ESP32

#include "esphome/components/json/json_util.h"
#include "esphome/components/mqtt/mqtt_client.h"
#include "esphome/core/log.h"

#include <esp_err.h>
#include <esp_partition.h>

#include <cinttypes>
#include <cstring>
#include <memory>

namespace esphome::ciotcfg {

static const char *const TAG = "ciotcfg";

static const char PARTITION_LABEL[] = "ciotcfg";
static const esp_partition_subtype_t PARTITION_SUBTYPE = static_cast<esp_partition_subtype_t>(0x40);

static const uint8_t MAGIC[] = {'C', 'I', 'O', 'T'};

/// CRC-32/ISO-HDLC, spelled out rather than delegated to esp_crc32_le: the ROM helper's seed and
/// final-XOR convention is easy to get subtly wrong, and a CRC that disagrees with the platform
/// rejects every record we ship. Pinned to the canonical check value 0xCBF43926 for "123456789".
static uint32_t crc32(const uint8_t *data, size_t length) {
  uint32_t crc = 0xFFFFFFFFu;
  for (size_t i = 0; i < length; i++) {
    crc ^= data[i];
    for (int bit = 0; bit < 8; bit++) {
      const uint32_t mask = -(crc & 1u);
      crc = (crc >> 1) ^ (0xEDB88320u & mask);
    }
  }

  return ~crc;
}

/// Reads a required non-empty string; returns nullptr and logs when absent or blank.
static const char *required_string(JsonObject root, const char *key) {
  if (!root[key].is<const char *>()) {
    ESP_LOGE(TAG, "record has no '%s'", key);
    return nullptr;
  }

  const char *value = root[key].as<const char *>();
  if (value == nullptr || value[0] == '\0') {
    ESP_LOGE(TAG, "record has an empty '%s'", key);
    return nullptr;
  }

  return value;
}

void CiotCfg::setup() {
  if (this->load_()) {
    ESP_LOGI(TAG, "identity loaded: '%s' -> %s:%u", this->client_id_.c_str(), this->host_.c_str(), this->port_);
    return;
  }

  // Fail closed. Importing this component means the identity comes from flash, so the compiled
  // substitutions are not a fallback -- they are whatever happened to be in the YAML, and letting
  // them reach a broker is worse than staying silent. set_enable_on_boot is what stops it: MQTT
  // sets up at AFTER_WIFI, after this, and reads the flag there.
  if (mqtt::global_mqtt_client != nullptr) {
    mqtt::global_mqtt_client->set_enable_on_boot(false);
  }

  this->mark_failed();
}

bool CiotCfg::load_() {
  const esp_partition_t *partition =
      esp_partition_find_first(ESP_PARTITION_TYPE_DATA, PARTITION_SUBTYPE, PARTITION_LABEL);
  if (partition == nullptr) {
    ESP_LOGE(TAG, "no '%s' partition in the table", PARTITION_LABEL);
    return false;
  }

  uint8_t header[HEADER_SIZE];
  esp_err_t err = esp_partition_read(partition, 0, header, sizeof(header));
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "could not read '%s': %s", PARTITION_LABEL, esp_err_to_name(err));
    return false;
  }

  if (memcmp(header, MAGIC, sizeof(MAGIC)) != 0) {
    // Erased flash reads as 0xFF: the device was flashed without a record.
    ESP_LOGE(TAG, "'%s' carries no record; the device was flashed without its credentials", PARTITION_LABEL);
    return false;
  }

  uint16_t version;
  uint32_t payload_length;
  uint32_t expected_crc;
  memcpy(&version, header + 4, sizeof(version));
  memcpy(&payload_length, header + 8, sizeof(payload_length));
  memcpy(&expected_crc, header + 12, sizeof(expected_crc));

  if (version > FORMAT_VERSION) {
    ESP_LOGE(TAG, "record format v%u is newer than this firmware understands (v%u)", version, FORMAT_VERSION);
    return false;
  }

  if (payload_length == 0 || payload_length > partition->size - HEADER_SIZE) {
    ESP_LOGE(TAG, "record declares an impossible payload length (%" PRIu32 " bytes)", payload_length);
    return false;
  }

  // Only the declared payload is pulled into RAM; the partition itself is far larger.
  std::unique_ptr<uint8_t[]> payload(new uint8_t[payload_length]);
  err = esp_partition_read(partition, HEADER_SIZE, payload.get(), payload_length);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "could not read the record payload: %s", esp_err_to_name(err));
    return false;
  }

  const uint32_t actual_crc = crc32(payload.get(), payload_length);
  if (actual_crc != expected_crc) {
    ESP_LOGE(TAG, "record CRC mismatch (stored %08" PRIx32 ", computed %08" PRIx32 ")", expected_crc, actual_crc);
    return false;
  }

  return this->apply_(payload.get(), payload_length);
}

bool CiotCfg::apply_(const uint8_t *payload, size_t length) {
  auto *client = mqtt::global_mqtt_client;
  if (client == nullptr) {
    ESP_LOGE(TAG, "no MQTT client to configure");
    return false;
  }

  const bool ok = json::parse_json(payload, length, [&](JsonObject root) -> bool {
    const int port = root["port"].as<int>();
    if (port <= 0 || port > 65535) {
      ESP_LOGE(TAG, "record has no usable 'port'");
      return false;
    }

    const char *host = required_string(root, "host");
    const char *username = required_string(root, "username");
    const char *password = required_string(root, "password");
    const char *client_id = required_string(root, "clientId");
    const char *topic_prefix = required_string(root, "topicPrefix");
    const char *ca = required_string(root, "ca");
    if (host == nullptr || username == nullptr || password == nullptr || client_id == nullptr ||
        topic_prefix == nullptr || ca == nullptr) {
      return false;
    }

    client->set_broker_address(host);
    client->set_broker_port(static_cast<uint16_t>(port));
    client->set_username(username);
    client->set_password(password);
    client->set_client_id(client_id);

    // TLS is selected at runtime from whether a CA is present: mqtt_backend_esp32 picks
    // MQTT_TRANSPORT_OVER_SSL only when ca_certificate_ holds a value and MQTT_TRANSPORT_OVER_TCP
    // otherwise. This call is therefore what encrypts the transport; the port number alone does
    // nothing. The backend copies into its own std::string, so this buffer may be freed after it.
    client->set_ca_certificate(ca);

    // The second argument is check_topic_prefix: set_topic_prefix substitutes App.get_name() for
    // the prefix when the two are EQUAL and name_add_mac_suffix is on. An empty string cannot equal
    // a prefix just proven non-empty, so this always takes the value verbatim.
    client->set_topic_prefix(topic_prefix, "");

    // set_topic_prefix does not reach these. ESPHome derives the availability topics from the
    // prefix in Python, at codegen time, so they still carry the device_name the image was compiled
    // with, and a fleet sharing one image would report every device's availability on the same
    // topic, each one overwriting the last.
    const std::string status_topic = std::string(topic_prefix) + "/status";
    client->set_birth_message(mqtt::MQTTMessage{status_topic, "online", 0, true});
    client->set_last_will(mqtt::MQTTMessage{status_topic, "offline", 0, true});
    client->set_shutdown_message(mqtt::MQTTMessage{status_topic, "offline", 0, true});

    this->client_id_ = client_id;
    this->host_ = host;
    this->port_ = static_cast<uint16_t>(port);
    return true;
  });

  if (!ok) {
    ESP_LOGE(TAG, "record payload is not a usable configuration");
    return false;
  }

  return true;
}

void CiotCfg::dump_config() {
  ESP_LOGCONFIG(TAG, "ciotcfg:");
  if (this->is_failed()) {
    ESP_LOGE(TAG, "  no usable identity; MQTT is disabled");
    return;
  }

  ESP_LOGCONFIG(TAG, "  Client ID: %s", this->client_id_.c_str());
  ESP_LOGCONFIG(TAG, "  Broker: %s:%u", this->host_.c_str(), this->port_);
}

}  // namespace esphome::ciotcfg

#endif  // USE_ESP32
