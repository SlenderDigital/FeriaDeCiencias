class_name UiStyle
extends RefCounted


static func add_hover_pop(btn: Button, scale_to: float = 1.06) -> void:
	if btn == null or btn.has_meta(&"hover_pop"):
		return
	btn.set_meta(&"hover_pop", true)
	var center_pivot: Callable = func() -> void:
		btn.pivot_offset = btn.size * 0.5
	btn.resized.connect(center_pivot)
	center_pivot.call()
	var pop: Callable = func(target: float) -> void:
		if not btn.is_inside_tree():
			return
		var tw: Tween = btn.create_tween()
		tw.tween_property(btn, "scale", Vector2.ONE * target, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	btn.mouse_entered.connect(pop.bind(scale_to))
	btn.mouse_exited.connect(pop.bind(1.0))
	btn.focus_entered.connect(pop.bind(scale_to))
	btn.focus_exited.connect(pop.bind(1.0))
	btn.mouse_entered.connect(func() -> void: SoundManager.play_ui_hover())
