#include "../common/sha256.hpp"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

namespace fs = std::filesystem;

int main(int argc, char** argv) {
    fs::path mod_dir = ".";
    std::string nickname = "CalradianHero";
    std::string server_addr = "127.0.0.1:7240";
    int max_players = 8;
    int friendly_fire_pct = 0;
    std::string speed_policy = "min_online";
    bool write_cfg_only = false;

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--mod-dir" && i + 1 < argc) mod_dir = argv[++i];
        else if (arg == "--nick" && i + 1 < argc) nickname = argv[++i];
        else if (arg == "--connect" && i + 1 < argc) server_addr = argv[++i];
        else if (arg == "--max-players" && i + 1 < argc) max_players = std::stoi(argv[++i]);
        else if (arg == "--ff-pct" && i + 1 < argc) friendly_fire_pct = std::stoi(argv[++i]);
        else if (arg == "--speed-policy" && i + 1 < argc) speed_policy = argv[++i];
        else if (arg == "--init-profile") write_cfg_only = true;
    }

    fs::create_directories(mod_dir);
    auto id = calradia::crypto::load_or_create_identity_file((mod_dir / "identity.key").string());

    fs::path cfg_path = mod_dir / "launcher_config.json";
    {
        std::ofstream ofs(cfg_path, std::ios::binary | std::ios::trunc);
        auto esc = [](const std::string& s) {
            std::string o;
            for (char c : s) {
                if (c == '\\' || c == '"') { o += '\\'; o += c; }
                else if (c == '\n' || c == '\r') o += ' ';
                else o += c;
            }
            return o;
        };
        ofs << "{\n"
            << "  \"player_uid\": \"" << id.player_uid << "\",\n"
            << "  \"nickname\": \"" << esc(nickname) << "\",\n"
            << "  \"last_server\": \"" << esc(server_addr) << "\",\n"
            << "  \"host_max_players\": " << max_players << ",\n"
            << "  \"friendly_fire_pct\": " << friendly_fire_pct << ",\n"
            << "  \"speed_policy\": \"" << speed_policy << "\"\n"
            << "}\n";
    }

    std::cout << "[CalradiaLauncher] Profile ready: " << nickname
              << " (" << id.player_uid << ") -> " << server_addr << "\n";
    if (write_cfg_only) {
        return 0;
    }
    return 0;
}
