#include "installer_core.hpp"
#include "../common/sha256.hpp"

#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <regex>
#include <set>
#include <sstream>

#ifdef _WIN32
  #ifndef WIN32_LEAN_AND_MEAN
    #define WIN32_LEAN_AND_MEAN
  #endif
  #ifndef NOMINMAX
    #define NOMINMAX
  #endif
  #include <windows.h>
#endif

namespace fs = std::filesystem;

namespace calradia::installer {

namespace {

constexpr const char* MOD_NAME = "CalradiaOnline";
constexpr const char* MANIFEST_FILE = "install_manifest.json";

const std::vector<std::string> NATIVE_STATIC_ASSETS = {
    "Data",
    "Resource",
    "Textures",
    "Sounds",
    "Music",
    "SceneObj",
    "languages",
    "main.bmp",
    "map.txt",
    "game_variables.txt",
};

const std::set<std::string> PROTECTED_USER_PREFIXES = {
    "saves/",
    "identity.key",
    "launcher_config.json",
};

// Protected user state: exact files (identity.key, launcher_config.json) and the whole saves/ directory.
bool is_protected_user_path(const std::string& rel_generic) {
    for (const auto& pref : PROTECTED_USER_PREFIXES) {
        if (!pref.empty() && pref.back() == '/') {
            if (rel_generic.rfind(pref, 0) == 0) return true;
        } else if (rel_generic == pref) {
            return true;
        }
    }
    return false;
}

// Manifest entries are read from disk: refuse anything that could escape Modules/CalradiaOnline.
bool is_safe_relative_path(const std::string& rel_generic) {
    if (rel_generic.empty() || rel_generic.front() == '/' || rel_generic.find(':') != std::string::npos) {
        return false;
    }
    std::size_t start = 0;
    while (start <= rel_generic.size()) {
        std::size_t end = rel_generic.find('/', start);
        if (end == std::string::npos) end = rel_generic.size();
        if (rel_generic.substr(start, end - start) == "..") return false;
        start = end + 1;
    }
    return true;
}

std::string json_escape(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 8);
    for (char c : s) {
        if (c == '\\') out += "\\\\";
        else if (c == '"') out += "\\\"";
        else if (c == '\n') out += "\\n";
        else out += c;
    }
    return out;
}

void copy_tree_recorded(
    const fs::path& src,
    const fs::path& dst,
    const fs::path& mod_root,
    std::vector<ManifestEntry>& manifest) {
    if (!fs::exists(src)) return;

    if (fs::is_regular_file(src)) {
        fs::create_directories(dst.parent_path());
        fs::copy_file(src, dst, fs::copy_options::overwrite_existing);
        std::string rel = fs::relative(dst, mod_root).generic_string();
        manifest.push_back({rel, crypto::sha256_file_hex(dst.string())});
        return;
    }

    for (const auto& entry : fs::recursive_directory_iterator(src)) {
        if (!entry.is_regular_file()) continue;
        fs::path rel_sub = fs::relative(entry.path(), src);
        fs::path target = dst / rel_sub;
        fs::create_directories(target.parent_path());
        fs::copy_file(entry.path(), target, fs::copy_options::overwrite_existing);
        std::string rel = fs::relative(target, mod_root).generic_string();
        manifest.push_back({rel, crypto::sha256_file_hex(target.string())});
    }
}

void write_manifest(
    const fs::path& manifest_path,
    const std::string& version_tag,
    std::vector<ManifestEntry>& entries) {
    // Deduplicate & sort deterministically by rel_path (last write wins when mod overlays Native!)
    std::sort(entries.begin(), entries.end(), [](const ManifestEntry& a, const ManifestEntry& b) {
        return a.rel_path < b.rel_path;
    });
    std::vector<ManifestEntry> dedup;
    for (const auto& e : entries) {
        if (!dedup.empty() && dedup.back().rel_path == e.rel_path) {
            dedup.back() = e;
        } else {
            dedup.push_back(e);
        }
    }
    entries.swap(dedup);

    std::ofstream ofs(manifest_path, std::ios::binary | std::ios::trunc);
    ofs << "{\n";
    ofs << "  \"mod\": \"" << MOD_NAME << "\",\n";
    ofs << "  \"version\": \"" << json_escape(version_tag) << "\",\n";
    ofs << "  \"files\": [\n";
    for (std::size_t i = 0; i < entries.size(); ++i) {
        ofs << "    {\"path\": \"" << json_escape(entries[i].rel_path)
            << "\", \"sha256\": \"" << entries[i].sha256 << "\"}"
            << (i + 1 < entries.size() ? "," : "") << "\n";
    }
    ofs << "  ]\n";
    ofs << "}\n";
}

void parse_steam_library_vdf(const fs::path& vdf_path, std::vector<fs::path>& candidates) {
    std::ifstream ifs(vdf_path);
    if (!ifs) return;
    std::string line;
    std::regex path_re("\"path\"\\s+\"([^\"]+)\"");
    while (std::getline(ifs, line)) {
        std::smatch m;
        if (std::regex_search(line, m, path_re)) {
            std::string raw = m[1].str();
            // Unescape double backslashes in Steam VDF
            std::string clean;
            for (std::size_t i = 0; i < raw.size(); ++i) {
                if (raw[i] == '\\' && i + 1 < raw.size() && raw[i + 1] == '\\') {
                    clean += '\\';
                    ++i;
                } else {
                    clean += raw[i];
                }
            }
            candidates.push_back(fs::path(clean) / "steamapps" / "common" / "MountBlade Warband");
        }
    }
}

void prune_empty_dirs_bottom_up(const fs::path& root) {
    if (!fs::exists(root)) return;
    std::vector<fs::path> dirs;
    for (const auto& entry : fs::recursive_directory_iterator(root)) {
        if (entry.is_directory()) {
            dirs.push_back(entry.path());
        }
    }
    std::sort(dirs.begin(), dirs.end(), [](const fs::path& a, const fs::path& b) {
        return a.generic_string().size() > b.generic_string().size();
    });
    for (const auto& d : dirs) {
        std::error_code ec;
        if (fs::exists(d, ec) && fs::is_empty(d, ec)) {
            fs::remove(d, ec);
        }
    }
}

} // namespace

