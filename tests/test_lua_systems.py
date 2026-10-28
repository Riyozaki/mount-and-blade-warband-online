import os
import shutil
import tempfile
import unittest

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LUA_DIR = os.path.join(REPO_ROOT, "lua")


def get_luajit_runtime():
    try:
        from lupa.luajit21 import LuaRuntime
    except ImportError:
        venv_site = os.path.join(REPO_ROOT, ".venv", "lib")
        for root, dirs, _ in os.walk(venv_site):
            if "site-packages" in dirs:
                import sys
                sys.path.insert(0, os.path.join(root, "site-packages"))
                break
        from lupa.luajit21 import LuaRuntime

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'package.path = "{LUA_DIR}/?.lua;{LUA_DIR}/msfiles/?.lua;" .. package.path')
    return lua


class TestLuaCampaignSystems(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.mkdtemp(prefix="calradia_lua_test_")
        self.lua = get_luajit_runtime()
        self.CO = self.lua.eval('require("main")')
        self.sha = self.lua.eval('require("sha256")')
        self.srv = self.CO.new(self.lua.table_from({
            "world_name": "FriendsSandbox",
            "save_dir": self.tmp_dir,
            "seed": 424242,
        }))

    def tearDown(self):
        shutil.rmtree(self.tmp_dir, ignore_errors=True)

    def test_01_fips_sha256_and_rfc2104_hmac_vectors(self):
        # FIPS 180-4 "abc" vector
        self.assertEqual(
            self.sha.sha256_hex("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        )
        # RFC 4231 Test Case 2 ("Jefe" / "what do ya want for nothing?")
        self.assertEqual(
            self.sha.hmac_sha256_hex("Jefe", "what do ya want for nothing?"),
            "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
        )

    def test_02_steam_free_auth_reconnect_and_impersonation_defense(self):
        id1 = self.srv.auth.derive_identity(self.srv.auth, "secret_alpha_player_one_99999999")
        id2 = self.srv.auth.derive_identity(self.srv.auth, "secret_bravo_player_two_88888888")

        nonce = self.srv.auth.issue_challenge(self.srv.auth, 1, 1000)
        sig1 = self.srv.auth.sign_challenge(self.srv.auth, id1.auth_key, nonce, id1.uid, "Ragnar")
        ok, welcome = self.srv.auth.verify_response(self.srv.auth, 1, id1.uid, "Ragnar", id1.public_token, sig1, 1002)
        self.assertTrue(ok)
        self.assertEqual(welcome.hero_slot, 0)
        self.assertFalse(welcome.reconnect)

        # Attacker trying to hijack Ragnar's nickname or UID with another key MUST be rejected!
        nonce_atk = self.srv.auth.issue_challenge(self.srv.auth, 2, 1005)
        sig_atk_nick = self.srv.auth.sign_challenge(self.srv.auth, id2.auth_key, nonce_atk, id2.uid, "ragnar")
        ok_nick, err_nick = self.srv.auth.verify_response(
            self.srv.auth, 2, id2.uid, "ragnar", id2.public_token, sig_atk_nick, 1006
        )
        self.assertFalse(ok_nick)
        self.assertEqual(err_nick, "nickname_taken_by_another_key")

        nonce_atk2 = self.srv.auth.issue_challenge(self.srv.auth, 2, 1007)
        sig_atk_uid = self.srv.auth.sign_challenge(self.srv.auth, id2.auth_key, nonce_atk2, id1.uid, "Fake")
        ok_uid, err_uid = self.srv.auth.verify_response(
            self.srv.auth, 2, id1.uid, "Fake", id2.public_token, sig_atk_uid, 1008
        )
        self.assertFalse(ok_uid)
        self.assertEqual(err_uid, "impersonation_detected")

        # Disconnect & reconnect restores exact hero_slot = 0!
        self.srv.auth.on_disconnect(self.srv.auth, 1, False, 1010)
        nonce_re = self.srv.auth.issue_challenge(self.srv.auth, 5, 1020)
        sig_re = self.srv.auth.sign_challenge(self.srv.auth, id1.auth_key, nonce_re, id1.uid, "Ragnar")
        ok_re, wel_re = self.srv.auth.verify_response(self.srv.auth, 5, id1.uid, "Ragnar", id1.public_token, sig_re, 1021)
        self.assertTrue(ok_re)
        self.assertEqual(wel_re.hero_slot, 0)
        self.assertTrue(wel_re.reconnect)

    def test_03_character_creation_economy_enterprises_and_atomic_p2p_trade(self):
        eco = self.srv.economy
        p1 = eco.create_character(eco, "u_p1", 0, "HarlausJr", self.lua.table_from({
            "father": "noble", "early": "page", "adulthood": "squire", "reason": "revenge"
        }))
        p2 = eco.create_character(eco, "u_p2", 1, "MerchantYmira", self.lua.table_from({
            "father": "merchant", "early": "shop_assistant", "adulthood": "peddler", "reason": "wealth"
        }))
        self.assertGreater(p2.gold, p1.gold)

        # Epoch-checked inventory move rejects stale epoch!
        ok_stale, err_stale = eco.move_inventory_item(eco, "u_p1", 10, 0, p1.snapshot_epoch - 1)
        self.assertFalse(ok_stale)
        self.assertEqual(err_stale, "stale_snapshot_epoch")

        ok_mv, _ = eco.move_inventory_item(eco, "u_p1", 10, 0, p1.snapshot_epoch)
        self.assertTrue(ok_mv)

        # Buy Dyeworks enterprise in Rivacheg (`p_town_13`)
        p2.gold = 15000
        ok_ent, ent = eco.buy_enterprise(eco, "u_p2", "p_town_13", "dyeworks", 5)
        self.assertTrue(ok_ent)
        self.assertEqual(ent.weekly_profit, 550)

        # Two-Phase Atomic P2P Trade (with anti-scam auto-unlock on offer change!)
        p1.gold = 2000
        sess, err_tr = eco.open_p2p_trade(eco, "u_p1", "u_p2")
        self.assertIsNotNone(sess, err_tr)
        tid = sess.trade_id
        self.assertTrue(eco.update_p2p_offer(eco, tid, "u_p1", 500, self.lua.table_from([], recursive=True))[0])
        self.assertTrue(eco.update_p2p_offer(eco, tid, "u_p2", 0, self.lua.table_from([10], recursive=True))[0])

        self.assertTrue(eco.lock_p2p_trade(eco, tid, "u_p1")[0])
        self.assertTrue(eco.lock_p2p_trade(eco, tid, "u_p2")[0])

        # Scam attempt: u_p1 drops gold from 500 -> 1 after both locked -> MUST reset BOTH locks & confirmations!
        self.assertTrue(eco.update_p2p_offer(eco, tid, "u_p1", 1, self.lua.table_from([], recursive=True))[0])
        ok_premature, err_prem = eco.confirm_p2p_trade(eco, tid, "u_p2")
        self.assertFalse(ok_premature)
        self.assertEqual(err_prem, "both_must_lock_first")

        # Legitimate re-lock & confirm executes atomic swap
        eco.update_p2p_offer(eco, tid, "u_p1", 500, self.lua.table_from([], recursive=True))
        eco.lock_p2p_trade(eco, tid, "u_p1")
        eco.lock_p2p_trade(eco, tid, "u_p2")
        eco.confirm_p2p_trade(eco, tid, "u_p1")
        ok_done, state_done = eco.confirm_p2p_trade(eco, tid, "u_p2")
        self.assertTrue(ok_done)
        self.assertEqual(state_done, "committed")
        self.assertEqual(p1.gold, 1500)

    def test_04_companions_instanced_quests_and_coop_rewards(self):
        eco = self.srv.economy
        qst = self.srv.quests
        eco.create_character(eco, "u_a", 0, "Alice", self.lua.table_from({"father": "nomad"}))
        eco.create_character(eco, "u_b", 1, "Bob", self.lua.table_from({"father": "hunter"}))
        eco.get_player(eco, "u_a").gold = 5000
        eco.get_player(eco, "u_b").gold = 5000

        # Hire Jeremus (`trp_npc12`): strictly unique across entire world!
        jeremus_town = qst.companions["trp_npc12"].tavern_town
        ok1, _ = qst.hire_companion(qst, eco, "u_a", "trp_npc12", jeremus_town)
        self.assertTrue(ok1)
        ok2, err2 = qst.hire_companion(qst, eco, "u_b", "trp_npc12", jeremus_town)
        self.assertFalse(ok2)
        self.assertEqual(err2, "companion_already_hired")

        # Bob can still hire a Specialist Surgeon Officer for his own party!
        ok_spec, spec_off = qst.hire_specialist_officer(qst, eco, "u_b", "surgeon")
        self.assertTrue(ok_spec)
        self.assertEqual(spec_off.skills.surgery, 4)

        # Instanced Quest + Co-op Brotherhood Assist Bonus + Anti-Kill-Steal Guard
        inst, err_q = qst.accept_quest(qst, "u_a", "gm_hunt_bandits", "trp_town_1_master", "pt_forest_bandits", 10)
        self.assertIsNotNone(inst, err_q)

        # Unallied stranger `u_b` cannot steal quest completion before joining as helper!
        ok_steal, err_steal = qst.complete_quest(qst, eco, inst.id, "u_b", self.lua.table_from([]))
        self.assertFalse(ok_steal)
        self.assertEqual(err_steal, "actor_not_authorized_for_quest")

        # Add `u_b` as Brotherhood helper -> both get rewarded!
        qst.add_coop_helper(qst, inst.id, "u_b")
        gold_a_before = eco.get_player(eco, "u_a").gold
        gold_b_before = eco.get_player(eco, "u_b").gold
        ok_fin, payouts = qst.complete_quest(qst, eco, inst.id, "u_b", self.lua.table_from(["u_b"]))
        self.assertTrue(ok_fin)
        self.assertGreater(eco.get_player(eco, "u_a").gold, gold_a_before)
        self.assertGreater(eco.get_player(eco, "u_b").gold, gold_b_before)

    def test_05_live_dropin_battle_surgery_captivity_and_shared_tournament(self):
        eco = self.srv.economy
        btl = self.srv.battles
        qst = self.srv.quests

        p1 = eco.create_character(eco, "u_1", 0, "CommanderOne", self.lua.table_from({"father": "veteran_warrior"}))
        p2 = eco.create_character(eco, "u_2", 1, "ReinforcerTwo", self.lua.table_from({"father": "nomad"}))
        p1.skills.surgery = 8  # High surgery: 25% + 4%*11 = 69% save rate!
        p1.skills.prisoner_management = 3
        eco.recruit_troops(eco, "u_1", "trp_swadian_footman", 20, 0)
        eco.recruit_troops(eco, "u_2", "trp_vaegir_archer", 15, 0)

        node = btl.start_battle(btl, self.lua.table_from({
            "mission_kind": 1,
            "scene_id": "scn_random_scene_plain",
            "side_a": {
                "faction_id": "fac_coop_player_0",
                "parties": [{
                    "party_id": 100,
                    "owner_player_uid": "u_1",
                    "tactics_skill": 4,
                    "stacks": [{"troop_id": "trp_swadian_footman", "count": 20, "wounded": 0}],
                }],
            },
            "side_b": {
                "faction_id": "fac_outlaws",
                "parties": [{
                    "party_id": 500,
                    "tactics_skill": 1,
                    "stacks": [{"troop_id": "trp_sea_raider", "count": 25, "wounded": 0}],
                }],
            },
        }, recursive=True))

        # Friend drops into ongoing 3D battle dynamically!
        ok_join, reinf_ipc = btl.join_ongoing_battle(btl, node.battle_id, 0, self.lua.table_from({
            "party_id": 101,
            "owner_player_uid": "u_2",
            "tactics_skill": 2,
            "stacks": [{"troop_id": "trp_vaegir_archer", "count": 15, "wounded": 0}],
        }, recursive=True))
        self.assertTrue(ok_join)
        self.assertEqual(reinf_ipc.msg_type, "LIVE_REINFORCEMENT")

        # Resolve battle with 10 lethal hits on u_1's footmen -> Surgery saves majority of them as wounded!
        ok_res, summary = btl.resolve_battle_result(btl, eco, qst.companions, self.lua.table_from({
            "battle_id": node.battle_id,
            "winning_side": 0,
            "party_casualties": {
                "100": {"stacks": [{"troop_id": "trp_swadian_footman", "dead_lethal": 10, "knocked_blunt": 2, "personal_kills": 6}]},
                "101": {"stacks": [{"troop_id": "trp_vaegir_archer", "dead_lethal": 2, "knocked_blunt": 1, "personal_kills": 4}]},
                "500": {"stacks": [{"troop_id": "trp_sea_raider", "dead_lethal": 20, "knocked_blunt": 5, "tier": 4}]},
            },
        }, recursive=True))
        self.assertTrue(ok_res)
        self.assertGreater(summary.party_outcomes["100"].wounded_saved, 2)
        self.assertGreater(len(list(p1.prisoners.values())), 0)

        # Shared Multiplayer Tournament with Self-Betting
        p1.gold = 1000
        btl.start_town_tournament(btl, "p_town_6", self.lua.table_from(["u_1", "u_2"]), 14)
        ok_bet, pot = btl.place_tournament_bet(btl, eco, "p_town_6", "u_1", 100)
        self.assertTrue(ok_bet)
        self.assertGreater(pot, 200)
        ok_win, res_t = btl.complete_tournament(btl, eco, "p_town_6", "u_1")
        self.assertTrue(ok_win)
        self.assertEqual(p1.gold, 900 + 200 + pot)

    def test_06_politics_consensus_speed_sieges_and_human_vassal_kingdoms(self):
        eco = self.srv.economy
        pol = self.srv.politics
        k_king = eco.create_character(eco, "u_king", 0, "KingArthur", self.lua.table_from({"father": "noble"}))
        k_vass = eco.create_character(eco, "u_vass", 1, "SirLancelot", self.lua.table_from({"father": "noble"}))
        k_king.gold = 25000

        # Consensus speed: King votes 5x, Lancelot votes 3x -> effective speed is 3x; encounter brakes to 1x!
        online = self.lua.table_from(["u_king", "u_vass"])
        pol.set_speed_vote(pol, "u_king", 5, online)
        _, eff = pol.set_speed_vote(pol, "u_vass", 3, online)
        self.assertEqual(eff, 3)
        braked = pol.interrupt_fast_forward(pol, "u_vass", online)
        self.assertEqual(braked, 1)

        # Register Castle & Siege with high Engineer
        pol.register_fief(pol, "p_castle_1", "castle", "fac_kingdom_1", "trp_knight_1_1", 55)
        sg, err_sg = pol.begin_siege(pol, "p_castle_1", "u_king", 8, "siege_tower", 100)
        self.assertIsNotNone(sg, err_sg)
        self.assertLess(sg.ready_at_hour - 100, 60)  # Engineer reduced 60h tower build time!

        # Found Sovereign Player Kingdom & swear friend `u_vass` as Human Vassal + grant fief!
        kingdom, err_k = pol.found_player_kingdom(pol, eco, "u_king", "Kingdom of Camelot", "p_castle_1", "swadia")
        self.assertIsNotNone(kingdom, err_k)
        self.assertEqual(kingdom.id, "fac_coop_kingdom_0")

        ok_oath, _ = pol.swear_vassal_oath(pol, eco, "u_vass", kingdom.id)
        self.assertTrue(ok_oath)
        self.assertEqual(k_vass.faction_id, "fac_coop_kingdom_0")

        pol.register_fief(pol, "p_village_1", "village", kingdom.id, "u_king", 60)
        ok_grant, _ = pol.grant_fief(pol, eco, "u_king", kingdom.id, "p_village_1", "u_vass")
        self.assertTrue(ok_grant)
        self.assertIsNotNone(k_vass.fiefs["p_village_1"])

        # Royal Marriage between two player characters grants both +3 Right to Rule!
        ok_wed, wed_info = pol.marry(pol, eco, "u_king", "u_vass")
        self.assertTrue(ok_wed)
        self.assertGreaterEqual(wed_info.new_rtr, 8)

    def test_07_atomic_persistence_and_corrupted_save_self_healing(self):
        eco = self.srv.economy
        p = eco.create_character(eco, "u_save", 0, "PersistentHero", self.lua.table_from({"father": "merchant"}))
        p.gold = 7777
        self.srv.cur_hour = 48
        ok1, _ = self.srv.save_campaign(self.srv)
        self.assertTrue(ok1)

        # Save a second time so `.bak1` holds gold=7777, then save gold=9999 as primary
        p.gold = 9999
        self.srv.cur_hour = 72
        ok2, _ = self.srv.save_campaign(self.srv)
        self.assertTrue(ok2)

        # Corrupt primary `world.json` mid-file (simulating power-loss/disk corruption)
        primary_path = os.path.join(self.tmp_dir, "FriendsSandbox", "world.json")
        with open(primary_path, "wb") as f:
            f.write(b'{"corrupted_json": "power_outage_half_write...')

        # Fresh server instance MUST automatically detect SHA/JSON corruption and heal from `.bak1`!
        srv2 = self.CO.new(self.lua.table_from({
            "world_name": "FriendsSandbox",
            "save_dir": self.tmp_dir,
        }))
        loaded_ok, source = srv2.load_campaign(srv2)
        self.assertTrue(loaded_ok)
        self.assertTrue(str(source).endswith(".bak1"), f"Expected recovery from .bak1, got {source}")
        self.assertEqual(srv2.economy.get_player(srv2.economy, "u_save").gold, 7777)


if __name__ == "__main__":
    unittest.main()
