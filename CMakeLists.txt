cmake_minimum_required(VERSION 3.16)
project(CalradiaOnlineNative LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(calradia_common STATIC
    native/common/sha256.cpp
    native/common/udp_mux.cpp
)
target_include_directories(calradia_common PUBLIC native/common)

add_executable(coop_host_supervisor native/supervisor/coop_host_supervisor.cpp)
target_link_libraries(coop_host_supervisor PRIVATE calradia_common)

add_executable(coop_net_proxy native/client_helper/coop_net_proxy.cpp)
target_link_libraries(coop_net_proxy PRIVATE calradia_common)

add_executable(calradia_launcher native/launcher/calradia_launcher.cpp)
target_link_libraries(calradia_launcher PRIVATE calradia_common)

add_executable(calradia_installer
    native/installer/calradia_installer.cpp
    native/installer/installer_core.cpp
)
target_link_libraries(calradia_installer PRIVATE calradia_common)

if(WIN32)
    target_link_libraries(coop_host_supervisor PRIVATE ws2_32)
    target_link_libraries(calradia_installer PRIVATE advapi32)
else()
    find_package(Threads REQUIRED)
    target_link_libraries(coop_host_supervisor PRIVATE Threads::Threads)
    target_link_libraries(coop_net_proxy PRIVATE ${CMAKE_DL_LIBS})
endif()
