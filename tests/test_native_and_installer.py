import os
import shutil
import subprocess
import tempfile
import unittest

from test_lua_systems import get_luajit_runtime

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
BIN_DIR = os.path.join(REPO_ROOT, "build", "native")


class TestNativeRuntimeAndInstallerLifecycle(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run(["make", "-C", "native", "-j4"], cwd=REPO_ROOT, check=True)

    def test_01_single_port_udp_mux_loopback_routing(self):
        sup_bin = os.path.join(BIN_DIR, "coop_host_supervisor")
        res = subprocess.run([sup_bin, "--mux-self-test"], capture_output=True, text=True, check=False)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("[OK] CoopUdpMux single-port routing self-test passed.", res.stdout)

    def test_02_cross_language_cpp_client_key_to_luajit_server_auth(self):
        """
        Proves C++ CoopNetProxy identity.key derivation & HMAC-SHA256 challenge signing
        authenticates 100% bit-for-bit against WSE2 LuaJIT auth.lua!
        """
        tmp = tempfile.mkdtemp(prefix="calradia_xlang_auth_")
        try:
            proxy_bin = os.path.join(BIN_DIR, "coop_net_proxy")
            key_file = os.path.join(tmp, "identity.key")

            lua = get_luajit_runtime()
            auth_mod = lua.eval('require("auth")')
            srv_auth = auth_mod.new(lua.table_from({"max_online": 16}))

            nonce = srv_auth.issue_challenge(srv_auth, 7, 5000)

            res = subprocess.run(
                [proxy_bin, "--key", key_file, "--nonce", nonce, "--nick", "Bogatyr", "--sign-challenge"],
                capture_output=True,
                text=True,
                check=True,
            )
            kv = dict(line.split("=", 1) for line in res.stdout.strip().splitlines() if "=" in line)
            ok, welcome = srv_auth.verify_response(
                srv_auth, 7, kv["player_uid"], "Bogatyr", kv["public_token"], kv["hmac_hex"], 5001
            )
            self.assertTrue(ok, f"Cross-language C++ -> LuaJIT auth failed: {welcome}")
            self.assertEqual(welcome.hero_slot, 0)

            # Verify Standalone/GOG Steam-free transport probe succeeds without steam_api
            probe = subprocess.run([proxy_bin, "--probe-transports"], capture_output=True, text=True, check=True)
            self.assertIn("direct_ip,lan,vpn,relay", probe.stdout)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_03_luajit_campaign_to_cpp_supervisor_ipc_battle_allocation(self):
        """
        Proves LuaJIT ipc_bridge -> atomic outbox JSON -> C++ CoopHostSupervisor -> atomic inbox BATTLE_READY!
        """
        tmp = tempfile.mkdtemp(prefix="calradia_ipc_")
        try:
            lua = get_luajit_runtime()
            ipc_mod = lua.eval('require("ipc_bridge")')
            btl_mod = lua.eval('require("battles")')

            spool_dir = os.path.join(tmp, "ipc")
            ipc = ipc_mod.new(lua.table_from({"spool_dir": spool_dir}))
            btl = btl_mod.new()

            node = btl.start_battle(btl, lua.table_from({
                "mission_kind": 2,
                "scene_id": "scn_castle_1_exterior",
            }))
            ok, out_path = ipc.request_battle_spawn(ipc, node)
            self.assertTrue(ok)
            self.assertTrue(os.path.isfile(out_path))

            sup_bin = os.path.join(BIN_DIR, "coop_host_supervisor")
            subprocess.run(
                [sup_bin, "--port", "7240", "--pool-size", "4", "--spool-dir", spool_dir, "--process-ipc-once"],
                check=True,
                capture_output=True,
                text=True,
            )

            inbox_dir = os.path.join(spool_dir, "inbox")
            inbox_files = [os.path.join(inbox_dir, f) for f in sorted(os.listdir(inbox_dir))]
            self.assertEqual(len(inbox_files), 1)

            msgs = ipc.poll_inbox_files(ipc, lua.table_from(inbox_files))
            msg = msgs[1]
            self.assertEqual(msg.msg_type, "BATTLE_READY")
            self.assertEqual(msg.battle_id, node.battle_id)
            self.assertEqual(msg.assigned_slot, 0)
            self.assertEqual(msg.mux_channel, 1)
            self.assertEqual(msg.battle_port, 7242)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_04_installer_autodetect_clean_update_and_complete_uninstall(self):
        """
        Verifies:
        1. Auto-detecting Warband from Steam libraryfolders.vdf
        2. Fresh Install (copying local Modules/Native assets + overlaying mod + writing install_manifest.json)
        3. Clean Update (removing 100% of old mod files & stale ghosts while preserving saves/ & identity.key!)
        4. Complete Uninstall (removing 100% of CalradiaOnline while leaving Modules/Native untouched!)
        """
        tmp = tempfile.mkdtemp(prefix="calradia_installer_e2e_")
        try:
            inst_bin = os.path.join(BIN_DIR, "calradia_installer")

            # Build realistic mock Steam library + Warband root + Modules/Native
            steam_root = os.path.join(tmp, "SteamRoot")
            wb_dir = os.path.join(steam_root, "steamapps", "common", "MountBlade Warband")
            native_dir = os.path.join(wb_dir, "Modules", "Native")
            os.makedirs(os.path.join(native_dir, "Resource"), exist_ok=True)
            os.makedirs(os.path.join(native_dir, "Textures"), exist_ok=True)
            with open(os.path.join(wb_dir, "mb_warband.exe"), "wb") as f:
                f.write(b"MZ_MOCK_WARBAND_1174")
            with open(os.path.join(native_dir, "module.ini"), "w", encoding="utf-8") as f:
                f.write("module_name = Native\n")
            with open(os.path.join(native_dir, "map.txt"), "w", encoding="utf-8") as f:
                f.write("100\n0 0 0\n")
            with open(os.path.join(native_dir, "Resource", "common_res.brf"), "wb") as f:
                f.write(b"BRF_ASSET_DATA")
            with open(os.path.join(steam_root, "steamapps", "libraryfolders.vdf"), "w", encoding="utf-8") as f:
                f.write(f'"libraryfolders"\n{{\n  "0"\n  {{\n    "path" "{steam_root}"\n  }}\n}}\n')

            # Build v1.0.0 package (including an obsolete file that v1.1.0 will drop!)
            pkg_v1 = os.path.join(tmp, "pkg_v1")
            os.makedirs(os.path.join(pkg_v1, "export"), exist_ok=True)
            os.makedirs(os.path.join(pkg_v1, "lua"), exist_ok=True)
            os.makedirs(os.path.join(pkg_v1, "deploy"), exist_ok=True)
            with open(os.path.join(pkg_v1, "export", "scripts.txt"), "w", encoding="utf-8") as f:
                f.write("scriptsfile version 1\n1\ncoop_v1 0\n")
            with open(os.path.join(pkg_v1, "lua", "main.lua"), "w", encoding="utf-8") as f:
                f.write("-- v1.0.0 main\n")
            with open(os.path.join(pkg_v1, "lua", "obsolete_in_v2.lua"), "w", encoding="utf-8") as f:
                f.write("-- must be deleted on update!\n")
            shutil.copy2(os.path.join(REPO_ROOT, "deploy", "wse2_module_config.ini"), os.path.join(pkg_v1, "deploy"))

            # 1. Auto-detect Warband
            det = subprocess.run([inst_bin, "detect", "--search-root", steam_root], capture_output=True, text=True, check=True)
            self.assertIn("MountBlade Warband", det.stdout)

            # 2. Fresh Install v1.0.0 (using auto-detection via --search-root!)
            subprocess.run(
                [inst_bin, "install", "--search-root", steam_root, "--package", pkg_v1, "--version", "1.0.0"],
                check=True, capture_output=True, text=True,
            )
            mod_dir = os.path.join(wb_dir, "Modules", "CalradiaOnline")
            self.assertTrue(os.path.isfile(os.path.join(mod_dir, "Resource", "common_res.brf")))
            self.assertTrue(os.path.isfile(os.path.join(mod_dir, "lua", "obsolete_in_v2.lua")))
            self.assertTrue(os.path.isfile(os.path.join(mod_dir, "identity.key")))
            self.assertTrue(os.path.isfile(os.path.join(mod_dir, "install_manifest.json")))

            # Read original player identity & write a campaign save + drop an untracked stale file
            with open(os.path.join(mod_dir, "identity.key"), "r", encoding="utf-8") as f:
                orig_key = f.read()
            os.makedirs(os.path.join(mod_dir, "saves", "FriendsCampaign"), exist_ok=True)
            save_file = os.path.join(mod_dir, "saves", "FriendsCampaign", "world.json")
            with open(save_file, "w", encoding="utf-8") as f:
                f.write('{"precious_campaign_progress": 9001}')
            with open(os.path.join(mod_dir, "stale_leftover_ghost.txt"), "w", encoding="utf-8") as f:
                f.write("stale file that must be wiped on clean update")

            # 3. Clean Atomic Update to v1.1.0 (does NOT contain obsolete_in_v2.lua)
            pkg_v2 = os.path.join(tmp, "pkg_v2")
            os.makedirs(os.path.join(pkg_v2, "export"), exist_ok=True)
            os.makedirs(os.path.join(pkg_v2, "lua"), exist_ok=True)
            with open(os.path.join(pkg_v2, "export", "scripts.txt"), "w", encoding="utf-8") as f:
                f.write("scriptsfile version 1\n1\ncoop_v2_upgraded 0\n")
            with open(os.path.join(pkg_v2, "lua", "main.lua"), "w", encoding="utf-8") as f:
                f.write("-- v1.1.0 upgraded main\n")

            subprocess.run(
                [inst_bin, "update", "--warband", wb_dir, "--package", pkg_v2, "--version", "1.1.0"],
                check=True, capture_output=True, text=True,
            )

            # Old mod files & stale ghosts MUST be 100% gone!
            self.assertFalse(os.path.exists(os.path.join(mod_dir, "lua", "obsolete_in_v2.lua")))
            self.assertFalse(os.path.exists(os.path.join(mod_dir, "stale_leftover_ghost.txt")))

            # Precious user save & identity.key MUST be 100% intact!
            self.assertTrue(os.path.isfile(save_file))
            with open(os.path.join(mod_dir, "identity.key"), "r", encoding="utf-8") as f:
                self.assertEqual(f.read(), orig_key)
            with open(os.path.join(mod_dir, "scripts.txt"), "r", encoding="utf-8") as f:
                self.assertIn("coop_v2_upgraded", f.read())

            # 4. Complete Uninstall removes CalradiaOnline 100% cleanly while Native stays untouched!
            subprocess.run([inst_bin, "uninstall", "--warband", wb_dir], check=True, capture_output=True, text=True)
            self.assertFalse(os.path.exists(mod_dir))
            self.assertTrue(os.path.isfile(os.path.join(native_dir, "module.ini")))
            self.assertTrue(os.path.isfile(os.path.join(wb_dir, "mb_warband.exe")))
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


    def test_05_installer_safety_traversal_guard_and_no_install_over_existing(self):
        """
        Verifies:
        1. A tampered install_manifest.json with '../' entries can NEVER delete files outside Modules/CalradiaOnline.
        2. 'install' over an existing installation automatically becomes a safe clean update (no stale files).
        """
        tmp = tempfile.mkdtemp(prefix="calradia_installer_safety_")
        try:
            inst_bin = os.path.join(BIN_DIR, "calradia_installer")
            wb_dir = os.path.join(tmp, "MountBlade Warband")
            native_dir = os.path.join(wb_dir, "Modules", "Native")
            os.makedirs(native_dir, exist_ok=True)
            with open(os.path.join(wb_dir, "mb_warband.exe"), "wb") as f:
                f.write(b"MZ_MOCK")
            with open(os.path.join(native_dir, "module.ini"), "w", encoding="utf-8") as f:
                f.write("module_name = Native\n")

            pkg = os.path.join(tmp, "pkg")
            os.makedirs(os.path.join(pkg, "lua"), exist_ok=True)
            with open(os.path.join(pkg, "lua", "main.lua"), "w", encoding="utf-8") as f:
                f.write("-- main\n")

            # Outside file that a malicious manifest tries to delete
            victim = os.path.join(wb_dir, "Modules", "precious_outside.txt")
            with open(victim, "w", encoding="utf-8") as f:
                f.write("must survive")

            subprocess.run([inst_bin, "install", "--warband", wb_dir, "--package", pkg, "--version", "1.0.0"],
                           check=True, capture_output=True, text=True)
            mod_dir = os.path.join(wb_dir, "Modules", "CalradiaOnline")
            manifest = os.path.join(mod_dir, "install_manifest.json")
            with open(manifest, "r", encoding="utf-8") as f:
                tampered = f.read().replace('"files": [', '"files": [\n    {"path": "../precious_outside.txt", "sha256": "00"},', 1)
            with open(manifest, "w", encoding="utf-8") as f:
                f.write(tampered)

            # Uninstall must skip the traversal entry
            subprocess.run([inst_bin, "uninstall", "--warband", wb_dir], check=True, capture_output=True, text=True)
            self.assertTrue(os.path.isfile(victim), "traversal entry deleted a file outside the mod folder!")

            # 'install' over an existing (manifest-bearing) install must succeed as clean update
            subprocess.run([inst_bin, "install", "--warband", wb_dir, "--package", pkg, "--version", "1.0.0"],
                           check=True, capture_output=True, text=True)
            res = subprocess.run([inst_bin, "install", "--warband", wb_dir, "--package", pkg, "--version", "1.0.1"],
                                 capture_output=True, text=True)
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertIn("clean update", res.stdout)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
