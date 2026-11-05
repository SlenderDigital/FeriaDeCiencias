extends SceneTree


func _process(_delta: float) -> bool:
	print("\n=== STARTING FULL PERSISTENCE LOOP TEST ===")

	var gm: Node = root.get_node_or_null("GameManager")
	assert(gm != null, "GameManager autoload must exist")

	print("[Step 1] Initial GameManager state:")
	print("  Player Name: ", gm.get_player_name())
	print("  Best Summary: ", gm.get_best_summary())
	print("  Save Path (Resource): ", gm.save_path)
	print("  Absolute Disk Path: ", gm.get_absolute_save_path())

	var test_name: String = "Facundo & Bauti"
	print("\n[Step 2] Updating player name to: '", test_name, "'")
	gm.set_player_name(test_name)
	var updated_name: String = gm.get_player_name()
	assert(updated_name.begins_with("Facundo"), "Player name should be updated")
	print("  Verified Player Name: ", updated_name)

	print("\n[Step 3] Submitting run result: Difficulty 2 (Hard), 45.0s, completed = true")
	gm.save_data.records = {}
	var improved: bool = gm.report_result(2, 45.0, true)
	assert(improved, "First completed run on empty record should be marked as improved/new record")
	print("  Improved flag: ", improved)
	print("  New Best Summary: ", gm.get_best_summary())

	var repeat_run: bool = gm.report_result(2, 30.0, false)
	assert(not repeat_run, "A worse run should not overwrite an existing completed record")

	var abs_path: String = gm.get_absolute_save_path()
	var file_exists: bool = FileAccess.file_exists(abs_path)
	print("\n[Step 4] Checking file existence on disk at: ", abs_path)
	print("  File exists on disk: ", file_exists)
	assert(file_exists, "Save file must exist on disk at user://save_data.tres")

	var f: FileAccess = FileAccess.open(abs_path, FileAccess.READ)
	assert(f != null, "Must be able to open saved file")
	var file_content: String = f.get_as_text()
	f.close()
	print("\n[Step 5] Raw content of saved Resource (.tres):")
	print("--------------------------------------------------")
	print(file_content.strip_edges())
	print("--------------------------------------------------")

	print("\n[Step 6] Testing round-trip reload from disk into a fresh instance:")
	var fresh_data: Resource = ResourceLoader.load(abs_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert(fresh_data != null, "Fresh reload from disk must succeed")
	var hard_record: Dictionary = fresh_data.get_record(2)
	assert(bool(hard_record.get("completed", false)) == true, "Hard difficulty must be recorded as completed")
	assert(float(hard_record.get("time", 0.0)) == 45.0, "Hard difficulty record time must be 45.0s")

	print("\n=== FULL PERSISTENCE LOOP VERIFIED SUCCESSFULLY! ===\n")
	quit(0)
	return true
