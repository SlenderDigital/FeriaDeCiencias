"""Unit and integration tests for records_server."""

from __future__ import annotations

import http.client
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest

RECORDS_SERVER_DIR = Path(__file__).resolve().parent.parent
REPO_ROOT = RECORDS_SERVER_DIR.parent
if str(RECORDS_SERVER_DIR) not in sys.path:
    sys.path.insert(0, str(RECORDS_SERVER_DIR))

from leaderboard import (  # noqa: E402
    build_snapshot,
    detect_record_updates,
    format_personal_stats,
    format_run_score,
    get_best_summary,
    get_boss_phase_for_time,
    get_leaderboard,
    global_tier_rank,
    sync_profiles,
)
from server import create_server  # noqa: E402
from tres_parser import TresParseError, parse_tres_file, parse_tres_text  # noqa: E402
from watcher import SaveWatcher, resolve_active_save_path  # noqa: E402


SAMPLE_TRES = """\
[gd_resource type="Resource" script_class="SaveData" format=3]

[ext_resource type="Script" path="res://scripts/data/save_data.gd" id="1"]

[resource]
script = ExtResource("1")
player_name = "Polenta"
records = {
1: {
"completed": false,
"time": 28.66666666666632
},
3: {
"completed": false,
"time": 100.31666666666226
}
}
player_profiles = {
"player": {
"display_name": "PLAYER",
"records": {
3: {
"completed": false,
"time": 107.6833333333285
}
}
},
"polenta": {
"display_name": "Polenta",
"records": {
1: {
"completed": false,
"time": 28.66666666666632
},
3: {
"completed": false,
"time": 100.31666666666226
}
}
}
}
"""


class TresParserTests(unittest.TestCase):
    def test_parses_repo_save_data_file(self) -> None:
        repo_save = REPO_ROOT / "juego" / "data" / "save_data.tres"
        self.assertTrue(repo_save.is_file(), f"Expected fixture at {repo_save}")
        parsed = parse_tres_file(repo_save)
        self.assertIn("player_name", parsed)
        self.assertIsInstance(parsed["records"], dict)
        self.assertIsInstance(parsed["player_profiles"], dict)

    def test_parses_types_escapes_comments_and_typed_containers(self) -> None:
        raw = """\
[gd_resource type="Resource" script_class="SaveData" format=3]
[ext_resource type="Script" path="res://scripts/data/save_data.gd" id="1"]

[resource]
; comment before properties
script = ExtResource("1")
player_name = "Fa\\"cu \\u00d1"
records = Dictionary[int, Dictionary]({
1: { "completed": true, "time": 45.0, },
})
player_profiles = {
"fa\\"cu \\u00d1": {
"display_name": "Fa\\"cu \\u00d1",
"records": {
0: { "completed": false, "time": 1.25e1 },
1: { "completed": true, "time": 45.0 }
}
}
}
tags = Array[String](["a", "b"])
extra_vec = Vector2(10, -20.5)
"""
        parsed = parse_tres_text(raw)
        self.assertEqual(parsed["player_name"], 'Fa"cu Ñ')
        self.assertEqual(parsed["records"][1], {"completed": True, "time": 45.0})
        profile = parsed["player_profiles"]['fa"cu Ñ']
        self.assertEqual(profile["records"][0]["time"], 12.5)
        self.assertTrue(profile["records"][1]["completed"])

    def test_defaults_when_optional_properties_omitted(self) -> None:
        raw = """\
[gd_resource type="Resource" format=3]
[resource]
script = ExtResource("1")
"""
        parsed = parse_tres_text(raw)
        self.assertEqual(parsed["player_name"], "PLAYER")
        self.assertEqual(parsed["records"], {})
        self.assertEqual(parsed["player_profiles"], {})

    def test_rejects_empty_and_malformed_tres(self) -> None:
        for bad in (
            "",
            "   \n",
            '[gd_resource type="Resource" format=3]\n',
            '[resource]\nplayer_name = "unterminated',
            '[resource]\nrecords = {\n1: {\n',
            '[resource]\nrecords = ',
        ):
            with self.subTest(bad=bad):
                with self.assertRaises(TresParseError):
                    parse_tres_text(bad)


