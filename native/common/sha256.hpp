#pragma once
#include <array>
#include <cstddef>
#include <cstdint>
#include <string>

namespace calradia::crypto {

struct IdentityProfile {
    std::string secret_hex;
    std::string player_uid;
    std::string auth_key_hex;
    std::string public_token_hex;
};

std::array<uint8_t, 32> sha256_bytes(const void* data, std::size_t len);
std::string sha256_hex(const std::string& data);
std::string sha256_file_hex(const std::string& path);
std::string hmac_sha256_hex(const std::string& key_raw, const std::string& message);

IdentityProfile derive_identity_from_secret(const std::string& secret_hex);
IdentityProfile load_or_create_identity_file(const std::string& key_path);
std::string sign_challenge_response(
    const IdentityProfile& id,
    const std::string& server_nonce,
    const std::string& nickname);

} // namespace calradia::crypto