bool is_valid_warband_dir(const fs::path& dir) {
    std::error_code ec;
    if (!fs::exists(dir, ec) || !fs::is_directory(dir, ec)) return false;
    bool has_exe = fs::exists(dir / "mb_warband.exe", ec) ||
                   fs::exists(dir / "mb_warband_wse2.exe", ec) ||
                   fs::exists(dir / "mb_warband_linux", ec);
    bool has_native = fs::exists(dir / "Modules" / "Native" / "module.ini", ec);
    return has_exe && has_native;
}

std::vector<fs::path> detect_warband_installations(const std::vector<fs::path>& extra_search_roots) {
    std::vector<fs::path> candidates;

    if (const char* env_wb = std::getenv("WARBAND_DIR")) {
        candidates.emplace_back(env_wb);
    }

#ifdef _WIN32
    auto query_reg_str = [](HKEY root, const char* subkey, const char* val_name) -> std::string {
        char buf[1024] = {};
        DWORD sz = sizeof(buf);
        if (RegGetValueA(root, subkey, val_name, RRF_RT_REG_SZ, nullptr, buf, &sz) == ERROR_SUCCESS) {
            return std::string(buf);
        }
        return {};
    };

    // 1. TaleWorlds Standalone Registry keys
    for (const char* tw_key : {
        "SOFTWARE\\WOW6432Node\\Mount&Blade Warband",
        "SOFTWARE\\Mount&Blade Warband"
    }) {
        std::string p = query_reg_str(HKEY_LOCAL_MACHINE, tw_key, "");
        if (!p.empty()) candidates.emplace_back(p);
        p = query_reg_str(HKEY_CURRENT_USER, tw_key, "");
        if (!p.empty()) candidates.emplace_back(p);
    }

    // 2. GOG Galaxy Registry keys (GOG AppID 1207659022)
    for (const char* gog_key : {
        "SOFTWARE\\WOW6432Node\\GOG.com\\Games\\1207659022",
        "SOFTWARE\\GOG.com\\Games\\1207659022"
    }) {
        std::string p = query_reg_str(HKEY_LOCAL_MACHINE, gog_key, "path");
        if (!p.empty()) candidates.emplace_back(p);
    }

    // 3. Steam Registry path + libraryfolders.vdf
    for (const char* stm_key : {
        "SOFTWARE\\WOW6432Node\\Valve\\Steam",
        "SOFTWARE\\Valve\\Steam"
    }) {
        std::string sp = query_reg_str(HKEY_LOCAL_MACHINE, stm_key, "InstallPath");
        if (sp.empty()) sp = query_reg_str(HKEY_CURRENT_USER, stm_key, "SteamPath");
        if (!sp.empty()) {
            fs::path sroot(sp);
            candidates.push_back(sroot / "steamapps" / "common" / "MountBlade Warband");
            parse_steam_library_vdf(sroot / "steamapps" / "libraryfolders.vdf", candidates);
        }
    }
#endif

    for (const auto& extra : extra_search_roots) {
        candidates.push_back(extra);
        candidates.push_back(extra / "MountBlade Warband");
        candidates.push_back(extra / "Mount&Blade Warband");
        candidates.push_back(extra / "steamapps" / "common" / "MountBlade Warband");
        parse_steam_library_vdf(extra / "steamapps" / "libraryfolders.vdf", candidates);
    }

    if (const char* home = std::getenv("HOME")) {
        fs::path h(home);
        candidates.push_back(h / ".steam" / "steam" / "steamapps" / "common" / "MountBlade Warband");
        candidates.push_back(h / ".local" / "share" / "Steam" / "steamapps" / "common" / "MountBlade Warband");
        parse_steam_library_vdf(h / ".steam" / "steam" / "steamapps" / "libraryfolders.vdf", candidates);
        parse_steam_library_vdf(h / ".local" / "share" / "Steam" / "steamapps" / "libraryfolders.vdf", candidates);
    }

    // Standard Windows Steam / GOG / TaleWorlds Standalone paths across drives C..G
    for (char drive : {'C', 'D', 'E', 'F', 'G'}) {
        std::string root = std::string(1, drive) + ":/";
        candidates.push_back(fs::path(root) / "Program Files (x86)/Steam/steamapps/common/MountBlade Warband");
        candidates.push_back(fs::path(root) / "SteamLibrary/steamapps/common/MountBlade Warband");
        candidates.push_back(fs::path(root) / "GOG Games/Mount and Blade - Warband");
        candidates.push_back(fs::path(root) / "Program Files (x86)/Mount&Blade Warband");
        candidates.push_back(fs::path(root) / "Games/Mount&Blade Warband");
        parse_steam_library_vdf(fs::path(root) / "Program Files (x86)/Steam/steamapps/libraryfolders.vdf", candidates);
    }

    std::vector<fs::path> found;
    std::set<std::string> seen;
    for (const auto& c : candidates) {
        if (is_valid_warband_dir(c)) {
            std::error_code ec;
            std::string canon = fs::weakly_canonical(c, ec).generic_string();
            if (seen.insert(canon).second) {
                found.push_back(c);
            }
        }
    }
    return found;
}

