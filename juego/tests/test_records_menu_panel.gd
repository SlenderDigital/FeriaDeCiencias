extends SceneTree


func _process(_delta: float) -> bool:
	print("\n=== STARTING IN-GAME RANKING & RECORDS MENU TEST ===")

	var gm: Node = root.get_node_or_null("GameManager")
	assert(gm != null, "GameManager autoload must exist")
	gm.save_data = SaveData.new()
	gm.set_player_name("Facundo")
	gm.report_result(2, 45.0, true)
	gm.set_player_name("Bauti")
	gm.report_result(1, 31.2, false)
	gm.set_player_name("Facundo")

	var menu_scene: PackedScene = load("res://scenes/main_menu.tscn")
	assert(menu_scene != null, "main_menu.tscn must load")
	var menu: Control = menu_scene.instantiate() as Control
	root.add_child(menu)

	print("[Step 1] Verifying menu buttons and live BestLabel updates...")
	var records_btn: Button = menu.get_node_or_null("CenterContainer/MenuBox/RecordsButton") as Button
	assert(records_btn != null and records_btn.text == "Records", "RecordsButton must exist with text 'Records'")

	var credits_btn: Button = menu.get_node_or_null("CenterContainer/MenuBox/CreditsButton") as Button
	assert(credits_btn != null and credits_btn.text == "Credits", "CreditsButton must exist with text 'Credits'")

	assert(menu.best_label.text.find("BEST  HARD  -  COMPLETED") != -1, "Menu BestLabel must show Facundo's best run")
	menu.name_edit.text = "Bauti"
	menu._on_name_text_changed("Bauti")
	assert(menu.best_label.text.find("BEST  NORMAL  -  31.2s") != -1, "Typing 'Bauti' must live-update BestLabel to Bauti's score")

	menu.name_edit.text = "NewPlayer"
	menu._on_name_text_changed("NewPlayer")
	assert(menu.best_label.text == "No runs yet", "Typing a new username must live-update BestLabel to 'No runs yet'")

	menu.name_edit.text = "Facundo"
	menu._commit_player_name()

	print("\n[Step 2] Verifying records panel opens and renders multi-player leaderboard...")
	var panel: ColorRect = menu.get_node_or_null("RecordsPanel") as ColorRect
	assert(panel != null and not panel.visible, "RecordsPanel must be initially invisible")

	menu._on_records_pressed()
	assert(panel.visible == true, "RecordsPanel must be visible after pressing RecordsButton")
	assert(menu.records_player_label.text.find("FACUNDO") != -1, "RecordsPlayerLabel must show active player")
	assert(menu.records_easy_label != null and menu.records_normal_label != null and menu.records_hard_label != null, "Difficulty labels must exist")
	assert(menu.leaderboard_list.get_child_count() == 2, "Global leaderboard must render 2 player rows")

	print("\n[Step 3] Testing difficulty filter tabs...")
	menu.set_leaderboard_filter(1) # Normal
	assert(menu.leaderboard_list.get_child_count() == 1, "Normal filter must render 1 row (Bauti)")
	menu.set_leaderboard_filter(0) # Easy (no runs)
	assert(menu.leaderboard_list.get_child_count() == 1, "Empty filter must render EmptyLeaderboardLabel")
	assert(menu.leaderboard_list.get_child(0).name == "EmptyLeaderboardLabel", "Empty state node must be EmptyLeaderboardLabel")
	menu.set_leaderboard_filter(-1) # Back to Global
	assert(menu.leaderboard_list.get_child_count() == 2, "Global filter must restore 2 player rows")

	print("\n[Step 4] Testing responsive layout across compact, standard, and wide viewports...")
	for vp_size: Vector2 in [Vector2(480.0, 360.0), Vector2(1152.0, 648.0), Vector2(1920.0, 1080.0)]:
		menu._on_resized(vp_size)
		assert(menu.records_box.custom_minimum_size.x <= vp_size.x, "RecordsBox width must fit inside viewport %s" % str(vp_size))
		assert(menu.records_box.custom_minimum_size.y <= vp_size.y, "RecordsBox height must fit inside viewport %s" % str(vp_size))

	print("\n[Step 5] Simulating Back/Close button and ESC key...")
	menu._on_records_close_pressed()
	assert(panel.visible == false, "RecordsPanel must hide when close button is pressed")

	menu._on_records_pressed()
	assert(panel.visible == true, "RecordsPanel reopened")
	var esc_event: InputEventAction = InputEventAction.new()
	esc_event.action = "ui_cancel"
	esc_event.pressed = true
	menu._unhandled_input(esc_event)
	assert(panel.visible == false, "Pressing ESC must close the RecordsPanel")

	gm.save_data = SaveData.new()
	gm.save_game()

	print("\n=== IN-GAME RANKING & RECORDS MENU VERIFIED 100% WORKING! ===\n")
	menu.free()
	quit(0)
	return true
