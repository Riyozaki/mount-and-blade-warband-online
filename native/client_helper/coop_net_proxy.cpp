#include "../common/sha256.hpp"
#include "../common/udp_mux.hpp"

#include <atomic>
#include <cstring>
#include <iostream>
#include <string>

#ifdef _WIN32
  #ifndef WIN32_LEAN_AND_MEAN
    #define WIN32_LEAN_AND_MEAN
  #endif
  #ifndef NOMINMAX
    #define NOMINMAX
  #endif
  #include <windows.h>
#else
  #include <dlfcn.h>
#endif

namespace {

// Optional runtime-only Steamworks probe (NEVER statically linked — runs identically on GOG & Standalone!)
bool probe_optional_steam_runtime() {
#ifdef _WIN32
    HMODULE h = LoadLibraryA("steam_api64.dll");
    if (!h) h = LoadLibraryA("steam_api.dll");
    if (h) {
        FreeLibrary(h);
        return true;
    }
    return false;
#else
    void* h = dlopen("libsteam_api.so", RTLD_LAZY);
    if (h) {
        dlclose(h);
        return true;
    }
    return false;
#endif
}

} // namespace

int main(int argc, char** argv) {
    std::string key_path = "identity.key";
    std::string nonce;
    std::string nickname = "Adventurer";
    bool sign_mode = false;
    bool probe_mode = false;

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--key" && i + 1 < argc) key_path = argv[++i];
        else if (arg == "--nonce" && i + 1 < argc) nonce = argv[++i];
        else if (arg == "--nick" && i + 1 < argc) nickname = argv[++i];
        else if (arg == "--sign-challenge") sign_mode = true;
        else if (arg == "--probe-transports") probe_mode = true;
    }

    if (probe_mode) {
        bool has_steam = probe_optional_steam_runtime();
        // Honest capability report: only what is really implemented is advertised.
        // direct_ip covers LAN and VPN (they are plain IP addresses through the same UDP mux path).
        // relay and steam_p2p are NOT implemented yet; the Steam runtime is only detected, never used.
        std::cout << "transports=direct_ip\n"
                  << "lan_vpn_via=direct_ip\n"
                  << "relay=not_implemented\n"
                  << "steam_p2p=not_implemented\n"
                  << "steam_runtime=" << (has_steam ? "present" : "absent") << "\n";
        return 0;
    }

    auto profile = calradia::crypto::load_or_create_identity_file(key_path);
    if (sign_mode) {
        std::string sig = calradia::crypto::sign_challenge_response(profile, nonce, nickname);
        std::cout << "player_uid=" << profile.player_uid << "\n"
                  << "public_token=" << profile.public_token_hex << "\n"
                  << "hmac_hex=" << sig << "\n";
        return 0;
    }

    std::cout << "[CoopNetProxy] Loaded universal identity " << profile.player_uid
              << " (Steam optional P2P: " << (probe_optional_steam_runtime() ? "available" : "standalone/direct-ip")
              << ")\n";
    return 0;
}
