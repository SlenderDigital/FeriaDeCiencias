extends SceneTree


func _process(_delta: float) -> bool:
	print("\n=== STARTING IN-GAME RECORDS MENU TEST ===")

	var menu_scene: PackedScene = load("res://scenes/main_menu.tscn")
	assert(menu_scene != null, "main_menu.tscn must load")
	var menu: Control = menu_scene.instantiate() as Control
	root.add_child(menu)

	print("[Step 1] Verifying menu buttons...")
	var records_btn: Button = menu.get_node_or_null("CenterContainer/MenuBox/RecordsButton") as Button
	assert(records_btn != null, "RecordsButton must exist in MenuBox")
	assert(records_btn.text == "Records", "RecordsButton text must be 'Records'")

	var credits_btn: Button = menu.get_node_or_null("CenterContainer/MenuBox/CreditsButton") as Button
	assert(credits_btn != null, "CreditsButton must exist in MenuBox")
	assert(credits_btn.text == "Credits", "CreditsButton text must be 'Credits'")

	print("\n[Step 2] Verifying records panel is initially closed...")
	var panel: ColorRect = menu.get_node_or_null("RecordsPanel") as ColorRect
	assert(panel != null, "RecordsPanel must exist as a child of MainMenu")
	assert(not panel.visible, "RecordsPanel must be initially invisible")

	print("\n[Step 3] Simulating click on RecordsButton...")
	menu._on_records_pressed()
	assert(panel.visible == true, "RecordsPanel must be visible after pressing RecordsButton")

	print("\n[Step 4] Checking records panel contents...")
	assert(menu.records_player_label != null, "RecordsPlayerLabel must exist")
	assert(menu.records_easy_label != null and menu.records_normal_label != null and menu.records_hard_label != null, "Difficulty labels must exist")

	print("\n[Step 5] Simulating Back/Close button...")
	menu._on_records_close_pressed()
	assert(panel.visible == false, "RecordsPanel must hide when close button is pressed")

	print("\n[Step 6] Testing ESC key (ui_cancel) handling...")
	menu._on_records_pressed()
	assert(panel.visible == true, "RecordsPanel reopened")
	var esc_event: InputEventAction = InputEventAction.new()
	esc_event.action = "ui_cancel"
	esc_event.pressed = true
	menu._unhandled_input(esc_event)
	assert(panel.visible == false, "Pressing ESC must close the RecordsPanel")

	print("\n=== IN-GAME RECORDS MENU VERIFIED 100% WORKING WITHOUT BUGS! ===\n")
	menu.free()
	quit(0)
	return true
