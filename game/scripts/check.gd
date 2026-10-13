class_name Check
extends Button
## A tick box in the CIC look (the stock CheckBox needs icons). Click to toggle; `toggled` fires as for any Button.

func _init(label: String, on := false) -> void:
	toggle_mode = true
	button_pressed = on
	text = label
	focus_mode = Control.FOCUS_NONE
	flat = true
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom_minimum_size = Vector2(0, 28)
	add_theme_font_size_override("font_size", 14)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		add_theme_color_override(c, UI.TEXT)
	var s := StyleBoxEmpty.new()
	s.content_margin_left = 30
	for n in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		add_theme_stylebox_override(n, s)
	toggled.connect(func(_on): queue_redraw())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)

func _draw() -> void:
	var r := Rect2(2, (size.y - 20) * 0.5, 20, 20)
	draw_rect(r, UI.KEY_BG)
	draw_rect(r, UI.PRI if (button_pressed or is_hovered()) else UI.KEY_LINE, false, 1.0)
	if button_pressed:
		draw_polyline(PackedVector2Array([r.position + Vector2(4, 10), r.position + Vector2(8.5, 14.5), r.position + Vector2(16, 5.5)]), UI.PRI, 2.5, true)
