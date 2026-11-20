"""1:1 Python port of Godot's SaveData, GameManager, and MainMenu record formatting."""

from __future__ import annotations

from functools import cmp_to_key
import math
from typing import Any

DEFAULT_PLAYER_NAME = "PLAYER"
MAX_NAME_LENGTH = 12
DIFFICULTY_NAMES = ("Easy", "Normal", "Hard", "Boss")
BOSS_DIFFICULTY = 3
BOSS_TOTAL_PHASES = 8
BOSS_PHASE_DURATION = 15.0
FILTER_IDS = (-1, 0, 1, 2, 3)


def clean_player_name(raw_name: Any, max_length: int = MAX_NAME_LENGTH) -> str:
    """Mirror `SaveData.clean_player_name`: strip whitespace, truncate, fallback to PLAYER."""
    text = "" if raw_name is None else str(raw_name)
    cleaned = text.strip()[:max_length]
    return DEFAULT_PLAYER_NAME if not cleaned else cleaned


def normalize_player_key(raw_name: Any, max_length: int = MAX_NAME_LENGTH) -> str:
    """Mirror `SaveData.normalize_player_key`: lowercase cleaned player name."""
    return clean_player_name(raw_name, max_length).lower()


def _safe_float(val: Any, default: float = 0.0) -> float:
    try:
        num = float(val)
    except (TypeError, ValueError):
        return default
    return num if math.isfinite(num) else default


def normalize_records_dict(source: Any) -> dict[int, dict[str, Any]]:
    """Mirror `SaveData._normalize_records_dict`."""
    if not isinstance(source, dict):
        return {}
    normalized: dict[int, dict[str, Any]] = {}
    for raw_key, raw_val in source.items():
        if not isinstance(raw_val, dict):
            continue
        try:
            diff_key = int(raw_key)
        except (TypeError, ValueError):
            continue
        normalized[diff_key] = {
            "time": _safe_float(raw_val.get("time", 0.0), 0.0),
            "completed": bool(raw_val.get("completed", False)),
        }
    return normalized


def sync_profiles(parsed: dict[str, Any]) -> tuple[str, dict[str, dict[str, Any]]]:
    """Mirror `SaveData.sync_active_profile` including legacy single-player migration."""
    player_name = clean_player_name(parsed.get("player_name", DEFAULT_PLAYER_NAME), MAX_NAME_LENGTH)
    active_key = normalize_player_key(player_name, MAX_NAME_LENGTH)

    raw_profiles = parsed.get("player_profiles")
    raw_records = parsed.get("records")
    profiles: dict[str, dict[str, Any]] = {}

    if isinstance(raw_profiles, dict):
        for raw_key, raw_profile in raw_profiles.items():
            if not isinstance(raw_profile, dict):
                continue
            key = str(raw_key)
            display_name = clean_player_name(
                raw_profile.get("display_name", key.upper()),
                MAX_NAME_LENGTH,
            )
            rec_map = normalize_records_dict(raw_profile.get("records", {}))
            profiles[key] = {
                "display_name": display_name,
                "records": rec_map,
            }

    if not raw_profiles:
        migrated = normalize_records_dict(raw_records)
        if migrated:
            profiles[active_key] = {
                "display_name": player_name,
                "records": migrated,
            }
            return player_name, profiles

    if active_key in profiles:
        profiles[active_key]["display_name"] = player_name

    return player_name, profiles


def get_difficulty_name(difficulty: int) -> str:
    """Mirror `GameManager.get_difficulty_name`."""
    clamped = max(0, min(int(difficulty), len(DIFFICULTY_NAMES) - 1))
    return DIFFICULTY_NAMES[clamped]


def get_boss_phase_for_time(time_survived: float, completed: bool = False) -> int:
    """Mirror `GameManager.get_boss_phase_for_time`."""
    if completed:
        return BOSS_TOTAL_PHASES
    phase = int(math.floor(max(time_survived, 0.0) / BOSS_PHASE_DURATION)) + 1
    return max(1, min(phase, BOSS_TOTAL_PHASES))


def global_tier_rank(difficulty: int, completed: bool) -> int:
    """Mirror `SaveData._global_tier_rank`."""
    if difficulty >= BOSS_DIFFICULTY:
        return 100 if completed else 15
    clamped_std = max(0, min(difficulty, 2))
    return (clamped_std + 1) * 20 + (0 if completed else -10)


