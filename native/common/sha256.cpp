#include "sha256.hpp"

#include <cstring>
#include <fstream>
#include <iomanip>
#include <random>
#include <sstream>
#include <stdexcept>
#include <vector>

namespace calradia::crypto {

namespace {

constexpr uint32_t K[64] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
    0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u, 0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
    0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu, 0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
    0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u, 0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
    0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u, 0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
    0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u, 0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
    0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u, 0x90befffaU, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u
};

inline uint32_t rotr(uint32_t x, uint32_t n) {
    return (x >> n) | (x << (32u - n));
}

std::string bytes_to_hex(const uint8_t* buf, std::size_t n) {
    std::ostringstream oss;
    oss << std::hex << std::setfill('0');
    for (std::size_t i = 0; i < n; ++i) {
        oss << std::setw(2) << static_cast<unsigned>(buf[i]);
    }
    return oss.str();
}

} // namespace

std::array<uint8_t, 32> sha256_bytes(const void* data, std::size_t len) {
    uint32_t h[8] = {
        0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
        0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u
    };

    const auto* src = static_cast<const uint8_t*>(data);
    uint64_t bit_len = static_cast<uint64_t>(len) * 8ull;
    std::size_t rem = (len + 9u) % 64u;
    std::size_t pad_zeros = (rem == 0u) ? 0u : (64u - rem);
    std::vector<uint8_t> msg(len + 1u + pad_zeros + 8u, 0u);
    if (len > 0) {
        std::memcpy(msg.data(), src, len);
    }
    msg[len] = 0x80u;
    for (int i = 0; i < 8; ++i) {
        msg[msg.size() - 1 - i] = static_cast<uint8_t>((bit_len >> (i * 8)) & 0xffu);
    }

    uint32_t w[64];
    for (std::size_t offset = 0; offset < msg.size(); offset += 64u) {
        for (int i = 0; i < 16; ++i) {
            std::size_t j = offset + static_cast<std::size_t>(i) * 4u;
            w[i] = (static_cast<uint32_t>(msg[j]) << 24) |
                   (static_cast<uint32_t>(msg[j + 1]) << 16) |
                   (static_cast<uint32_t>(msg[j + 2]) << 8) |
                   static_cast<uint32_t>(msg[j + 3]);
        }
        for (int i = 16; i < 64; ++i) {
            uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
            uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16] + s0 + w[i - 7] + s1;
        }

        uint32_t a = h[0], b = h[1], c = h[2], d = h[3];
        uint32_t e = h[4], f = h[5], g = h[6], hh = h[7];

        for (int i = 0; i < 64; ++i) {
            uint32_t S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
            uint32_t ch = (e & f) ^ ((~e) & g);
            uint32_t temp1 = hh + S1 + ch + K[i] + w[i];
            uint32_t S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
            uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
            uint32_t temp2 = S0 + maj;

            hh = g;
            g = f;
            f = e;
            e = d + temp1;
            d = c;
            c = b;
            b = a;
            a = temp1 + temp2;
        }

        h[0] += a; h[1] += b; h[2] += c; h[3] += d;
        h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
    }

    std::array<uint8_t, 32> out{};
    for (int i = 0; i < 8; ++i) {
        out[static_cast<std::size_t>(i) * 4 + 0] = static_cast<uint8_t>((h[i] >> 24) & 0xffu);
        out[static_cast<std::size_t>(i) * 4 + 1] = static_cast<uint8_t>((h[i] >> 16) & 0xffu);
        out[static_cast<std::size_t>(i) * 4 + 2] = static_cast<uint8_t>((h[i] >> 8) & 0xffu);
        out[static_cast<std::size_t>(i) * 4 + 3] = static_cast<uint8_t>(h[i] & 0xffu);
    }
    return out;
}

std::string sha256_hex(const std::string& data) {
    auto digest = sha256_bytes(data.data(), data.size());
    return bytes_to_hex(digest.data(), digest.size());
}

std::string sha256_file_hex(const std::string& path) {
    std::ifstream ifs(path, std::ios::binary);
    if (!ifs) {
        throw std::runtime_error("Cannot open file for hashing: " + path);
    }
    std::ostringstream ss;
    ss << ifs.rdbuf();
    return sha256_hex(ss.str());
}

