#pragma once
// Single-port UDP relay for CoopUdpMux.
//
// Client -> relay: datagram with "CO" header (or legacy raw datagram => channel 0).
//                  The 8-byte header is stripped and the bare payload is sent to the
//                  game-side port that is registered for that channel.
// Game -> relay:   bare payload from a registered game-side port is wrapped with the
//                  "CO" header (same channel, last known session_id) and sent back to the
//                  client that last used that channel.
//
// The game engine never sees the mux header, so Warband stays unmodified on the wire.

#include "udp_mux.hpp"

#include <cstdint>
#include <cstring>
#include <map>
#include <utility>
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
  #ifndef UDP_RELAY_SOCK_T
    #define UDP_RELAY_SOCK_T SOCKET
  #endif
#else
  #include <arpa/inet.h>
  #include <netinet/in.h>
  #include <sys/select.h>
  #include <sys/socket.h>
  #include <unistd.h>
  #ifndef UDP_RELAY_SOCK_T
    #define UDP_RELAY_SOCK_T int
  #endif
#endif

namespace calradia::net {

#ifdef _WIN32
using relay_len_t = int;
#else
using relay_len_t = socklen_t;
#endif

class UdpMuxRelay {
public:
    using Sock = UDP_RELAY_SOCK_T;

    // game_ports: channel -> loopback port of the game-side listener for that channel
    explicit UdpMuxRelay(std::map<uint8_t, uint16_t> game_ports)
        : game_ports_(std::move(game_ports)) {}

    ~UdpMuxRelay() { close_all(); }

    UdpMuxRelay(const UdpMuxRelay&) = delete;
    UdpMuxRelay& operator=(const UdpMuxRelay&) = delete;

    // public_port == 0 selects an ephemeral port (used by self-tests)
    bool start(uint16_t public_port, bool all_interfaces) {
        if (!net_init()) return false;
        public_sock_ = make_udp_socket();
        if (!valid(public_sock_)) return false;
        sockaddr_in addr{};
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = htonl(all_interfaces ? INADDR_ANY : INADDR_LOOPBACK);
        addr.sin_port = htons(public_port);
        if (::bind(public_sock_, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0) return false;
        if (!local_port(public_sock_, public_port_)) return false;

        for (const auto& [channel, game_port] : game_ports_) {
            Route r;
            r.channel = channel;
            r.game_port = game_port;
            r.sock = make_udp_socket();
            if (!valid(r.sock)) return false;
            sockaddr_in any{};
            any.sin_family = AF_INET;
            any.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
            any.sin_port = htons(0);
            if (::bind(r.sock, reinterpret_cast<sockaddr*>(&any), sizeof(any)) != 0) return false;
            routes_.push_back(r);
        }
        return true;
    }

    uint16_t public_port() const { return public_port_; }

    // Waits for one datagram on any socket and forwards it. Returns false on socket error.
    bool pump_once() {
        fd_set rfds;
        FD_ZERO(&rfds);
        FD_SET(public_sock_, &rfds);
        Sock max_fd = public_sock_;
        for (const auto& r : routes_) {
            FD_SET(r.sock, &rfds);
            if (r.sock > max_fd) max_fd = r.sock;
        }
        if (select(static_cast<int>(max_fd) + 1, &rfds, nullptr, nullptr, nullptr) <= 0) return false;

        if (FD_ISSET(public_sock_, &rfds)) {
            forward_client_datagram();
        }
        for (auto& r : routes_) {
            if (FD_ISSET(r.sock, &rfds)) {
                forward_game_datagram(r);
            }
        }
        return true;
    }

    // Pumps until `count` datagrams have been forwarded in total.
    bool pump_n(std::size_t count) {
        for (std::size_t i = 0; i < count; ++i) {
            if (!pump_once()) return false;
        }
        return true;
    }

private:
    struct Route {
        uint8_t channel = 0;
        uint16_t game_port = 0;
        Sock sock = invalid_sock();
        bool has_client = false;
        sockaddr_in client{};
        uint32_t session_id = 0;
    };

    static Sock invalid_sock() {
#ifdef _WIN32
        return INVALID_SOCKET;
#else
        return -1;
#endif
    }

    static bool valid(Sock s) {
#ifdef _WIN32
        return s != INVALID_SOCKET;
#else
        return s >= 0;
#endif
    }

    static Sock make_udp_socket() {
        return ::socket(AF_INET, SOCK_DGRAM, 0);
    }

    static bool net_init() {
#ifdef _WIN32
        static bool done = false;
        static bool ok = false;
        if (!done) {
            WSADATA wsa;
            ok = (WSAStartup(MAKEWORD(2, 2), &wsa) == 0);
            done = true;
        }
        return ok;
#else
        return true;
#endif
    }

    static void close_sock(Sock s) {
#ifdef _WIN32
        closesocket(s);
#else
        close(s);
#endif
    }

    static bool local_port(Sock s, uint16_t& out) {
        sockaddr_in addr{};
        relay_len_t len = sizeof(addr);
        if (getsockname(s, reinterpret_cast<sockaddr*>(&addr), &len) != 0) return false;
        out = ntohs(addr.sin_port);
        return true;
    }

    void forward_client_datagram() {
        uint8_t buf[2048];
        sockaddr_in from{};
        relay_len_t flen = sizeof(from);
        int n = ::recvfrom(public_sock_, reinterpret_cast<char*>(buf), sizeof(buf), 0,
                           reinterpret_cast<sockaddr*>(&from), &flen);
        if (n <= 0) return;

        MuxFrame frame = decode_mux_frame(buf, static_cast<std::size_t>(n));
        for (auto& r : routes_) {
            if (r.channel != frame.channel) continue;
            r.client = from;
            r.has_client = true;
            r.session_id = frame.session_id;
            sockaddr_in game{};
            game.sin_family = AF_INET;
            game.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
            game.sin_port = htons(r.game_port);
            ::sendto(r.sock, reinterpret_cast<const char*>(frame.payload.data()),
                     static_cast<int>(frame.payload.size()), 0,
                     reinterpret_cast<sockaddr*>(&game), sizeof(game));
            return;
        }
        // Unknown channel: dropped (no game listener registered for it)
    }

    void forward_game_datagram(Route& r) {
        uint8_t buf[2048];
        sockaddr_in from{};
        relay_len_t flen = sizeof(from);
        int n = ::recvfrom(r.sock, reinterpret_cast<char*>(buf), sizeof(buf), 0,
                           reinterpret_cast<sockaddr*>(&from), &flen);
        if (n <= 0 || !r.has_client) return;
        auto wrapped = encode_mux_frame(r.channel, r.session_id, buf, static_cast<std::size_t>(n));
        ::sendto(public_sock_, reinterpret_cast<const char*>(wrapped.data()),
                 static_cast<int>(wrapped.size()), 0,
                 reinterpret_cast<sockaddr*>(&r.client), sizeof(r.client));
    }

    void close_all() {
        if (valid(public_sock_)) close_sock(public_sock_);
        for (auto& r : routes_) {
            if (valid(r.sock)) close_sock(r.sock);
        }
        routes_.clear();
    }

    std::map<uint8_t, uint16_t> game_ports_;
    std::vector<Route> routes_;
    Sock public_sock_ = invalid_sock();
    uint16_t public_port_ = 0;
};

} // namespace calradia::net
