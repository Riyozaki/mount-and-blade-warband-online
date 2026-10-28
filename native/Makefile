CXX      ?= g++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra -Werror
OUT_DIR  ?= ../build/native

ifeq ($(OS),Windows_NT)
  LDFLAGS_NET := -lws2_32
  LDFLAGS_DL  :=
  EXE         := .exe
else
  LDFLAGS_NET := -pthread
  LDFLAGS_DL  := -ldl
  EXE         :=
endif

COMMON_SRC := common/sha256.cpp common/udp_mux.cpp

TARGETS := \
  $(OUT_DIR)/coop_host_supervisor$(EXE) \
  $(OUT_DIR)/coop_net_proxy$(EXE) \
  $(OUT_DIR)/calradia_launcher$(EXE) \
  $(OUT_DIR)/calradia_installer$(EXE)

.PHONY: all clean

all: $(TARGETS)

$(OUT_DIR):
	mkdir -p $(OUT_DIR)

$(OUT_DIR)/coop_host_supervisor$(EXE): supervisor/coop_host_supervisor.cpp $(COMMON_SRC) | $(OUT_DIR)
	$(CXX) $(CXXFLAGS) $^ -o $@ $(LDFLAGS_NET)

$(OUT_DIR)/coop_net_proxy$(EXE): client_helper/coop_net_proxy.cpp $(COMMON_SRC) | $(OUT_DIR)
	$(CXX) $(CXXFLAGS) $^ -o $@ $(LDFLAGS_DL)

$(OUT_DIR)/calradia_launcher$(EXE): launcher/calradia_launcher.cpp common/sha256.cpp | $(OUT_DIR)
	$(CXX) $(CXXFLAGS) $^ -o $@

$(OUT_DIR)/calradia_installer$(EXE): installer/calradia_installer.cpp installer/installer_core.cpp common/sha256.cpp | $(OUT_DIR)
	$(CXX) $(CXXFLAGS) $^ -o $@

clean:
	rm -rf $(OUT_DIR)