std::vector<ManifestEntry> read_manifest(const fs::path& manifest_path) {
    std::vector<ManifestEntry> entries;
    std::ifstream ifs(manifest_path);
    if (!ifs) return entries;
    std::string line;
    std::regex entry_re("\"path\"\\s*:\\s*\"([^\"]+)\"\\s*,\\s*\"sha256\"\\s*:\\s*\"([0-9a-fA-F]+)\"");
    while (std::getline(ifs, line)) {
        std::smatch m;
        if (std::regex_search(line, m, entry_re) && is_safe_relative_path(m[1].str())) {
            entries.push_back({m[1].str(), m[2].str()});
        }
    }
    return entries;
}

namespace {

// Builds a complete CalradiaOnline tree (Native static assets + package overlay + manifest) inside `dst`.
// Never touches identity.key or saves/: those are user state and live outside the manifest.
void build_mod_tree(
    const fs::path& warband_root,
    const fs::path& package_dir,
    const fs::path& dst,
    const std::string& version_tag) {
    const fs::path native_dir = warband_root / "Modules" / "Native";
    fs::create_directories(dst);

    std::vector<ManifestEntry> manifest;

    // 1. Copy base static assets locally from the player's legal Modules/Native folder
    for (const auto& item : NATIVE_STATIC_ASSETS) {
        fs::path src = native_dir / item;
        if (fs::exists(src)) {
            copy_tree_recorded(src, dst / item, dst, manifest);
        }
    }

    // 2. Overlay CalradiaOnline compiled .txt, lua/, deploy configs & runtime helpers from package_dir
    if (fs::exists(package_dir / "export")) {
        copy_tree_recorded(package_dir / "export", dst, dst, manifest);
    }
    if (fs::exists(package_dir / "lua")) {
        copy_tree_recorded(package_dir / "lua", dst / "lua", dst, manifest);
    }
    if (fs::exists(package_dir / "deploy")) {
        copy_tree_recorded(package_dir / "deploy", dst, dst, manifest);
    }
    if (fs::exists(package_dir / "bin")) {
        copy_tree_recorded(package_dir / "bin", dst / "bin", dst, manifest);
    }
    // Support flat pre-assembled package layout too
    for (const auto& entry : fs::directory_iterator(package_dir)) {
        std::string fn = entry.path().filename().string();
        if (fn == "export" || fn == "lua" || fn == "deploy" || fn == "bin") continue;
        if (entry.is_regular_file()) {
            copy_tree_recorded(entry.path(), dst / fn, dst, manifest);
        }
    }

    // 3. Write install_manifest.json (the single source of truth for what this version owns)
    write_manifest(dst / MANIFEST_FILE, version_tag, manifest);
}

void ensure_identity(const fs::path& module_dir) {
    // Player's cryptographic identity.key is created once and then preserved across updates
    crypto::load_or_create_identity_file((module_dir / "identity.key").string());
}

bool package_is_usable(const fs::path& package_dir, std::string& why) {
    std::error_code ec;
    if (!fs::is_directory(package_dir, ec)) {
        why = "Package directory does not exist: " + package_dir.string();
        return false;
    }
    return true;
}

} // namespace

