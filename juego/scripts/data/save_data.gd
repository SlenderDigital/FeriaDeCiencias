class_name SaveData
extends Resource
## Persistent multi-player profiles and leaderboard data.
##
## Stored as a custom Resource in user://save_data.tres through ResourceSaver.
## Each player username (matched case-insensitively) has an isolated record
## dictionary mapping difficulty tier (int) -> { "time": float, "completed": bool }.

const DEFAULT_PLAYER_NAME: String = "PLAYER"
const DEFAULT_MAX_NAME_LENGTH: int = 12

@export var player_name: String = DEFAULT_PLAYER_NAME
## Active player's records mirror: difficulty (int) -> { "time": float, "completed": bool }
@export var records: Dictionary = {}
## Normalized player key (String) -> { "display_name": String, "records": Dictionary }
@export var player_profiles: Dictionary = {}
@export_range(0.0, 1.0) var music_volume: float = 0.8
@export_range(0.0, 1.0) var sfx_volume: float = 1.0


static func clean_player_name(raw_name: String, max_length: int = DEFAULT_MAX_NAME_LENGTH) -> String:
	var cleaned: String = raw_name.strip_edges().left(max_length)
	return DEFAULT_PLAYER_NAME if cleaned.is_empty() else cleaned


static func normalize_player_key(raw_name: String, max_length: int = DEFAULT_MAX_NAME_LENGTH) -> String:
	return clean_player_name(raw_name, max_length).to_lower()


## Ensures legacy single-player save files are migrated and syncs `records`
## to the currently active `player_name` without leaking scores across players.
func sync_active_profile(max_length: int = DEFAULT_MAX_NAME_LENGTH) -> void:
	player_name = clean_player_name(player_name, max_length)
	var key: String = normalize_player_key(player_name, max_length)
	if player_profiles.is_empty() and not records.is_empty():
		var migrated_records: Dictionary = _normalize_records_dict(records)
		player_profiles[key] = {
			"display_name": player_name,
			"records": migrated_records,
		}
		records = migrated_records
		return

	if player_profiles.has(key):
		var profile: Dictionary = player_profiles[key] as Dictionary
		var stored_records: Dictionary = _normalize_records_dict(profile.get("records", {}) as Dictionary)
		profile["display_name"] = player_name
		profile["records"] = stored_records
		player_profiles[key] = profile
		records = stored_records
	else:
		records = {}


## Switches the active player to `new_name` and loads their isolated score history.
func set_active_player(new_name: String, max_length: int = DEFAULT_MAX_NAME_LENGTH) -> String:
	var cleaned: String = clean_player_name(new_name, max_length)
	var key: String = normalize_player_key(cleaned, max_length)
	player_name = cleaned
	if player_profiles.has(key):
		var profile: Dictionary = player_profiles[key] as Dictionary
		var stored_records: Dictionary = _normalize_records_dict(profile.get("records", {}) as Dictionary)
		profile["display_name"] = cleaned
		profile["records"] = stored_records
		player_profiles[key] = profile
		records = stored_records
	else:
		records = {}
	return player_name


func has_player_profile(for_player: String = "") -> bool:
	var target_name: String = player_name if for_player.is_empty() else for_player
	var key: String = normalize_player_key(target_name)
	if not player_profiles.has(key):
		return false
	var profile: Dictionary = player_profiles[key] as Dictionary
	var rec_map: Dictionary = profile.get("records", {}) as Dictionary
	return not rec_map.is_empty()


## Returns the isolated records dictionary for `for_player` (defaults to active `player_name`).
func get_player_records(for_player: String = "") -> Dictionary:
	var target_name: String = player_name if for_player.is_empty() else for_player
	var key: String = normalize_player_key(target_name)
	var active_key: String = normalize_player_key(player_name)

	if key == active_key:
		if player_profiles.has(key):
			var profile: Dictionary = player_profiles[key] as Dictionary
			var profile_records: Dictionary = _normalize_records_dict(profile.get("records", {}) as Dictionary)
			if records.is_empty() and not profile_records.is_empty():
				# Caller explicitly cleared `save_data.records = {}`
				profile["records"] = {}
				player_profiles[key] = profile
				return records
			return profile_records
		return _normalize_records_dict(records)

	if not player_profiles.has(key):
		return {}
	var target_profile: Dictionary = player_profiles[key] as Dictionary
	return _normalize_records_dict(target_profile.get("records", {}) as Dictionary)


## Clears all recorded runs for `for_player` (defaults to active `player_name`).
func clear_player_records(for_player: String = "") -> void:
	var target_name: String = player_name if for_player.is_empty() else for_player
	var key: String = normalize_player_key(target_name)
	if player_profiles.has(key):
		player_profiles.erase(key)
	if key == normalize_player_key(player_name):
		records = {}


## Returns the highest difficulty with a recorded run for `for_player`, or -1 when nothing is stored.
func get_highest_difficulty(for_player: String = "") -> int:
	var rec_map: Dictionary = get_player_records(for_player)
	var highest: int = -1
	for key: Variant in rec_map.keys():
		highest = maxi(highest, int(key))
	return highest


## Returns the record of a difficulty for `for_player` ({} when never played).
func get_record(difficulty: int, for_player: String = "") -> Dictionary:
	var rec_map: Dictionary = get_player_records(for_player)
	if rec_map.has(difficulty):
		return (rec_map[difficulty] as Dictionary).duplicate()
	if rec_map.has(str(difficulty)):
		return (rec_map[str(difficulty)] as Dictionary).duplicate()
	return {}