class LeaderboardParityTests(unittest.TestCase):
    def test_global_tier_hierarchy_and_tie_breakers(self) -> None:
        # Exact SaveData parity:
        # Boss completed(100) > Hard comp(60) > Hard inc(50) > Normal comp(40)
        # > Normal inc(30) > Easy comp(20) > Boss inc(15) > Easy inc(10)
        self.assertEqual(global_tier_rank(3, True), 100)
        self.assertEqual(global_tier_rank(2, True), 60)
        self.assertEqual(global_tier_rank(2, False), 50)
        self.assertEqual(global_tier_rank(1, True), 40)
        self.assertEqual(global_tier_rank(1, False), 30)
        self.assertEqual(global_tier_rank(0, True), 20)
        self.assertEqual(global_tier_rank(3, False), 15)
        self.assertEqual(global_tier_rank(0, False), 10)

        parsed = {
            "player_name": "Bravo",
            "player_profiles": {
                "bosswin": {"display_name": "BossWin", "records": {3: {"time": 120.0, "completed": True}}},
                "hardwin": {"display_name": "HardWin", "records": {2: {"time": 45.0, "completed": True}}},
                "hardtry": {"display_name": "HardTry", "records": {2: {"time": 20.0, "completed": False}}},
                "normwin": {"display_name": "NormWin", "records": {1: {"time": 45.0, "completed": True}}},
                "normtry": {"display_name": "NormTry", "records": {1: {"time": 30.0, "completed": False}}},
                "easywin": {"display_name": "EasyWin", "records": {0: {"time": 45.0, "completed": True}}},
                "bosstry": {"display_name": "BossTry", "records": {3: {"time": 110.0, "completed": False}}},
                "bravo": {"display_name": "Bravo", "records": {0: {"time": 10.00001, "completed": False}}},
                "alpha": {"display_name": "Alpha", "records": {0: {"time": 10.00002, "completed": False}}},
            },
        }
        player_name, profiles = sync_profiles(parsed)
        board = get_leaderboard(profiles, player_name, -1)
        ordered_names = [row["player_name"] for row in board]
        self.assertEqual(
            ordered_names,
            [
                "BossWin",
                "HardWin",
                "HardTry",
                "NormWin",
                "NormTry",
                "EasyWin",
                "BossTry",
                "Alpha",
                "Bravo",
            ],
        )
        self.assertTrue(board[-1]["is_current"])
        self.assertEqual([row["rank"] for row in board], list(range(1, 10)))

    def test_legacy_single_player_migration(self) -> None:
        parsed = {
            "player_name": "  LegacyHeroExceedingTwelve  ",
            "records": {
                1: {"time": 45.0, "completed": True},
            },
            "player_profiles": {},
        }
        snap, _ = build_snapshot(parsed, "/tmp/save_data.tres", True, 1.0)
        self.assertEqual(snap["player_name"], "LegacyHeroEx")
        self.assertEqual(snap["total_players"], 1)
        self.assertEqual(snap["player_ranks"]["-1"], 1)
        self.assertEqual(snap["best_summary"], "BEST  NORMAL  -  COMPLETED")

    def test_unplayed_active_player_sees_empty_personal_stats(self) -> None:
        parsed = parse_tres_text(SAMPLE_TRES)
        parsed["player_name"] = "NewComer"
        snap, _ = build_snapshot(parsed, "/tmp/save_data.tres", True, 1.0)
        self.assertEqual(snap["best_summary"], "No runs yet")
        self.assertEqual(snap["player_ranks"]["-1"], 0)
        self.assertEqual(snap["personal_stats"]["0"], "EASY:  No runs recorded")
        self.assertEqual(snap["personal_stats"]["3"], "BOSS:  No runs recorded")

    def test_boss_phase_and_formatting_parity(self) -> None:
        self.assertEqual(get_boss_phase_for_time(0.0, False), 1)
        self.assertEqual(get_boss_phase_for_time(14.9, False), 1)
        self.assertEqual(get_boss_phase_for_time(15.0, False), 2)
        self.assertEqual(get_boss_phase_for_time(100.3166, False), 7)
        self.assertEqual(get_boss_phase_for_time(107.6833, False), 8)
        self.assertEqual(get_boss_phase_for_time(150.0, False), 8)
        self.assertEqual(get_boss_phase_for_time(10.0, True), 8)

        self.assertEqual(format_run_score(3, 120.0, True, False), "COMPLETED (8/8) ★")
        self.assertEqual(format_run_score(3, 120.0, True, True), "8/8 PHASES ★")
        self.assertEqual(format_run_score(3, 100.3166, False, False), "Phase 7/8 (100.3s)")
        self.assertEqual(format_run_score(3, 100.3166, False, True), "P7/8 (100.3s)")
        self.assertEqual(format_run_score(2, 45.0, True, False), "COMPLETED (45.0s) ★")
        self.assertEqual(format_run_score(2, 45.0, True, True), "COMPLETED ★")
        self.assertEqual(format_run_score(1, 28.666, False, False), "Survived 28.7s")
        self.assertEqual(format_run_score(1, 28.666, False, True), "28.7s")

        rec_map = {
            1: {"time": 28.666, "completed": False},
            3: {"time": 100.3166, "completed": False},
        }
        self.assertEqual(get_best_summary(rec_map), "BEST  NORMAL  -  28.7s")
        stats = format_personal_stats(rec_map)
        self.assertEqual(stats["0"], "EASY:  No runs recorded")
        self.assertEqual(stats["1"], "NORMAL:  Survived 28.7s")
        self.assertEqual(stats["3"], "BOSS:  Phase 7/8 (100.3s)")

    def test_detect_record_updates(self) -> None:
        prev = {
            "ana": {"display_name": "Ana", "records": {1: {"time": 20.0, "completed": False}}},
        }
        curr_same = {
            "ana": {"display_name": "Ana", "records": {1: {"time": 20.0, "completed": False}}},
        }
        self.assertEqual(detect_record_updates(prev, curr_same), [])

        curr_improved = {
            "ana": {"display_name": "Ana", "records": {1: {"time": 45.0, "completed": True}}},
            "bob": {"display_name": "Bob", "records": {0: {"time": 12.0, "completed": False}}},
        }
        updates = detect_record_updates(prev, curr_improved)
        self.assertEqual({u["key"] for u in updates}, {"ana", "bob"})