InstallResult perform_install(
    const fs::path& warband_root,
    const fs::path& package_dir,
    const std::string& version_tag) {
    InstallResult res;
    res.warband_root = warband_root;
    res.module_dir = warband_root / "Modules" / MOD_NAME;

    if (!is_valid_warband_dir(warband_root)) {
        res.message = "Invalid Mount & Blade: Warband directory (missing mb_warband executable or Modules/Native).";
        return res;
    }
    if (!package_is_usable(package_dir, res.message)) {
        return res;
    }
    if (fs::exists(res.module_dir / MANIFEST_FILE)) {
        res.message = "CalradiaOnline is already installed. Use the clean update instead (it removes old files safely).";
        return res;
    }

    build_mod_tree(warband_root, package_dir, res.module_dir, version_tag);
    fs::create_directories(res.module_dir / "saves");
    fs::create_directories(res.module_dir / "logs");
    ensure_identity(res.module_dir);

    res.ok = true;
    res.files_installed = read_manifest(res.module_dir / MANIFEST_FILE).size();
    res.message = "Installed CalradiaOnline v" + version_tag + " successfully.";
    return res;
}

// Build-then-swap clean update:
//   1. Build the complete NEW tree in a staging folder. If this fails, the live install is untouched.
//   2. Back up user state (saves/, identity.key, launcher_config.json) as a safety copy.
//   3. Remove every file the OLD manifest tracks, plus any untracked leftovers (never user state).
//   4. Move the staged files into place, then ensure identity.key exists.
//   5. Delete the backup only after the swap succeeded.
InstallResult perform_clean_update(
    const fs::path& warband_root,
    const fs::path& new_package_dir,
    const std::string& new_version_tag) {
    InstallResult res;
    res.warband_root = warband_root;
    res.module_dir = warband_root / "Modules" / MOD_NAME;

    if (!is_valid_warband_dir(warband_root)) {
        res.message = "Invalid Mount & Blade: Warband directory.";
        return res;
    }
    if (!package_is_usable(new_package_dir, res.message)) {
        res.message = "Update package directory not found: " + new_package_dir.string();
        return res;
    }

    const fs::path modules_dir = warband_root / "Modules";
    const fs::path staging_dir = modules_dir / ".CalradiaOnline_staging";
    const fs::path backup_dir = modules_dir / ".CalradiaOnline_update_backup";
    std::error_code ec;

    // Step 1: stage the new build without touching the live install
    fs::remove_all(staging_dir, ec);
    try {
        build_mod_tree(warband_root, new_package_dir, staging_dir, new_version_tag);
    } catch (const std::exception& ex) {
        fs::remove_all(staging_dir, ec);
        res.message = std::string("Update aborted before changing anything (staging failed): ") + ex.what();
        return res;
    }

    // Step 2: safety backup of user state
    fs::remove_all(backup_dir, ec);
    fs::create_directories(backup_dir);
    if (fs::exists(res.module_dir / "saves")) {
        fs::copy(res.module_dir / "saves", backup_dir / "saves", fs::copy_options::recursive, ec);
    }
    for (const char* ufile : {"identity.key", "launcher_config.json"}) {
        if (fs::exists(res.module_dir / ufile)) {
            fs::copy_file(res.module_dir / ufile, backup_dir / ufile, fs::copy_options::overwrite_existing, ec);
        }
    }

    // Step 3: remove the old tracked files and any stale leftovers outside user state
    std::size_t removed_count = 0;
    fs::path old_manifest = res.module_dir / MANIFEST_FILE;
    if (fs::exists(old_manifest)) {
        for (const auto& item : read_manifest(old_manifest)) {
            if (is_protected_user_path(item.rel_path)) continue;
            fs::path p = res.module_dir / item.rel_path;
            if (fs::exists(p, ec) && fs::remove(p, ec)) ++removed_count;
        }
    }
    if (fs::exists(res.module_dir)) {
        std::vector<fs::path> stale_files;
        for (const auto& entry : fs::recursive_directory_iterator(res.module_dir)) {
            if (!entry.is_regular_file()) continue;
            std::string rel = fs::relative(entry.path(), res.module_dir).generic_string();
            if (!is_protected_user_path(rel)) stale_files.push_back(entry.path());
        }
        for (const auto& sf : stale_files) {
            if (fs::remove(sf, ec)) ++removed_count;
        }
        prune_empty_dirs_bottom_up(res.module_dir);
    }

    // Step 4: move the staged tree into place (the staging tree contains no user state)
    try {
        for (const auto& entry : fs::recursive_directory_iterator(staging_dir)) {
            if (!entry.is_regular_file()) continue;
            fs::path rel = fs::relative(entry.path(), staging_dir);
            fs::path target = res.module_dir / rel;
            fs::create_directories(target.parent_path());
            fs::rename(entry.path(), target);
        }
        fs::create_directories(res.module_dir / "saves");
        fs::create_directories(res.module_dir / "logs");
        ensure_identity(res.module_dir);
    } catch (const std::exception& ex) {
        res.message = std::string("Update failed while installing new files: ") + ex.what() +
                      ". Your saves and identity.key are safe in " + backup_dir.string();
        return res;
    }

    // Step 5: success — drop the staging leftovers and the backup
    fs::remove_all(staging_dir, ec);
    fs::remove_all(backup_dir, ec);

    res.ok = true;
    res.files_installed = read_manifest(res.module_dir / MANIFEST_FILE).size();
    res.files_removed_old = removed_count;
    res.message = "Clean update to v" + new_version_tag + " complete (removed " +
                  std::to_string(removed_count) + " old files, preserved saves & identity.key).";
    return res;
}

