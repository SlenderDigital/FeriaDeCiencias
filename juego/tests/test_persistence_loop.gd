extends SceneTree


func _process(_delta: float) -> bool:
	print("\n=== STARTING MULTI-PLAYER PERSISTENCE & RANKING TEST ===")

	var gm: Node = root.get_node_or_null("GameManager")
	assert(gm != null, "GameManager autoload must exist")

	# Use a clean save state for deterministic testing
	gm.save_data = SaveData.new()
	gm.save_game()

	print("[Step 1] Setting Player 1 ('Facundo') and recording runs...")
	gm.set_player_name("Facundo")
	assert(gm.get_player_name() == "Facundo", "Player name should be 'Facundo'")
	assert(gm.get_best_summary() == "No runs yet", "Fresh player must start with 'No runs yet'")

	var p1_hard: bool = gm.report_result(2, 45.0, true)
	assert(p1_hard, "First completed run on Hard for Facundo must be marked as improved")
	assert(gm.get_best_summary() == "BEST  HARD  -  COMPLETED", "Facundo best summary must reflect Hard completion")

	var p1_worse: bool = gm.report_result(2, 30.0, false)
	assert(not p1_worse, "Worse run must not overwrite existing completed record")

	print("\n[Step 2] Switching to Player 2 ('Bauti') and verifying score isolation...")
	gm.set_player_name("Bauti")
	assert(gm.get_player_name() == "Bauti", "Active player should now be 'Bauti'")
	assert(gm.get_best_summary() == "No runs yet", "New player 'Bauti' must NOT inherit Facundo's scores")
	assert(gm.save_data.get_record(2).is_empty(), "Bauti's Hard record must be empty")

	var p2_normal: bool = gm.report_result(1, 34.5, false)
	assert(p2_normal, "Bauti's first Normal run must be recorded")
	assert(gm.get_best_summary() == "BEST  NORMAL  -  34.5s", "Bauti best summary must reflect Normal 34.5s")
	var p2_hard: bool = gm.report_result(2, 28.0, false)
	assert(p2_hard, "Bauti's first Hard run must be recorded")

	print("\n[Step 3] Switching to Player 3 ('Alex') and recording runs...")
	gm.set_player_name("Alex")
	assert(gm.get_best_summary() == "No runs yet", "New player 'Alex' must start with 'No runs yet'")
	gm.report_result(1, 45.0, true)

	print("\n[Step 4] Verifying case-insensitive profile restoration ('facundo')...")
	gm.set_player_name("facundo")
	assert(gm.get_best_summary() == "BEST  HARD  -  COMPLETED", "Case-insensitive switch to 'facundo' must restore Facundo's scores")
	var facu_hard: Dictionary = gm.save_data.get_record(2)
	assert(bool(facu_hard.get("completed", false)) == true, "Facundo Hard completion must be intact")
	assert(gm.save_data.get_record(1).is_empty(), "Facundo must not have Bauti's or Alex's Normal runs")

	print("\n[Step 5] Verifying Global and Per-Difficulty Leaderboard rankings...")
	var global_board: Array[Dictionary] = gm.get_leaderboard(-1)
	assert(global_board.size() == 3, "Global leaderboard must contain all 3 players with recorded runs")
	assert(str(global_board[0].get("key", "")) == "facundo", "Rank #1 Global must be Facundo (Hard Completed)")
	assert(str(global_board[1].get("key", "")) == "bauti", "Rank #2 Global must be Bauti (Hard 28.0s)")
	assert(str(global_board[2].get("key", "")) == "alex", "Rank #3 Global must be Alex (Normal Completed)")
	assert(gm.get_player_rank(-1, "Facundo") == 1, "Facundo global rank must be 1")
	assert(gm.get_player_rank(-1, "Bauti") == 2, "Bauti global rank must be 2")
	assert(gm.get_player_rank(-1, "Alex") == 3, "Alex global rank must be 3")

	var normal_board: Array[Dictionary] = gm.get_leaderboard(1)
	assert(normal_board.size() == 2, "Normal leaderboard must contain only Alex and Bauti")
	assert(str(normal_board[0].get("key", "")) == "alex", "Rank #1 Normal must be Alex (Completed)")
	assert(str(normal_board[1].get("key", "")) == "bauti", "Rank #2 Normal must be Bauti (34.5s)")

	print("\n[Step 6] Verifying round-trip reload from disk...")
	var abs_path: String = gm.get_absolute_save_path()
	assert(FileAccess.file_exists(abs_path), "Save file must exist on disk")
	var fresh_data: SaveData = ResourceLoader.load(abs_path, "", ResourceLoader.CACHE_MODE_IGNORE) as SaveData
	assert(fresh_data != null, "Fresh reload from disk must succeed")
	fresh_data.sync_active_profile()
	assert(fresh_data.get_player_rank(-1, "Facundo") == 1, "Reloaded data must preserve Facundo Rank #1")
	assert(fresh_data.get_player_rank(1, "Alex") == 1, "Reloaded data must preserve Alex Normal Rank #1")
	assert(float(fresh_data.get_record(1, "Bauti").get("time", 0.0)) == 34.5, "Reloaded data must preserve Bauti Normal 34.5s")

	# Leave clean default save data after test
	gm.save_data = SaveData.new()
	gm.save_game()

	print("\n=== MULTI-PLAYER PERSISTENCE & RANKING VERIFIED SUCCESSFULLY! ===\n")
	quit(0)
	return true