class WatcherAndHttpIntegrationTests(unittest.TestCase):
    def test_resolve_active_save_path_explicit_and_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "missing.tres"
            resolved, exists = resolve_active_save_path(target, Path(tmp))
            self.assertEqual(resolved, target)
            self.assertFalse(exists)

    def test_watcher_retains_last_valid_snapshot_on_corrupt_write(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            save_path = Path(tmp) / "save_data.tres"
            save_path.write_text(SAMPLE_TRES, encoding="utf-8")

            watcher = SaveWatcher(
                explicit_save_file=save_path,
                poll_interval=0.05,
                max_parse_retries=1,
                retry_delay=0.01,
            )
            self.addCleanup(watcher.stop)
            self.assertEqual(watcher.get_snapshot()["total_players"], 2)

            # Corrupt file temporarily: watcher must keep previous valid snapshot.
            save_path.write_text("[resource]\nrecords = { broken", encoding="utf-8")
            os.utime(save_path, None)
            watcher._poll_once(initial=False)
            self.assertEqual(watcher.get_snapshot()["total_players"], 2)

            # Restore valid file with a 3rd player and verify recovery.
            updated = SAMPLE_TRES.replace(
                'player_profiles = {',
                'player_profiles = {\n"carlos": {\n"display_name": "Carlos",\n"records": {2: {"completed": true, "time": 45.0}}\n},',
            )
            save_path.write_text(updated, encoding="utf-8")
            watcher._poll_once(initial=False)
            snap = watcher.get_snapshot()
            self.assertEqual(snap["total_players"], 3)
            self.assertEqual(snap["leaderboards"]["-1"][0]["player_name"], "Carlos")

    def test_http_endpoints_read_only_security_and_live_sse(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            save_path = Path(tmp) / "save_data.tres"
            save_path.write_text(SAMPLE_TRES, encoding="utf-8")

            watcher = SaveWatcher(
                explicit_save_file=save_path,
                poll_interval=0.05,
                max_parse_retries=2,
                retry_delay=0.01,
            )
            watcher.start()
            self.addCleanup(watcher.stop)

            srv = create_server(
                "127.0.0.1",
                0,
                watcher=watcher,
                static_dir=RECORDS_SERVER_DIR / "static",
                quiet=True,
                keepalive_interval=1.0,
            )
            thread = threading.Thread(target=srv.serve_forever, daemon=True)
            thread.start()

            def _cleanup_server() -> None:
                srv.shutdown()
                srv.server_close()
                thread.join(timeout=2.0)

            self.addCleanup(_cleanup_server)

            port = srv.server_address[1]

            # 1. GET / serves Main Menu Records HTML
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=3.0)
            self.addCleanup(conn.close)
            conn.request("GET", "/")
            resp = conn.getresponse()
            html = resp.read().decode("utf-8")
            self.assertEqual(resp.status, 200)
            self.assertIn("RANKING &amp; RECORDS", html)
            for label in ("GLOBAL", "EASY", "NORMAL", "HARD", "BOSS"):
                self.assertIn(label, html)

            # 2. Static CSS & JS
            for asset, expected_ct in (
                ("/static/styles.css", "text/css"),
                ("/static/app.js", "application/javascript"),
            ):
                conn.request("GET", asset)
                r = conn.getresponse()
                r.read()
                self.assertEqual(r.status, 200)
                self.assertIn(expected_ct, r.getheader("Content-Type", ""))

            # 3. Path traversal protection (both raw .. and URL-encoded %2e%2e)
            for bad_path in ("/static/../server.py", "/static/%2e%2e/server.py", "/static/missing.css"):
                conn.request("GET", bad_path)
                r = conn.getresponse()
                r.read()
                self.assertEqual(r.status, 404, f"Expected 404 for {bad_path}")

            # 4. Strictly read-only: non-GET/HEAD rejected with 405
            for method in ("POST", "PUT", "PATCH", "DELETE", "OPTIONS"):
                conn.request(method, "/api/records", body=b"{}")
                r = conn.getresponse()
                r.read()
                self.assertEqual(r.status, 405, f"Expected 405 for {method}")
                self.assertEqual(r.getheader("Allow"), "GET, HEAD")

            # 5. GET /api/records & /health
            conn.request("GET", "/api/records")
            r = conn.getresponse()
            api_data = json.loads(r.read().decode("utf-8"))
            self.assertEqual(r.status, 200)
            self.assertEqual(api_data["player_name"], "Polenta")
            self.assertEqual(api_data["total_players"], 2)

            conn.request("GET", "/health")
            r = conn.getresponse()
            health = json.loads(r.read().decode("utf-8"))
            self.assertEqual(r.status, 200)
            self.assertTrue(health["read_only"])
            self.assertTrue(health["source_exists"])

            # 6. Live SSE stream receives initial snapshot + disk update push
            sse_conn = http.client.HTTPConnection("127.0.0.1", port, timeout=4.0)
            self.addCleanup(sse_conn.close)
            sse_conn.request("GET", "/events")
            sse_resp = sse_conn.getresponse()
            self.assertEqual(sse_resp.status, 200)
            self.assertIn("text/event-stream", sse_resp.getheader("Content-Type", ""))

            def _read_next_records_event() -> dict:
                deadline = time.monotonic() + 3.5
                event_name = ""
                data_lines: list[str] = []
                while time.monotonic() < deadline:
                    raw_line = sse_resp.fp.readline()
                    if not raw_line:
                        break
                    line = raw_line.decode("utf-8").rstrip("\r\n")
                    if line.startswith(":"):
                        continue
                    if line == "":
                        if event_name == "records" and data_lines:
                            return json.loads("\n".join(data_lines))
                        event_name = ""
                        data_lines = []
                    elif line.startswith("event:"):
                        event_name = line.split(":", 1)[1].strip()
                    elif line.startswith("data:"):
                        data_lines.append(line.split(":", 1)[1].lstrip())
                self.fail("Timed out waiting for SSE records event")

            first_ev = _read_next_records_event()
            self.assertEqual(first_ev["total_players"], 2)
            self.assertEqual(first_ev["recent_updates"], [])

            # Modify save_data.tres on disk to trigger live SSE update
            new_tres = SAMPLE_TRES.replace(
                'player_profiles = {',
                'player_profiles = {\n"winner": {\n"display_name": "Winner",\n"records": {3: {"completed": true, "time": 120.0}}\n},',
            )
            save_path.write_text(new_tres, encoding="utf-8")

            second_ev = _read_next_records_event()
            self.assertEqual(second_ev["total_players"], 3)
            self.assertEqual(second_ev["leaderboards"]["-1"][0]["player_name"], "Winner")
            self.assertTrue(any(u["key"] == "winner" for u in second_ev["recent_updates"]))


if __name__ == "__main__":
    unittest.main()
