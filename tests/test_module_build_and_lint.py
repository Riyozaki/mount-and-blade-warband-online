import ast
import glob
import os
import sys
import unittest

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MS_DIR = os.path.join(REPO_ROOT, "module_system")
if MS_DIR not in sys.path:
    sys.path.insert(0, MS_DIR)

import build_module  # noqa: E402


class TestModuleBuildAndStaticLint(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build_summary = build_module.build_all(MS_DIR, sync_lua_msfiles=True)

    def test_01_all_txt_and_msfiles_exported(self):
        self.assertGreaterEqual(self.build_summary["txt_count"], 29)
        required_txt = {
            "actions.txt", "conversation.txt", "factions.txt", "item_kinds1.txt",
            "menus.txt", "mission_templates.txt", "parties.txt", "party_templates.txt",
            "presentations.txt", "quests.txt", "scripts.txt", "simple_triggers.txt",
            "strings.txt", "triggers.txt", "troops.txt",
        }
        self.assertTrue(required_txt.issubset(set(self.build_summary["txt_files"])))

        msfiles_dir = os.path.join(REPO_ROOT, "lua", "msfiles")
        self.assertTrue(os.path.isfile(os.path.join(msfiles_dir, "ID_scripts.py")))
        self.assertTrue(os.path.isfile(os.path.join(msfiles_dir, "ID_troops.py")))
        self.assertTrue(os.path.isfile(os.path.join(msfiles_dir, "ID_factions.py")))
        self.assertTrue(os.path.isfile(os.path.join(msfiles_dir, "header_operations.py")))

    def test_02_coop_pools_exist_without_shifting_native_ids(self):
        import ID_factions
        import ID_presentations
        import ID_scripts
        import ID_troops

        # Native factions remain at exact vanilla indices
        self.assertEqual(ID_factions.fac_commoners, 1)
        self.assertEqual(ID_factions.fac_kingdom_1, 15)

        # 16 Player Warbands + 16 Sovereign Player Kingdoms exist
        for i in range(16):
            self.assertTrue(hasattr(ID_factions, f"fac_coop_player_{i}"))
            self.assertTrue(hasattr(ID_factions, f"fac_coop_kingdom_{i}"))

        # 32 Persistent Hero Profiles + 4 Specialist Officers exist
        for i in range(32):
            self.assertTrue(hasattr(ID_troops, f"trp_coop_hero_{i}"))
        for role in ("surgeon", "engineer", "scout", "quartermaster"):
            self.assertTrue(hasattr(ID_troops, f"trp_coop_officer_{role}"))

        # Co-op presentations & scripts exist
        self.assertTrue(hasattr(ID_presentations, "prsnt_coop_campaign_hud"))
        self.assertTrue(hasattr(ID_presentations, "prsnt_coop_p2p_trade"))
        self.assertTrue(hasattr(ID_scripts, "script_coop_receive_composite_message"))
        self.assertTrue(hasattr(ID_scripts, "script_coop_bind_player_to_hero_party"))

    def test_03_try_begin_try_end_balance_across_all_scripts(self):
        """Static block-nesting verifier (catches bugs like upstream Native-Coop wse_window_opened!)."""
        import header_operations as hop
        import module_scripts

        open_ops = {
            hop.try_begin,
            hop.try_for_range,
            hop.try_for_range_backwards,
            hop.try_for_parties,
            hop.try_for_agents,
            hop.try_for_players,
            hop.try_for_prop_instances,
            hop.try_for_dict_keys,
        }

        unbalanced = []
        for entry in module_scripts.scripts:
            name = entry[0]
            body = entry[1] if isinstance(entry[1], list) else entry[2]
            depth = 0
            for stmt in body:
                op = stmt[0] if isinstance(stmt, tuple) else stmt
                base_op = op & 0xFFFF
                if base_op in open_ops:
                    depth += 1
                elif base_op == hop.else_try:
                    if depth <= 0:
                        unbalanced.append((name, "else_try_at_zero_depth"))
                elif base_op == hop.try_end:
                    depth -= 1
                    if depth < 0:
                        unbalanced.append((name, "extra_try_end"))
            if depth != 0:
                unbalanced.append((name, f"unclosed_depth_{depth}"))

        self.assertEqual(unbalanced, [], f"Unbalanced try_begin/try_end blocks found: {unbalanced}")

    def test_04_wse2_composite_message_bitwidth_symmetry(self):
        """
        Proves every WSE2 composite message sender in coop_network.py uses the EXACT same
        bit-width sequence (`int:bits` / `str`) as its corresponding receiver in coop_receive_composite_message!
        """
        from coop import coop_constants as cc
        from coop import coop_network as cn

        import header_operations as hop

        scripts_by_name = {name: body for name, body in cn.coop_network_scripts}

        def extract_put_schema(script_name):
            body = scripts_by_name[script_name]
            fields = []
            channel = None
            for stmt in body:
                if not isinstance(stmt, tuple):
                    continue
                op = stmt[0]
                if op == hop.multiplayer_message_put_int:
                    fields.append(("int", stmt[3]))
                elif op == hop.multiplayer_message_put_string:
                    fields.append(("str", None))
                elif op == hop.multiplayer_send_composite_message_to_player:
                    channel = stmt[2]
                elif op == hop.multiplayer_send_composite_message_to_server:
                    channel = stmt[1]
            # First two fields are always (sub_event:8, epoch:16)
            sub_event_val = body[[s[0] for s in body if isinstance(s, tuple)].index(hop.multiplayer_message_put_int)][2]
            for stmt in body:
                if isinstance(stmt, tuple) and stmt[0] == hop.multiplayer_message_put_int:
                    sub_event_val = stmt[2]
                    break
            return (channel, sub_event_val), fields

        sent_schemas = {}
        for sname in scripts_by_name:
            if sname.startswith("coop_sv_send_") or sname.startswith("coop_cl_send_") or sname.startswith("coop_sv_broadcast_"):
                key, schema = extract_put_schema(sname)
                sent_schemas[key] = (sname, schema)

        self.assertGreaterEqual(len(sent_schemas), 8)

        # Parse receiver branches in coop_receive_composite_message
        rx_body = scripts_by_name["coop_receive_composite_message"]
        cur_chan = None
        cur_sub = None
        rx_schemas = {}
        for stmt in rx_body:
            if not isinstance(stmt, tuple):
                continue
            op = stmt[0]
            if op == hop.eq and stmt[1] == ":event_no":
                cur_chan = stmt[2]
                cur_sub = None
            elif op == hop.eq and stmt[1] == ":sub_event":
                cur_sub = stmt[2]
                rx_schemas[(cur_chan, cur_sub)] = [
                    ("int", cc.COOP_BITS_SUB_EVENT),
                    ("int", cc.COOP_BITS_EPOCH),
                ]
            elif cur_chan is not None and cur_sub is not None:
                if op == hop.multiplayer_cur_message_get_int:
                    rx_schemas[(cur_chan, cur_sub)].append(("int", stmt[2]))
                elif op == hop.multiplayer_cur_message_get_string:
                    rx_schemas[(cur_chan, cur_sub)].append(("str", None))

        for key, (sname, tx_fields) in sent_schemas.items():
            self.assertIn(key, rx_schemas, f"Missing receiver branch for {sname} {key}")
            self.assertEqual(
                tx_fields,
                rx_schemas[key],
                f"Bit-width mismatch in {sname} {key}: sent {tx_fields} != received {rx_schemas[key]}",
            )

    def test_05_no_python2_float_division_in_module_sources(self):
        import warnings
        for p in sorted(glob.glob(os.path.join(MS_DIR, "module_*.py"))):
            bn = os.path.basename(p)
            if bn == "module_troops.py":
                continue  # int(x / 10) is explicitly cast to int
            with open(p, "r", encoding="utf-8") as f:
                src = f.read()
            with warnings.catch_warnings():
                warnings.simplefilter("ignore")
                tree = ast.parse(src, p)
            div_lines = [
                n.lineno for n in ast.walk(tree)
                if isinstance(n, ast.BinOp) and isinstance(n.op, ast.Div)
            ]
            self.assertEqual(div_lines, [], f"Raw float '/' division found in {bn} at lines {div_lines}")


if __name__ == "__main__":
    unittest.main()
