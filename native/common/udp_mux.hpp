#pragma once
#include <cstddef>
#include <cstdint>
#include <optional>
#include <vector>

namespace calradia::net {

constexpr uint8_t MUX_MAGIC_0 = 0x43; // 'C'
constexpr uint8_t MUX_MAGIC_1 = 0x4F; // 'O'
constexpr uint8_t MUX_VERSION = 0x01;
constexpr std::size_t MUX_HEADER_BYTES = 8;

enum class MuxChannel : uint8_t {
    Campaign       = 0,
    BattleSlot0    = 1,
    BattleSlotMax  = 8,
    ControlSwitch  = 254,
    PingInfo       = 255,
};

struct MuxFrame {
    bool had_mux_header = false;
    uint8_t channel = 0;
    uint32_t session_id = 0;
    std::vector<uint8_t> payload;
};

// Encode raw UDP payload with 8-byte CoopUdpMux header ("CO" + ver=1 + channel + session_id_be32)
std::vector<uint8_t> encode_mux_frame(
    uint8_t channel,
    uint32_t session_id,
    const uint8_t* payload,
    std::size_t payload_len);

// Decode incoming UDP datagram: if prefixed with "CO\x01", strips 8-byte header and returns channel;
// otherwise falls back seamlessly to Campaign channel 0 (allowing unproxied Direct-IP clients to connect too!).
MuxFrame decode_mux_frame(const uint8_t* datagram, std::size_t len);

// Map logical mux channel -> internal loopback backend port (base_port+1 for Campaign, base_port+2+2*(ch-1) for Battle)
uint16_t channel_to_backend_port(uint16_t public_port, uint8_t channel);

} // namespace calradia::net