InstallResult perform_uninstall(const fs::path& warband_root, bool keep_saves) {
    InstallResult res;
    res.warband_root = warband_root;
    res.module_dir = warband_root / "Modules" / MOD_NAME;

    std::error_code ec;
    if (!fs::exists(res.module_dir, ec)) {
        res.ok = true;
        res.message = "CalradiaOnline is already uninstalled.";
        return res;
    }

    std::size_t removed_count = 0;
    auto entries = read_manifest(res.module_dir / MANIFEST_FILE);
    for (const auto& e : entries) {
        if (!is_safe_relative_path(e.rel_path)) continue;
        if (keep_saves && is_protected_user_path(e.rel_path)) continue;
        fs::path target = res.module_dir / e.rel_path;
        if (fs::exists(target, ec) && fs::remove(target, ec)) {
            ++removed_count;
        }
    }
    fs::remove(res.module_dir / MANIFEST_FILE, ec);

    if (!keep_saves) {
        // Complete removal of every single file and directory created by CalradiaOnline
        for (const auto& entry : fs::recursive_directory_iterator(res.module_dir, ec)) {
            if (entry.is_regular_file()) ++removed_count;
        }
        fs::remove_all(res.module_dir, ec);
    } else {
        // Remove everything except saves/ and identity.key
        std::vector<fs::path> non_save_files;
        for (const auto& entry : fs::recursive_directory_iterator(res.module_dir, ec)) {
            if (!entry.is_regular_file()) continue;
            std::string rel = fs::relative(entry.path(), res.module_dir).generic_string();
            if (!is_protected_user_path(rel)) {
                non_save_files.push_back(entry.path());
            }
        }
        for (const auto& f : non_save_files) {
            if (fs::remove(f, ec)) ++removed_count;
        }
        prune_empty_dirs_bottom_up(res.module_dir);
    }

    res.ok = true;
    res.files_removed_old = removed_count;
    res.message = keep_saves
        ? "Uninstalled CalradiaOnline cleanly (kept user saves & identity.key)."
        : "Uninstalled CalradiaOnline completely (zero files remaining).";
    return res;
}

} // namespace calradia::installer
