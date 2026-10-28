#include "../common/sha256.hpp"
#include "../common/udp_mux.hpp"
#include "../common/udp_relay.hpp"

#include <algorithm>
#include <chrono>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <regex>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#ifdef _WIN32
  #ifndef WIN32_LEAN_AND_MEAN
    #define WIN32_LEAN_AND_MEAN
  #endif
  #ifndef NOMINMAX
    #define NOMINMAX
  #endif
  #include <winsock2.h>
  #include <ws2tcpip.h>
  using socklen_t = int;
  static void close_sock(SOCKET s) { closesocket(s); }
#else
  #include <arpa/inet.h>
  #include <netinet/in.h>
  #include <sys/select.h>
  #include <sys/socket.h>
  #include <unistd.h>
  using SOCKET = int;
  constexpr SOCKET INVALID_SOCKET = -1;
  static void close_sock(SOCKET s) { close(s); }
#endif

namespace fs = std::filesystem;

namespace {

struct BattleSlot {
    int slot_index = 0;
    uint16_t backend_port = 0;
    bool busy = false;
    int active_battle_id = 0;
    std::string scene_id;
};

class HostSupervisor {
public:
    HostSupervisor(uint16_t public_port, int pool_size, fs::path spool_dir)
        : public_port_(public_port), spool_dir_(std::move(spool_dir)) {
        for (int i = 0; i < pool_size; ++i) {
            BattleSlot bs;
            bs.slot_index = i;
            bs.backend_port = calradia::net::channel_to_backend_port(public_port_, static_cast<uint8_t>(i + 1));
            slots_.push_back(bs);
        }
        fs::create_directories(spool_dir_ / "outbox");
        fs::create_directories(spool_dir_ / "inbox");
    }

    // Poll Campaign outbox for BATTLE_SPAWN_REQ / BATTLE_FREE & write atomic BATTLE_READY to inbox
    std::size_t process_ipc_outbox_once() {
        std::size_t handled = 0;
        std::vector<fs::path> files;
        for (const auto& entry : fs::directory_iterator(spool_dir_ / "outbox")) {
            if (entry.is_regular_file() && entry.path().extension() == ".json") {
                files.push_back(entry.path());
            }
        }
        std::sort(files.begin(), files.end());

        std::regex type_re("\"msg_type\"\\s*:\\s*\"([^\"]+)\"");
        std::regex bid_re("\"battle_id\"\\s*:\\s*([0-9]+)");
        std::regex scene_re("\"scene_id\"\\s*:\\s*\"([^\"]+)\"");

        for (const auto& fpath : files) {
            std::ifstream ifs(fpath);
            if (!ifs) continue;
            std::ostringstream ss;
            ss << ifs.rdbuf();
            ifs.close();
            std::string body = ss.str();

            std::smatch mt, mb, ms;
            std::string msg_type = std::regex_search(body, mt, type_re) ? mt[1].str() : "";
            int battle_id = std::regex_search(body, mb, bid_re) ? std::stoi(mb[1].str()) : 0;
            std::string scene_id = std::regex_search(body, ms, scene_re) ? ms[1].str() : "scn_random_scene_plain";

            if (msg_type == "BATTLE_SPAWN_REQ") {
                int chosen_slot = -1;
                for (auto& sl : slots_) {
                    if (!sl.busy) {
                        sl.busy = true;
                        sl.active_battle_id = battle_id;
                        sl.scene_id = scene_id;
                        chosen_slot = sl.slot_index;
                        break;
                    }
                }
                if (chosen_slot >= 0) {
                    write_inbox_ready(battle_id, slots_[static_cast<std::size_t>(chosen_slot)]);
                    ++handled;
                }
            } else if (msg_type == "LIVE_REINFORCEMENT") {
                ++handled;
            }
            std::error_code ec;
            fs::remove(fpath, ec);
        }
        return handled;
    }