## Returns the record of the highest difficulty played by `for_player` ({} when none).
func get_highest_record(for_player: String = "") -> Dictionary:
	var highest: int = get_highest_difficulty(for_player)
	if highest < 0:
		return {}
	var record: Dictionary = get_record(highest, for_player)
	record["difficulty"] = highest
	return record


## Stores a run for `for_player` (defaults to active `player_name`) if it beats their
## personal record on that difficulty.
## A completed run always beats an incomplete one; otherwise longer time wins.
## Returns true when the player's stored record changed.
func submit_result(difficulty: int, time_survived: float, completed: bool, for_player: String = "") -> bool:
	var target_raw: String = player_name if for_player.is_empty() else for_player
	var cleaned_name: String = clean_player_name(target_raw)
	var key: String = normalize_player_key(cleaned_name)
	var active_key: String = normalize_player_key(player_name)

	var rec_map: Dictionary = get_player_records(cleaned_name)
	var current: Dictionary = rec_map.get(difficulty, {}) as Dictionary
	var improved: bool = current.is_empty()
	if not improved:
		var was_completed: bool = bool(current.get("completed", false))
		if completed and not was_completed:
			improved = true
		elif not completed and not was_completed and time_survived > float(current.get("time", 0.0)):
			improved = true

	if improved:
		rec_map[difficulty] = {"time": time_survived, "completed": completed}
		var display_name: String = cleaned_name
		if player_profiles.has(key) and for_player.is_empty():
			display_name = player_name
		player_profiles[key] = {
			"display_name": display_name,
			"records": rec_map,
		}
		if key == active_key:
			records = rec_map
	elif not player_profiles.has(key) and not rec_map.is_empty():
		player_profiles[key] = {
			"display_name": cleaned_name,
			"records": rec_map,
		}
		if key == active_key:
			records = rec_map

	return improved


## Returns a ranked leaderboard array across all saved players.
## When `difficulty_filter == -1`, ranks players by their highest difficulty record.
## When `difficulty_filter` is 0 (Easy), 1 (Normal), or 2 (Hard), ranks only players
## who have recorded a run on that specific difficulty.
func get_leaderboard(difficulty_filter: int = -1, current_player_override: String = "") -> Array[Dictionary]:
	sync_active_profile()
	var active_key: String = normalize_player_key(
		player_name if current_player_override.is_empty() else current_player_override
	)
	var entries: Array[Dictionary] = []

	for raw_key: Variant in player_profiles.keys():
		var key: String = str(raw_key)
		var profile: Dictionary = player_profiles[raw_key] as Dictionary
		var display_name: String = clean_player_name(str(profile.get("display_name", key.to_upper())))
		var rec_map: Dictionary = _normalize_records_dict(profile.get("records", {}) as Dictionary)
		if rec_map.is_empty():
			continue

		if difficulty_filter < 0:
			var highest_diff: int = -1
			for d_key: Variant in rec_map.keys():
				highest_diff = maxi(highest_diff, int(d_key))
			if highest_diff < 0:
				continue
			var best_rec: Dictionary = rec_map.get(highest_diff, {}) as Dictionary
			entries.append({
				"rank": 0,
				"key": key,
				"player_name": display_name,
				"difficulty": highest_diff,
				"time": float(best_rec.get("time", 0.0)),
				"completed": bool(best_rec.get("completed", false)),
				"is_current": key == active_key,
			})
		else:
			if not rec_map.has(difficulty_filter):
				continue
			var diff_rec: Dictionary = rec_map.get(difficulty_filter, {}) as Dictionary
			entries.append({
				"rank": 0,
				"key": key,
				"player_name": display_name,
				"difficulty": difficulty_filter,
				"time": float(diff_rec.get("time", 0.0)),
				"completed": bool(diff_rec.get("completed", false)),
				"is_current": key == active_key,
			})

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var diff_a: int = int(a.get("difficulty", 0))
		var diff_b: int = int(b.get("difficulty", 0))
		if difficulty_filter < 0 and diff_a != diff_b:
			return diff_a > diff_b
		var comp_a: bool = bool(a.get("completed", false))
		var comp_b: bool = bool(b.get("completed", false))
		if comp_a != comp_b:
			return comp_a
		var time_a: float = float(a.get("time", 0.0))
		var time_b: float = float(b.get("time", 0.0))
		if absf(time_a - time_b) > 0.0001:
			return time_a > time_b
		return str(a.get("player_name", "")).nocasecmp_to(str(b.get("player_name", ""))) < 0
	)

	for i: int in range(entries.size()):
		entries[i]["rank"] = i + 1

	return entries


## Returns the 1-based rank of `for_player` in the requested leaderboard filter, or 0 if unranked.
func get_player_rank(difficulty_filter: int = -1, for_player: String = "") -> int:
	var target_name: String = player_name if for_player.is_empty() else for_player
	var target_key: String = normalize_player_key(target_name)
	var board: Array[Dictionary] = get_leaderboard(difficulty_filter, target_name)
	for entry: Dictionary in board:
		if str(entry.get("key", "")) == target_key:
			return int(entry.get("rank", 0))
	return 0


func _normalize_records_dict(source: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	for k: Variant in source.keys():
		var val: Variant = source[k]
		if val is Dictionary:
			var rec: Dictionary = val as Dictionary
			normalized[int(k)] = {
				"time": float(rec.get("time", 0.0)),
				"completed": bool(rec.get("completed", false)),
			}
	return normalized
