#pragma once
#include <filesystem>
#include <string>
#include <vector>

namespace calradia::installer {

struct ManifestEntry {
    std::string rel_path;
    std::string sha256;
};

struct InstallResult {
    bool ok = false;
    std::string message;
    std::filesystem::path warband_root;
    std::filesystem::path module_dir;
    std::size_t files_installed = 0;
    std::size_t files_removed_old = 0;
};

// Validate whether candidate directory is a genuine Warband installation containing Native module
bool is_valid_warband_dir(const std::filesystem::path& dir);

// Auto-detect Warband across Steam (libraryfolders.vdf), GOG, Standalone paths & environment hints
std::vector<std::filesystem::path> detect_warband_installations(
    const std::vector<std::filesystem::path>& extra_search_roots = {});

// Fresh Install: clones local Modules/Native static assets + overlays compiled CalradiaOnline build + writes install_manifest.json
InstallResult perform_install(
    const std::filesystem::path& warband_root,
    const std::filesystem::path& package_dir,
    const std::string& version_tag = "1.0.0");

// Clean Atomic Update:
//   1. Backs up user saves/, identity.key, launcher_config.json into temp staging
//   2. Reads existing install_manifest.json and removes 100% of old mod files (zero leftover stale scripts!)
//   3. Installs new package, restores user saves/identity/config, writes fresh install_manifest.json
InstallResult perform_clean_update(
    const std::filesystem::path& warband_root,
    const std::filesystem::path& new_package_dir,
    const std::string& new_version_tag = "1.0.1");

// Complete Clean Uninstall: removes every file & folder installed by CalradiaOnline (optionally preserving saves)
InstallResult perform_uninstall(
    const std::filesystem::path& warband_root,
    bool keep_saves = false);

std::vector<ManifestEntry> read_manifest(const std::filesystem::path& manifest_path);

} // namespace calradia::installer
