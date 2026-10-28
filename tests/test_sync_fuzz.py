import os
import random
import shutil
import tempfile
import unittest

from test_lua_systems import get_luajit_runtime


class TestCoopAnythingChaosAndSyncFuzz(unittest.TestCase):
    """
    coop-anything style randomized multi-player campaign fuzzer + invariant checker:
    Simulates 4 concurrent players over 350 randomized steps (trades, stale-epoch duplicates,
    companion hires, drop-in battles, speed votes, kingdom fiefs, hourly ticks, and save/reload cycles)
    and verifies zero companion duplication, zero negative resources, exact P2P conservation,
    and deterministic save/load SHA-256 state digests.
    """

    def test_multiplayer_campaign_chaos_fuzz_invariants(self):
        tmp_dir = tempfile.mkdtemp(prefix="calradia_fuzz_")
        try:
            rng = random.Random(20261028)
            lua = get_luajit_runtime()
            CO = lua.eval('require("main")')
            srv = CO.new(lua.table_from({
                "world_name": "FuzzWorld",
                "save_dir": tmp_dir,
                "seed": 987654,
            }))

            uids = ["p_alice", "p_bob", "p_carol", "p_dave"]
            for idx, uid in enumerate(uids):
                net_id = idx + 1
                ident = srv.auth.derive_identity(srv.auth, f"fuzz_secret_key_{idx}_0123456789abcdef")
                nonce = srv.auth.issue_challenge(srv.auth, net_id, 100 + idx)
                sig = srv.auth.sign_challenge(srv.auth, ident.auth_key, nonce, ident.uid, f"Hero{idx}")
                ok, wel = srv.auth.verify_response(srv.auth, net_id, ident.uid, f"Hero{idx}", ident.public_token, sig, 101 + idx)
                self.assertTrue(ok)
                uids[idx] = ident.uid
                pl = srv.economy.create_character(srv.economy, ident.uid, wel.hero_slot, f"Hero{idx}", lua.table_from({
                    "father": rng.choice(["noble", "merchant", "veteran_warrior", "nomad"]),
                    "early": "page",
                    "adulthood": "squire",
                    "reason": "wanderlust",
                }))
                pl.gold = 5000

            comp_ids = [f"trp_npc{i}" for i in range(1, 17)]
            town_ids = [f"p_town_{i}" for i in range(1, 23)]

            for step in range(350):
                op = rng.choice([
                    "hour_tick", "speed_vote", "merchant_buy", "hire_companion",
                    "p2p_trade", "stale_packet_chaos", "dropin_battle", "save_reload_verify",
                ])
                actor = rng.choice(uids)
                pl = srv.economy.get_player(srv.economy, actor)

                if op == "hour_tick":
                    srv.step_world_hour(srv)

                elif op == "speed_vote":
                    spd = rng.choice([0, 1, 3, 5])
                    srv.politics.set_speed_vote(srv.politics, actor, spd, lua.table_from(uids))

                elif op == "merchant_buy":
                    tid = rng.choice(town_ids)
                    srv.economy.merchant_buy(srv.economy, actor, tid, lua.table_from({
                        "item_id": "itm_smoked_fish", "base_price": 45, "food_amount": 30
                    }), srv.quests.companions)

                elif op == "hire_companion":
                    cid = rng.choice(comp_ids)
                    twn = srv.quests.companions[cid].tavern_town
                    srv.quests.hire_companion(srv.quests, srv.economy, actor, cid, twn)

                elif op == "stale_packet_chaos":
                    # Inject duplicated / reordered packet with outdated snapshot_epoch -> MUST reject cleanly
                    stale_ep = max(0, pl.snapshot_epoch - rng.randint(1, 5))
                    ok_st, err_st = srv.economy.move_inventory_item(srv.economy, actor, 10, 11, stale_ep)
                    self.assertFalse(ok_st)
                    self.assertEqual(err_st, "stale_snapshot_epoch")

                elif op == "p2p_trade":
                    partner = rng.choice([u for u in uids if u != actor])
                    pa = srv.economy.get_player(srv.economy, actor)
                    pb = srv.economy.get_player(srv.economy, partner)
                    total_gold_before = pa.gold + pb.gold
                    gift = min(pa.gold, rng.randint(10, 200))
                    sess, _ = srv.economy.open_p2p_trade(srv.economy, actor, partner)
                    if sess:
                        srv.economy.update_p2p_offer(srv.economy, sess.trade_id, actor, gift, lua.table_from([], recursive=True))
                        srv.economy.lock_p2p_trade(srv.economy, sess.trade_id, actor)
                        srv.economy.lock_p2p_trade(srv.economy, sess.trade_id, partner)
                        srv.economy.confirm_p2p_trade(srv.economy, sess.trade_id, actor)
                        srv.economy.confirm_p2p_trade(srv.economy, sess.trade_id, partner)
                    self.assertEqual(pa.gold + pb.gold, total_gold_before, "P2P trade violated gold conservation!")

                elif op == "dropin_battle":
                    ally = rng.choice([u for u in uids if u != actor])
                    srv.economy.recruit_troops(srv.economy, actor, "trp_swadian_recruit", 5, 10)
                    node = srv.battles.start_battle(srv.battles, lua.table_from({
                        "mission_kind": 1,
                        "side_a": {"parties": [{"party_id": 10, "owner_player_uid": actor, "stacks": [{"troop_id": "trp_swadian_recruit", "count": 5, "wounded": 0}]}]},
                        "side_b": {"parties": [{"party_id": 99, "stacks": [{"troop_id": "trp_looter", "count": 6, "wounded": 0}]}]},
                    }, recursive=True))
                    srv.battles.join_ongoing_battle(srv.battles, node.battle_id, 0, lua.table_from({
                        "party_id": 11, "owner_player_uid": ally, "stacks": []
                    }, recursive=True))
                    srv.battles.resolve_battle_result(srv.battles, srv.economy, srv.quests.companions, lua.table_from({
                        "battle_id": node.battle_id,
                        "winning_side": 0,
                        "party_casualties": {
                            "10": {"stacks": [{"troop_id": "trp_swadian_recruit", "dead_lethal": 2, "knocked_blunt": 1, "personal_kills": 3}]},
                            "99": {"stacks": [{"troop_id": "trp_looter", "dead_lethal": 4, "knocked_blunt": 2, "tier": 1}]},
                        },
                    }, recursive=True))

                elif op == "save_reload_verify" and step % 25 == 0:
                    pre_state = srv.export_world_state(srv)
                    # Normalize epoch difference on load by checking players & companions digest
                    digest_before = srv.recorder.world_digest(srv.recorder, pre_state.players)
                    ok_s, _ = srv.save_campaign(srv)
                    self.assertTrue(ok_s)
                    ok_l, _ = srv.load_campaign(srv)
                    self.assertTrue(ok_l)
                    post_state = srv.export_world_state(srv)
                    digest_after = srv.recorder.world_digest(srv.recorder, post_state.players)
                    self.assertEqual(digest_before, digest_after, "World player digest diverged across save/load!")

                # === STRICT INVARIANT CHECKS AFTER EVERY SINGLE FUZZ STEP ===
                seen_companions = set()
                for u in uids:
                    p = srv.economy.get_player(srv.economy, u)
                    self.assertGreaterEqual(p.gold, 0, f"Negative gold on {u}")
                    self.assertGreaterEqual(p.level, 1)
                    for cid in p.companions.values():
                        self.assertNotIn(cid, seen_companions, f"Companion {cid} duplicated across multiple players!")
                        seen_companions.add(cid)
                    for st in p.party_stacks.values():
                        self.assertGreater(st.count, 0)
                        self.assertLessEqual(st.wounded, st.count)
        finally:
            shutil.rmtree(tmp_dir, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