std::string hmac_sha256_hex(const std::string& key_raw, const std::string& message) {
    std::array<uint8_t, 64> k_block{};
    if (key_raw.size() > 64u) {
        auto kh = sha256_bytes(key_raw.data(), key_raw.size());
        std::memcpy(k_block.data(), kh.data(), kh.size());
    } else if (!key_raw.empty()) {
        std::memcpy(k_block.data(), key_raw.data(), key_raw.size());
    }

    std::array<uint8_t, 64> o_key_pad{};
    std::array<uint8_t, 64> i_key_pad{};
    for (std::size_t i = 0; i < 64u; ++i) {
        o_key_pad[i] = k_block[i] ^ 0x5cu;
        i_key_pad[i] = k_block[i] ^ 0x36u;
    }

    std::string inner_input(reinterpret_cast<const char*>(i_key_pad.data()), 64u);
    inner_input.append(message);
    auto inner_digest = sha256_bytes(inner_input.data(), inner_input.size());

    std::string outer_input(reinterpret_cast<const char*>(o_key_pad.data()), 64u);
    outer_input.append(reinterpret_cast<const char*>(inner_digest.data()), 32u);
    auto outer_digest = sha256_bytes(outer_input.data(), outer_input.size());
    return bytes_to_hex(outer_digest.data(), outer_digest.size());
}

// Matches lua/auth.lua 100% bit-for-bit!
IdentityProfile derive_identity_from_secret(const std::string& secret_hex) {
    IdentityProfile id;
    id.secret_hex = secret_hex;
    id.player_uid = "p_" + sha256_hex("calradia_uid_v1:" + secret_hex).substr(0, 24);
    id.auth_key_hex = sha256_hex("calradia_auth_key_v1:" + secret_hex);
    id.public_token_hex = id.auth_key_hex;
    return id;
}

IdentityProfile load_or_create_identity_file(const std::string& key_path) {
    {
        std::ifstream ifs(key_path);
        if (ifs) {
            std::string line;
            while (std::getline(ifs, line)) {
                auto pos = line.find("secret_hex=");
                if (pos == 0) {
                    std::string sec = line.substr(11);
                    while (!sec.empty() && (sec.back() == '\r' || sec.back() == '\n' || sec.back() == ' ')) {
                        sec.pop_back();
                    }
                    if (sec.size() >= 32) {
                        return derive_identity_from_secret(sec);
                    }
                }
            }
        }
    }

    std::random_device rd;
    uint8_t entropy[32];
    for (std::size_t i = 0; i < sizeof(entropy); i += 4) {
        uint32_t v = rd();
        entropy[i + 0] = static_cast<uint8_t>((v >> 24) & 0xffu);
        entropy[i + 1] = static_cast<uint8_t>((v >> 16) & 0xffu);
        entropy[i + 2] = static_cast<uint8_t>((v >> 8) & 0xffu);
        entropy[i + 3] = static_cast<uint8_t>(v & 0xffu);
    }
    std::string secret_hex = bytes_to_hex(entropy, sizeof(entropy));
    auto profile = derive_identity_from_secret(secret_hex);

    std::ofstream ofs(key_path, std::ios::binary | std::ios::trunc);
    if (!ofs) {
        throw std::runtime_error("Failed to write identity key: " + key_path);
    }
    ofs << "# Calradia Online Persistent Player Cryptographic Key (KEEP SECRET - BACK UP WITH SAVES)\n";
    ofs << "player_uid=" << profile.player_uid << "\n";
    ofs << "public_token=" << profile.public_token_hex << "\n";
    ofs << "secret_hex=" << profile.secret_hex << "\n";
    return profile;
}

std::string sign_challenge_response(
    const IdentityProfile& id,
    const std::string& server_nonce,
    const std::string& /*nickname*/) {
    std::string msg = server_nonce + ":" + id.player_uid;
    return hmac_sha256_hex(id.auth_key_hex, msg);
}

} // namespace calradia::crypto