def select_best_global_difficulty(rec_map: dict[int, dict[str, Any]]) -> int:
    """Mirror `SaveData._select_best_global_difficulty`."""
    best_diff = -1
    best_rank = -1
    for diff, rec in rec_map.items():
        tier_rank = global_tier_rank(diff, bool(rec.get("completed", False)))
        if tier_rank > best_rank or (tier_rank == best_rank and diff > best_diff):
            best_rank = tier_rank
            best_diff = diff
    return best_diff


def format_run_score(
    difficulty: int,
    time_survived: float,
    completed: bool,
    compact: bool = False,
) -> str:
    """Mirror `GameManager.format_run_score`."""
    if difficulty == BOSS_DIFFICULTY:
        if completed:
            return "8/8 PHASES ★" if compact else "COMPLETED (8/8) ★"
        phase = get_boss_phase_for_time(time_survived, False)
        return (
            f"P{phase}/8 ({time_survived:.1f}s)"
            if compact
            else f"Phase {phase}/8 ({time_survived:.1f}s)"
        )
    if completed:
        return "COMPLETED ★" if compact else "COMPLETED (45.0s) ★"
    return f"{time_survived:.1f}s" if compact else f"Survived {time_survived:.1f}s"


def get_best_summary(rec_map: dict[int, dict[str, Any]]) -> str:
    """Mirror `GameManager.get_best_summary`."""
    if not rec_map:
        return "No runs yet"
    diff = select_best_global_difficulty(rec_map)
    if diff < 0 or diff not in rec_map:
        return "No runs yet"
    rec = rec_map[diff]
    completed = bool(rec.get("completed", False))
    time_val = float(rec.get("time", 0.0))

    if diff == BOSS_DIFFICULTY:
        if completed:
            status = "COMPLETED (8/8)"
        else:
            phase = get_boss_phase_for_time(time_val, False)
            status = f"PHASE {phase}/8 ({time_val:.1f}s)"
    else:
        status = "COMPLETED" if completed else f"{time_val:.1f}s"

    return f"BEST  {get_difficulty_name(diff).upper()}  -  {status}"


def format_personal_stats(rec_map: dict[int, dict[str, Any]]) -> dict[str, str]:
    """Mirror `main_menu._format_record_line` for all four difficulty tiers."""
    stats: dict[str, str] = {}
    for diff_idx in (0, 1, 2, 3):
        diff_upper = get_difficulty_name(diff_idx).upper()
        rec = rec_map.get(diff_idx)
        if not rec:
            stats[str(diff_idx)] = f"{diff_upper}:  No runs recorded"
        else:
            completed = bool(rec.get("completed", False))
            time_val = float(rec.get("time", 0.0))
            formatted = format_run_score(diff_idx, time_val, completed, compact=False)
            stats[str(diff_idx)] = f"{diff_upper}:  {formatted}"
    return stats


def _get_active_player_records(
    player_name: str,
    profiles: dict[str, dict[str, Any]],
) -> dict[int, dict[str, Any]]:
    """Mirror `SaveData.get_player_records` for the active player."""
    active_key = normalize_player_key(player_name, MAX_NAME_LENGTH)
    profile = profiles.get(active_key)
    if profile is None:
        return {}
    return profile.get("records", {})