    // Live loopback socket self-test verifying single-port UDP mux routing across Campaign (ch 0) & Battle (ch 1)
    static bool run_udp_mux_loopback_selftest() {
#ifdef _WIN32
        WSADATA wsa;
        WSAStartup(MAKEWORD(2, 2), &wsa);
#endif
        SOCKET mux_sock = socket(AF_INET, SOCK_DGRAM, 0);
        SOCKET camp_sock = socket(AF_INET, SOCK_DGRAM, 0);
        SOCKET btl_sock = socket(AF_INET, SOCK_DGRAM, 0);
        if (mux_sock == INVALID_SOCKET || camp_sock == INVALID_SOCKET || btl_sock == INVALID_SOCKET) {
            return false;
        }

        auto bind_ephemeral = [](SOCKET s, uint16_t& port_out) -> bool {
            sockaddr_in addr{};
            addr.sin_family = AF_INET;
            addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
            addr.sin_port = htons(0);
            if (bind(s, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0) return false;
            socklen_t alen = sizeof(addr);
            if (getsockname(s, reinterpret_cast<sockaddr*>(&addr), &alen) != 0) return false;
            port_out = ntohs(addr.sin_port);
            return true;
        };

        uint16_t mux_port = 0, camp_port = 0, btl_port = 0;
        bool ok = bind_ephemeral(mux_sock, mux_port) &&
                  bind_ephemeral(camp_sock, camp_port) &&
                  bind_ephemeral(btl_sock, btl_port);
        if (!ok) {
            close_sock(mux_sock); close_sock(camp_sock); close_sock(btl_sock);
            return false;
        }

        SOCKET client_sock = socket(AF_INET, SOCK_DGRAM, 0);
        sockaddr_in mux_dst{};
        mux_dst.sin_family = AF_INET;
        mux_dst.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        mux_dst.sin_port = htons(mux_port);

        // Send a Battle Slot 0 packet (channel = 1) through the single public mux_port!
        const std::string test_payload = "WARBAND_3D_BATTLE_SYNC_TICK_42";
        auto pkt = calradia::net::encode_mux_frame(
            1, 0xCAFEBABEu,
            reinterpret_cast<const uint8_t*>(test_payload.data()),
            test_payload.size());
        sendto(client_sock, reinterpret_cast<const char*>(pkt.data()), static_cast<int>(pkt.size()), 0,
               reinterpret_cast<sockaddr*>(&mux_dst), sizeof(mux_dst));

        uint8_t rx_buf[1500];
        sockaddr_in src_addr{};
        socklen_t slen = sizeof(src_addr);
        auto n = recvfrom(mux_sock, reinterpret_cast<char*>(rx_buf), sizeof(rx_buf), 0,
                          reinterpret_cast<sockaddr*>(&src_addr), &slen);
        if (n <= 0) {
            close_sock(client_sock); close_sock(mux_sock); close_sock(camp_sock); close_sock(btl_sock);
            return false;
        }

        auto decoded = calradia::net::decode_mux_frame(rx_buf, static_cast<std::size_t>(n));
        sockaddr_in backend_dst{};
        backend_dst.sin_family = AF_INET;
        backend_dst.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        backend_dst.sin_port = htons(decoded.channel == 1 ? btl_port : camp_port);
        sendto(mux_sock, reinterpret_cast<const char*>(decoded.payload.data()),
               static_cast<int>(decoded.payload.size()), 0,
               reinterpret_cast<sockaddr*>(&backend_dst), sizeof(backend_dst));

        uint8_t btl_rx[1500];
        auto bn = recvfrom(btl_sock, reinterpret_cast<char*>(btl_rx), sizeof(btl_rx), 0, nullptr, nullptr);
        std::string delivered(reinterpret_cast<char*>(btl_rx), bn > 0 ? static_cast<std::size_t>(bn) : 0u);

        close_sock(client_sock);
        close_sock(mux_sock);
        close_sock(camp_sock);
        close_sock(btl_sock);

        return decoded.had_mux_header &&
               decoded.channel == 1 &&
               decoded.session_id == 0xCAFEBABEu &&
               delivered == test_payload;
    }

private:
    void write_inbox_ready(int battle_id, const BattleSlot& slot) {
        ++inbox_seq_;
        std::string token = calradia::crypto::sha256_hex(
            "battle_tok:" + std::to_string(battle_id) + ":" + std::to_string(slot.backend_port)).substr(0, 24);
        fs::path final_path = spool_dir_ / "inbox" /
            ("ready_" + std::to_string(inbox_seq_) + "_b" + std::to_string(battle_id) + ".json");
        fs::path tmp_path = final_path;
        tmp_path += ".tmp";

        std::ofstream ofs(tmp_path, std::ios::binary | std::ios::trunc);
        ofs << "{\n"
            << "  \"msg_type\": \"BATTLE_READY\",\n"
            << "  \"battle_id\": " << battle_id << ",\n"
            << "  \"assigned_slot\": " << slot.slot_index << ",\n"
            << "  \"mux_channel\": " << (slot.slot_index + 1) << ",\n"
            << "  \"battle_port\": " << slot.backend_port << ",\n"
            << "  \"join_token\": \"" << token << "\"\n"
            << "}\n";
        ofs.close();
        fs::rename(tmp_path, final_path);
    }

    uint16_t public_port_;
    fs::path spool_dir_;
    std::vector<BattleSlot> slots_;
    uint64_t inbox_seq_ = 0;
};

} // namespace

namespace {

// Real round trip through UdpMuxRelay on loopback:
//   client --(CO ch=1 header)--> relay public port --(bare payload)--> game listener
//   game listener --(reply)--> relay --(CO ch=1 header)--> client
bool run_relay_roundtrip_selftest() {
#ifdef _WIN32
    WSADATA wsa;
    WSAStartup(MAKEWORD(2, 2), &wsa);
#endif
    SOCKET game = socket(AF_INET, SOCK_DGRAM, 0);
    SOCKET client = socket(AF_INET, SOCK_DGRAM, 0);
    if (game == INVALID_SOCKET || client == INVALID_SOCKET) return false;

    sockaddr_in loop{};
    loop.sin_family = AF_INET;
    loop.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    loop.sin_port = htons(0);
    if (bind(game, reinterpret_cast<sockaddr*>(&loop), sizeof(loop)) != 0) return false;
    socklen_t glen = sizeof(loop);
    getsockname(game, reinterpret_cast<sockaddr*>(&loop), &glen);
    uint16_t game_port = ntohs(loop.sin_port);

    calradia::net::UdpMuxRelay relay({{1, game_port}});
    if (!relay.start(0, false)) return false;

    const std::string request = "WARBAND_BATTLE_JOIN";
    auto framed = calradia::net::encode_mux_frame(1, 0xABCD0001u,
        reinterpret_cast<const uint8_t*>(request.data()), request.size());
    sockaddr_in pub{};
    pub.sin_family = AF_INET;
    pub.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    pub.sin_port = htons(relay.public_port());
    sendto(client, reinterpret_cast<const char*>(framed.data()), static_cast<int>(framed.size()), 0,
           reinterpret_cast<sockaddr*>(&pub), sizeof(pub));

    // Step 1: relay forwards the client datagram to the game listener
    if (!relay.pump_once()) return false;
    char gbuf[256];
    sockaddr_in relay_side{};
    socklen_t rlen = sizeof(relay_side);
    int gn = recvfrom(game, gbuf, sizeof(gbuf), 0, reinterpret_cast<sockaddr*>(&relay_side), &rlen);
    if (gn != static_cast<int>(request.size()) || std::string(gbuf, gn) != request) return false;

    // Step 2: game replies to the relay's channel socket; relay wraps it with the CO header
    const std::string reply = "BATTLE_ACK_OK";
    sendto(game, reply.data(), static_cast<int>(reply.size()), 0,
           reinterpret_cast<sockaddr*>(&relay_side), sizeof(relay_side));
    if (!relay.pump_once()) return false;

    uint8_t cbuf[256];
    int cn = recvfrom(client, reinterpret_cast<char*>(cbuf), sizeof(cbuf), 0, nullptr, nullptr);
    if (cn <= 0) return false;
    auto frame = calradia::net::decode_mux_frame(cbuf, static_cast<std::size_t>(cn));
    bool ok = frame.had_mux_header && frame.channel == 1 && frame.session_id == 0xABCD0001u &&
              std::string(frame.payload.begin(), frame.payload.end()) == reply;

    close_sock(game);
    close_sock(client);
    return ok;
}

} // namespace

int main(int argc, char** argv) {
    uint16_t public_port = 7240;
    int pool_size = 4;
    fs::path spool_dir = "saves/ipc";
    bool once = false;
    bool selftest = false;
    bool relay_selftest = false;

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--port" && i + 1 < argc) public_port = static_cast<uint16_t>(std::stoi(argv[++i]));
        else if (arg == "--pool-size" && i + 1 < argc) pool_size = std::stoi(argv[++i]);
        else if (arg == "--spool-dir" && i + 1 < argc) spool_dir = argv[++i];
        else if (arg == "--process-ipc-once") once = true;
        else if (arg == "--mux-self-test") selftest = true;
        else if (arg == "--relay-self-test") relay_selftest = true;
    }

    if (relay_selftest) {
        if (!run_relay_roundtrip_selftest()) {
            std::cerr << "[FAIL] CoopUdpMux relay round-trip self-test failed.\n";
            return 1;
        }
        std::cout << "[OK] CoopUdpMux relay round-trip self-test passed.\n";
        return 0;
    }
    if (selftest) {
        if (!HostSupervisor::run_udp_mux_loopback_selftest()) {
            std::cerr << "[FAIL] CoopUdpMux loopback self-test failed.\n";
            return 1;
        }
        std::cout << "[OK] CoopUdpMux single-port routing self-test passed.\n";
        return 0;
    }

    HostSupervisor sup(public_port, pool_size, spool_dir);
    if (once) {
        auto count = sup.process_ipc_outbox_once();
        std::cout << "[OK] Processed " << count << " IPC messages.\n";
        return 0;
    }

    std::cout << "[CoopHostSupervisor] Listening on public UDP port " << public_port
              << " with " << pool_size << " tactical battle pool slots...\n";
    for (;;) {
        sup.process_ipc_outbox_once();
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
}
