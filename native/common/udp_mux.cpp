#include "udp_mux.hpp"

#include <cstring>

namespace calradia::net {

std::vector<uint8_t> encode_mux_frame(
    uint8_t channel,
    uint32_t session_id,
    const uint8_t* payload,
    std::size_t payload_len) {
    std::vector<uint8_t> out(MUX_HEADER_BYTES + payload_len);
    out[0] = MUX_MAGIC_0;
    out[1] = MUX_MAGIC_1;
    out[2] = MUX_VERSION;
    out[3] = channel;
    out[4] = static_cast<uint8_t>((session_id >> 24) & 0xffu);
    out[5] = static_cast<uint8_t>((session_id >> 16) & 0xffu);
    out[6] = static_cast<uint8_t>((session_id >> 8) & 0xffu);
    out[7] = static_cast<uint8_t>(session_id & 0xffu);
    if (payload_len > 0 && payload != nullptr) {
        std::memcpy(out.data() + MUX_HEADER_BYTES, payload, payload_len);
    }
    return out;
}

MuxFrame decode_mux_frame(const uint8_t* datagram, std::size_t len) {
    MuxFrame frame;
    if (len >= MUX_HEADER_BYTES &&
        datagram[0] == MUX_MAGIC_0 &&
        datagram[1] == MUX_MAGIC_1 &&
        datagram[2] == MUX_VERSION) {
        frame.had_mux_header = true;
        frame.channel = datagram[3];
        frame.session_id =
            (static_cast<uint32_t>(datagram[4]) << 24) |
            (static_cast<uint32_t>(datagram[5]) << 16) |
            (static_cast<uint32_t>(datagram[6]) << 8) |
            static_cast<uint32_t>(datagram[7]);
        frame.payload.assign(datagram + MUX_HEADER_BYTES, datagram + len);
        return frame;
    }

    // Legacy / raw Warband packet fallback -> Campaign channel 0
    frame.had_mux_header = false;
    frame.channel = 0;
    frame.session_id = 0;
    if (len > 0 && datagram != nullptr) {
        frame.payload.assign(datagram, datagram + len);
    }
    return frame;
}

uint16_t channel_to_backend_port(uint16_t public_port, uint8_t channel) {
    if (channel == 0) {
        return static_cast<uint16_t>(public_port + 1u);
    }
    if (channel >= 1 && channel <= 8) {
        return static_cast<uint16_t>(public_port + 2u + 2u * static_cast<uint16_t>(channel - 1u));
    }
    return public_port;
}

} // namespace calradia::net