def get_leaderboard(
    profiles: dict[str, dict[str, Any]],
    active_player_name: str,
    difficulty_filter: int = -1,
) -> list[dict[str, Any]]:
    """Mirror `SaveData.get_leaderboard` with exact tier/completion/time/name sorting."""
    active_key = normalize_player_key(active_player_name, MAX_NAME_LENGTH)
    entries: list[dict[str, Any]] = []

    for key, profile in profiles.items():
        rec_map: dict[int, dict[str, Any]] = profile.get("records", {})
        if not rec_map:
            continue
        display_name = clean_player_name(profile.get("display_name", key.upper()), MAX_NAME_LENGTH)

        if difficulty_filter < 0:
            highest_diff = select_best_global_difficulty(rec_map)
            if highest_diff < 0:
                continue
            best_rec = rec_map[highest_diff]
            diff_idx = highest_diff
            rec = best_rec
        else:
            if difficulty_filter not in rec_map:
                continue
            diff_idx = difficulty_filter
            rec = rec_map[difficulty_filter]

        time_val = float(rec.get("time", 0.0))
        completed = bool(rec.get("completed", False))
        diff_name = get_difficulty_name(diff_idx)
        entries.append(
            {
                "rank": 0,
                "key": key,
                "player_name": display_name,
                "player_name_upper": display_name.upper(),
                "difficulty": diff_idx,
                "difficulty_name": diff_name,
                "difficulty_upper": diff_name.upper(),
                "time": time_val,
                "completed": completed,
                "is_current": key == active_key,
                "score_full": format_run_score(diff_idx, time_val, completed, compact=False),
                "score_compact": format_run_score(diff_idx, time_val, completed, compact=True),
            }
        )

    def _compare(a: dict[str, Any], b: dict[str, Any]) -> int:
        diff_a = int(a["difficulty"])
        diff_b = int(b["difficulty"])
        comp_a = bool(a["completed"])
        comp_b = bool(b["completed"])

        if difficulty_filter < 0:
            rank_a = global_tier_rank(diff_a, comp_a)
            rank_b = global_tier_rank(diff_b, comp_b)
            if rank_a != rank_b:
                return -1 if rank_a > rank_b else 1

        if comp_a != comp_b:
            return -1 if comp_a else 1

        time_a = float(a["time"])
        time_b = float(b["time"])
        if abs(time_a - time_b) > 0.0001:
            return -1 if time_a > time_b else 1

        name_a = str(a["player_name"]).lower()
        name_b = str(b["player_name"]).lower()
        if name_a != name_b:
            return -1 if name_a < name_b else 1
        return 0

    entries.sort(key=cmp_to_key(_compare))
    for idx, entry in enumerate(entries, start=1):
        entry["rank"] = idx
    return entries


def detect_record_updates(
    previous_profiles: dict[str, dict[str, Any]] | None,
    current_profiles: dict[str, dict[str, Any]],
) -> list[dict[str, Any]]:
    """Return newly created or improved player records relative to `previous_profiles`."""
    if previous_profiles is None:
        return []

    updates: list[dict[str, Any]] = []
    for key, profile in current_profiles.items():
        prev_records = previous_profiles.get(key, {}).get("records", {})
        curr_records = profile.get("records", {})
        display_name = str(profile.get("display_name", key.upper()))

        for diff, rec in curr_records.items():
            time_val = float(rec.get("time", 0.0))
            completed = bool(rec.get("completed", False))
            prev = prev_records.get(diff)
            improved = False
            if prev is None:
                improved = True
            else:
                was_completed = bool(prev.get("completed", False))
                prev_time = float(prev.get("time", 0.0))
                if completed and not was_completed:
                    improved = True
                elif not completed and not was_completed and (time_val - prev_time) > 0.0001:
                    improved = True

            if improved:
                updates.append(
                    {
                        "key": key,
                        "player_name": display_name,
                        "difficulty": diff,
                        "time": time_val,
                        "completed": completed,
                    }
                )

    return updates


def build_snapshot(
    parsed: dict[str, Any],
    source_path: str,
    source_exists: bool,
    mtime: float | None,
    previous_profiles: dict[str, dict[str, Any]] | None = None,
) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    """Build the complete JSON-serializable leaderboard snapshot + synced profiles."""
    player_name, profiles = sync_profiles(parsed)
    active_key = normalize_player_key(player_name, MAX_NAME_LENGTH)
    active_records = _get_active_player_records(player_name, profiles)

    leaderboards: dict[str, list[dict[str, Any]]] = {}
    player_ranks: dict[str, int] = {}
    for filter_id in FILTER_IDS:
        board = get_leaderboard(profiles, player_name, filter_id)
        f_key = str(filter_id)
        leaderboards[f_key] = board
        rank_val = 0
        for entry in board:
            if entry["key"] == active_key:
                rank_val = int(entry["rank"])
                break
        player_ranks[f_key] = rank_val

    recent_updates = detect_record_updates(previous_profiles, profiles)

    snapshot = {
        "version": 1,
        "updated_at": mtime,
        "source_file": source_path,
        "source_exists": source_exists,
        "player_name": player_name,
        "player_name_upper": player_name.upper(),
        "best_summary": get_best_summary(active_records),
        "personal_stats": format_personal_stats(active_records),
        "player_ranks": player_ranks,
        "leaderboards": leaderboards,
        "total_players": len(leaderboards["-1"]),
        "recent_updates": recent_updates,
    }
    return snapshot, profiles
