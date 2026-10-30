class_name BubbleController
extends Control
## BubbleController: speaker anchors, wrapping, segments, and screen clamping (SPEC 4.2).
## One bubble per speaker anchor. World positions are converted to screen
## coordinates every frame so bubbles follow speakers as the camera moves.

const STYLE: BubbleStyle = preload("res://data/bubble_style.tres")

var _bubbles: Dictionary = {}  # anchor Node2D -> _Bubble


class _Bubble extends PanelContainer:
	var style: BubbleStyle
	var name_label := Label.new()
	var body := Label.new()
	var footer := HBoxContainer.new()
	var hint := Label.new()
	var retry_button := Button.new()
	var segments := PackedStringArray()
	var index := 0
	var on_retry: Callable

	func _init(s: BubbleStyle) -> void:
		style = s
		mouse_filter = Control.MOUSE_FILTER_STOP
		var box := StyleBoxFlat.new()
		box.bg_color = s.background
		box.border_color = s.border
		box.set_border_width_all(1)
		box.content_margin_left = s.padding_h
		box.content_margin_right = s.padding_h
		box.content_margin_top = s.padding_v
		box.content_margin_bottom = s.padding_v
		add_theme_stylebox_override("panel", box)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(v)
		for l: Label in [name_label, body, hint]:
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.add_theme_font_size_override("font_size", s.name_font_size)
		name_label.add_theme_color_override("font_color", s.muted_color)
		body.add_theme_font_size_override("font_size", s.body_font_size)
		body.add_theme_color_override("font_color", s.text_color)
		hint.add_theme_font_size_override("font_size", s.name_font_size)
		hint.add_theme_color_override("font_color", s.muted_color)
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		retry_button.text = "Retry"
		retry_button.focus_mode = Control.FOCUS_NONE
		retry_button.pressed.connect(func() -> void: on_retry.call())
		footer.add_child(hint)
		footer.add_child(retry_button)
		v.add_child(name_label)
		v.add_child(body)
		v.add_child(footer)

	func set_content(speaker: String, text: String, streaming: bool, error := false) -> void:
		name_label.text = speaker
		var new_segments := BubbleController.split_segments(text, style.segment_chars)
		if new_segments.is_empty():
			new_segments = PackedStringArray([""])
		# Keep the reader's place while text streams in; a new reply starts from the
		# single "…" waiting segment, which resets the index to 0.
		segments = new_segments
		index = mini(index, segments.size() - 1)
		retry_button.visible = error
		body.add_theme_color_override("font_color", style.muted_color if error else style.text_color)
		_render(streaming)

	func _render(streaming := false) -> void:
		var text := segments[index]
		var inner := style.max_width - 2.0 * style.padding_h
		var font := body.get_theme_font("font")
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, style.body_font_size).x
		if width <= inner:
			body.autowrap_mode = TextServer.AUTOWRAP_OFF
			body.custom_minimum_size.x = 0
		else:
			body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.custom_minimum_size.x = inner
		body.text = text
		var more := index < segments.size() - 1
		hint.text = "click for more  %d/%d" % [index + 1, segments.size()] if more else ("…" if streaming else "")
		footer.visible = hint.text != "" or retry_button.visible
		reset_size()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if index < segments.size() - 1:
				index += 1
				_render()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func show_waiting(anchor: Node2D, speaker: String) -> void:
	_bubble_for(anchor).set_content(speaker, "…", true)


func show_text(anchor: Node2D, speaker: String, text: String, streaming: bool) -> void:
	_bubble_for(anchor).set_content(speaker, text, streaming)


func show_error(anchor: Node2D, speaker: String, message: String, on_retry: Callable) -> void:
	var b := _bubble_for(anchor)
	b.on_retry = on_retry
	b.set_content(speaker, message, false, true)


func dismiss(anchor: Node2D) -> void:
	if _bubbles.has(anchor):
		_bubbles[anchor].queue_free()
		_bubbles.erase(anchor)


func _bubble_for(anchor: Node2D) -> _Bubble:
	if not _bubbles.has(anchor):
		var b := _Bubble.new(STYLE)
		add_child(b)
		_bubbles[anchor] = b
	return _bubbles[anchor]


func _process(_delta: float) -> void:
	var view := get_viewport_rect().size
	var to_screen := get_viewport().get_canvas_transform()
	var placed: Array[Rect2] = []
	for anchor: Node2D in _bubbles.keys():
		if not is_instance_valid(anchor) or not anchor.is_visible_in_tree():
			dismiss(anchor)
			continue
		var b: _Bubble = _bubbles[anchor]
		b.reset_size()  # wrapped labels settle a frame late; re-fit so bubbles shrink
		var p: Vector2 = to_screen * anchor.call("bubble_anchor")
		var pos := p - Vector2(b.size.x / 2.0, b.size.y + 4.0)
		var m := STYLE.screen_margin
		pos = pos.clamp(Vector2(m, STYLE.top_margin), view - b.size - Vector2(m, m))
		# Push overlapping bubbles upward so both stay readable; when the top of the
		# screen leaves no room, move sideways away from the other bubble instead.
		for r in placed:
			if Rect2(pos, b.size).intersects(r):
				pos.y = maxf(STYLE.top_margin, r.position.y - b.size.y - 2.0)
			if Rect2(pos, b.size).intersects(r):
				pos.x = r.end.x + 2.0 if p.x >= r.get_center().x else r.position.x - b.size.x - 2.0
				pos.x = clampf(pos.x, m, view.x - b.size.x - m)
		b.position = pos.round()
		b.set_meta("tip", p)
		placed.append(Rect2(b.position, b.size))
	queue_redraw()


## A small tail from each bubble toward its speaker, when the speaker is below it.
func _draw() -> void:
	for b: _Bubble in _bubbles.values():
		if not b.has_meta("tip"):
			continue
		var tip: Vector2 = b.get_meta("tip")
		var bottom := b.position.y + b.size.y
		if tip.y - bottom < 3.0:
			continue
		var x := clampf(tip.x, b.position.x + 8.0, b.position.x + b.size.x - 8.0)
		var end := Vector2(x, minf(tip.y, bottom + 6.0))
		var pts := PackedVector2Array([Vector2(x - 4.0, bottom - 1.0), Vector2(x + 4.0, bottom - 1.0), end])
		draw_colored_polygon(pts, STYLE.background)
		draw_polyline(PackedVector2Array([pts[0] + Vector2(0, 1), end, pts[1] + Vector2(0, 1)]), STYLE.border, 1.0)


## Splits text at sentence boundaries into segments of at most max_chars
## (a single over-long sentence is broken at the last space that fits).
static func split_segments(text: String, max_chars: int) -> PackedStringArray:
	var out := PackedStringArray()
	var re := RegEx.create_from_string("[^.!?…。！？]+[.!?…。！？]*[\"'”’)]*\\s*")
	var current := ""
	for m in re.search_all(text):
		var sentence := m.get_string()
		while sentence.length() > max_chars:
			var cut := sentence.substr(0, max_chars).rfind(" ")
			cut = max_chars if cut <= 0 else cut
			if current.strip_edges() != "":
				out.append(current.strip_edges())
				current = ""
			out.append(sentence.substr(0, cut).strip_edges())
			sentence = sentence.substr(cut)
		if current.length() + sentence.length() > max_chars and current.strip_edges() != "":
			out.append(current.strip_edges())
			current = ""
		current += sentence
	if current.strip_edges() != "":
		out.append(current.strip_edges())
	return out
