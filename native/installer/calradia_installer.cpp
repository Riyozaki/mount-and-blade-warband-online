#include "installer_core.hpp"

#include <exception>
#include <iostream>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace {

void print_usage() {
    std::cout << "Calradia Online — Few-Click Auto-Detecting Installer / Clean Updater / Uninstaller\n"
              << "Usage:\n"
              << "  calradia_installer                     (Interactive Wizard on double-click)\n"
              << "  calradia_installer detect  [--search-root <dir>]\n"
              << "  calradia_installer install [--warband <dir>] --package <dir> [--version <ver>]\n"
              << "  calradia_installer update  [--warband <dir>] --package <dir> [--version <ver>]\n"
              << "  calradia_installer uninstall [--warband <dir>] [--keep-saves]\n";
}

fs::path auto_find_local_package(const fs::path& exe_path) {
    fs::path base = exe_path.has_parent_path() ? exe_path.parent_path() : fs::current_path();
    for (const auto& cand : {
        base / "CalradiaOnlinePackage",
        fs::current_path() / "CalradiaOnlinePackage",
        base / ".." / "CalradiaOnlinePackage",
        base
    }) {
        std::error_code ec;
        if (fs::exists(cand / "export" / "scripts.txt", ec) || fs::exists(cand / "lua" / "main.lua", ec)) {
            return cand;
        }
    }
    return base / "CalradiaOnlinePackage";
}

int run_interactive_wizard(const fs::path& exe_path) {
    std::cout << "====================================================================\n"
              << "  Calradia Online — Cooperative Campaign Installer & Clean Updater\n"
              << "====================================================================\n\n";

    auto found = calradia::installer::detect_warband_installations();
    fs::path warband_dir;
    if (!found.empty()) {
        warband_dir = found.front();
        std::cout << "[Auto-Detected Warband]: " << warband_dir.string() << "\n";
    } else {
        std::cout << "[!] Mount & Blade: Warband path was not auto-detected.\n"
                  << "Enter full path to Mount & Blade Warband folder: ";
        std::string custom_p;
        std::getline(std::cin, custom_p);
        if (custom_p.empty()) return 1;
        warband_dir = custom_p;
    }

    fs::path pkg_dir = auto_find_local_package(exe_path);
    std::cout << "\nSelect action:\n"
              << "  [1] Install Calradia Online (copies Native assets locally + installs mod)\n"
              << "  [2] Clean Update (removes 100% of old mod files, preserves saves & identity.key)\n"
              << "  [3] Uninstall completely (removes all mod files)\n"
              << "  [4] Uninstall mod files only (keep campaign saves & identity.key)\n"
              << "  [0] Exit\n"
              << "\nChoice [0-4]: ";

    std::string choice;
    if (!std::getline(std::cin, choice)) return 0;

    calradia::installer::InstallResult res;
    if (choice == "1") {
        // Already installed? Treat "install" as a safe clean update so no stale files survive.
        if (fs::exists(warband_dir / "Modules" / "CalradiaOnline" / "install_manifest.json")) {
            std::cout << "[i] Mod already present — performing clean update instead.\n";
            res = calradia::installer::perform_clean_update(warband_dir, pkg_dir, "1.0.0");
        } else {
            res = calradia::installer::perform_install(warband_dir, pkg_dir, "1.0.0");
        }
    } else if (choice == "2") {
        res = calradia::installer::perform_clean_update(warband_dir, pkg_dir, "1.0.0");
    } else if (choice == "3") {
        res = calradia::installer::perform_uninstall(warband_dir, false);
    } else if (choice == "4") {
        res = calradia::installer::perform_uninstall(warband_dir, true);
    } else {
        return 0;
    }

    std::cout << "\n" << (res.ok ? "[OK] " : "[ERROR] ") << res.message << "\n"
              << "Press Enter to close...";
    std::string dummy;
    std::getline(std::cin, dummy);
    return res.ok ? 0 : 1;
}

} // namespace

namespace {

int run_cli(int argc, char** argv) {
    if (argc < 2) {
        return run_interactive_wizard(argc > 0 ? fs::path(argv[0]) : fs::current_path());
    }

    std::string cmd = argv[1];
    if (cmd == "--help" || cmd == "-h") {
        print_usage();
        return 0;
    }

    fs::path warband_dir;
    fs::path package_dir;
    std::string version_tag = "1.0.0";
    bool keep_saves = false;
    std::vector<fs::path> extra_roots;

    for (int i = 2; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--warband" && i + 1 < argc) {
            warband_dir = argv[++i];
        } else if (arg == "--package" && i + 1 < argc) {
            package_dir = argv[++i];
        } else if (arg == "--version" && i + 1 < argc) {
            version_tag = argv[++i];
        } else if (arg == "--search-root" && i + 1 < argc) {
            extra_roots.emplace_back(argv[++i]);
        } else if (arg == "--keep-saves") {
            keep_saves = true;
        }
    }

    if (cmd == "detect") {
        auto found = calradia::installer::detect_warband_installations(extra_roots);
        if (found.empty()) {
            std::cerr << "[detect] No Mount & Blade: Warband installations detected.\n";
            return 2;
        }
        for (const auto& p : found) {
            std::cout << p.string() << "\n";
        }
        return 0;
    }

    if (package_dir.empty() && (cmd == "install" || cmd == "update")) {
        package_dir = auto_find_local_package(argc > 0 ? fs::path(argv[0]) : fs::current_path());
    }

    if (warband_dir.empty()) {
        auto found = calradia::installer::detect_warband_installations(extra_roots);
        if (found.empty()) {
            std::cerr << "Could not auto-detect Mount & Blade: Warband. Pass --warband <dir>.\n";
            return 2;
        }
        warband_dir = found.front();
        std::cout << "[auto-detect] Selected Warband installation: " << warband_dir.string() << "\n";
    }

    calradia::installer::InstallResult res;
    if (cmd == "install") {
        if (fs::exists(warband_dir / "Modules" / "CalradiaOnline" / "install_manifest.json")) {
            std::cout << "[i] Mod already present — performing clean update instead.\n";
            res = calradia::installer::perform_clean_update(warband_dir, package_dir, version_tag);
        } else {
            res = calradia::installer::perform_install(warband_dir, package_dir, version_tag);
        }
    } else if (cmd == "update") {
        res = calradia::installer::perform_clean_update(warband_dir, package_dir, version_tag);
    } else if (cmd == "uninstall") {
        res = calradia::installer::perform_uninstall(warband_dir, keep_saves);
    } else {
        print_usage();
        return 1;
    }

    if (!res.ok) {
        std::cerr << "[ERROR] " << res.message << "\n";
        return 1;
    }
    std::cout << "[OK] " << res.message << "\n";
    return 0;
}

} // namespace

int main(int argc, char** argv) {
    try {
        return run_cli(argc, argv);
    } catch (const std::exception& ex) {
        // Never crash with an unhandled filesystem exception: report it and keep the console open
        std::cerr << "[ERROR] " << ex.what() << "\n"
                  << "Check that the game is closed and that the folder is writable.\n";
        return 1;
    }
}
