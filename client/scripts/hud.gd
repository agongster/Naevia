class_name Hud
extends CanvasLayer
## HUD: bag/furniture, contacts, history, reply input, and development actions.
## Native controls with live text, styled after art/previews/ui_direction.png.
## Sizes are 640 x 360 game units (x2 on screen): 22 units = 44 px minimum height.

const BUTTON_H := 22.0
const COLORS := {
	"panel": Color("#f4e9d2"), "border": Color("#4b382d"), "text": Color("#352c2a"),
	"normal": Color("#eadbb9"), "hover": Color("#d4d8a5"), "pressed": Color("#9ea77c"),
	"disabled": Color("#c9c4b6"), "field": Color("#fffaf0"),
}

var bubbles: BubbleController

var _root: Control
var _bag_panel: PanelContainer
var _bag_list: VBoxContainer
var _stone_label: Label
var _arrange_button: Button
var _store_button: Button
var _cancel_button: Button
var _contacts_panel: PanelContainer
var _dev_panel: PanelContainer
var _history_panel: PanelContainer
var _history_list: VBoxContainer
var _history_key := "witch"
var _history_title: Label
var _show_memory := false
var _reply_panel: PanelContainer
var _reply_to: Label
var _reply_field: LineEdit
var _send_button: Button
var _hint: Label
var _status: Label

@onready var world: World = get_parent()


## Called by World once its node references exist (children are ready before parents).
func setup() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)
	bubbles = BubbleController.new()
	_root.add_child(bubbles)
	_build_top_bar()
	_build_bag()
	_build_contacts()
	_build_dev()
	_build_history()
	_build_reply()
	_hint = _label("", 9)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_hint.offset_top = 36
	_hint.add_theme_color_override("font_outline_color", COLORS.panel)
	_hint.add_theme_constant_override("outline_size", 3)
	var status_panel := PanelContainer.new()
	_status = _label("Backend: checking…", 8)
	status_panel.add_child(_status)
	_root.add_child(status_panel)
	status_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 6)
	status_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	SaveManager.inventory_changed.connect(_refresh_bag)
	ApiClient.health_checked.connect(_on_health)
	world.furniture.mode_changed.connect(_refresh_bag)
	world.conversation.opened.connect(_refresh_reply)
	world.conversation.closed.connect(_refresh_reply)
	world.conversation.state_changed.connect(_refresh_reply)
	_refresh_bag()
	_refresh_reply()


# --- Construction ---

func _build_top_bar() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_button("Bag", func() -> void: _toggle(_bag_panel)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)
	bar.add_child(_button("History", func() -> void:
		_toggle(_history_panel)
		_refresh_history()))
	bar.add_child(_button("Contacts", func() -> void: _toggle(_contacts_panel)))
	bar.add_child(_button("Dev", func() -> void: _toggle(_dev_panel)))
	_root.add_child(bar)


func _build_bag() -> void:
	_bag_panel = PanelContainer.new()
	_bag_panel.position = Vector2(8, 34)
	_bag_panel.visible = false
	var v := VBoxContainer.new()
	_bag_panel.add_child(v)
	v.add_child(_label("Bag", 11))
	var stone_row := HBoxContainer.new()
	var icon := TextureRect.new()
	icon.texture = Visuals.texture(Defs.items["item.stone"].icon)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	stone_row.add_child(icon)
	_stone_label = _label("", 10)
	stone_row.add_child(_stone_label)
	v.add_child(stone_row)
	_bag_list = VBoxContainer.new()
	v.add_child(_bag_list)
	var row := HBoxContainer.new()
	_arrange_button = _button("Arrange", func() -> void: world.furniture.set_arranging(_arrange_button.button_pressed))
	_arrange_button.toggle_mode = true
	_store_button = _button("Store", world.furniture.store_moving)
	_cancel_button = _button("Cancel", world.furniture.cancel)
	row.add_child(_arrange_button)
	row.add_child(_store_button)
	row.add_child(_cancel_button)
	v.add_child(row)
	_root.add_child(_bag_panel)


func _build_contacts() -> void:
	_contacts_panel = _popup_panel([
		["Witch", world.contacts.summon_pigeon],
		["Blacksmith", world.contacts.summon_blacksmith],
		["Invite Both", world.contacts.invite_both],
	])


func _build_dev() -> void:
	_dev_panel = _popup_panel([
		["Pigeon now", world.contacts.summon_pigeon],
		["Blacksmith now", world.contacts.summon_blacksmith],
		["Reset resources", world.reset_resources],
		["+9 stone", func() -> void: SaveManager.add_material("item.stone", 9)],
		["Check backend", ApiClient.check_health],
		["Update memories now", MemoryStore.update_all],
		["Wipe save + reload", func() -> void:
			SaveManager.wipe_slot()
			get_tree().reload_current_scene()],
	])


func _popup_panel(entries: Array) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	var v := VBoxContainer.new()
	panel.add_child(v)
	for e in entries:
		var b := _button(e[0], e[1])
		v.add_child(b)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	panel.offset_top = 34
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_root.add_child(panel)
	return panel


func _build_history() -> void:
	_history_panel = PanelContainer.new()
	_history_panel.visible = false
	# Fixed 400 x 240 box centered on screen; the list scrolls inside it.
	_history_panel.set_anchors_preset(Control.PRESET_CENTER)
	_history_panel.offset_left = -200
	_history_panel.offset_right = 200
	_history_panel.offset_top = -120
	_history_panel.offset_bottom = 120
	_history_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_history_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := VBoxContainer.new()
	_history_panel.add_child(v)
	var tabs := HBoxContainer.new()
	_history_title = _label("History", 11)
	tabs.add_child(_history_title)
	for key in Defs.characters.keys() + [ConversationCoordinator.GROUP]:
		tabs.add_child(_button(Defs.characters[key].name if Defs.characters.has(key) else "Group", func() -> void:
			_history_key = key
			_refresh_history()))
	tabs.add_child(_button("Memory", func() -> void:
		_show_memory = not _show_memory
		_refresh_history()))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(spacer)
	tabs.add_child(_button("Close", func() -> void: _history_panel.visible = false))
	v.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_history_list = VBoxContainer.new()
	_history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_history_list)
	v.add_child(scroll)
	_root.add_child(_history_panel)
	MemoryStore.updated.connect(func(id: String) -> void:
		if _history_panel.visible and id == _history_key:
			_refresh_history())


func _build_reply() -> void:
	_reply_panel = PanelContainer.new()
	_reply_panel.custom_minimum_size = Vector2(380, 0)
	var v := VBoxContainer.new()
	_reply_panel.add_child(v)
	_reply_to = _label("", 9)
	v.add_child(_reply_to)
	var row := HBoxContainer.new()
	_reply_field = LineEdit.new()
	_reply_field.placeholder_text = "Say something…"
	_reply_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reply_field.custom_minimum_size.y = BUTTON_H
	_reply_field.text_submitted.connect(func(_t: String) -> void: _send())
	row.add_child(_reply_field)
	_send_button = _button("Send", _send)
	row.add_child(_send_button)
	row.add_child(_button("Close", world.conversation.close))
	v.add_child(row)
	_root.add_child(_reply_panel)
	_reply_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 8)
	_reply_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH


# --- Refresh ---

func _refresh_bag() -> void:
	_stone_label.text = "Stone × %d" % SaveManager.count("item.stone")
	for c in _bag_list.get_children():
		c.queue_free()
	for id: String in Defs.furniture:
		var d: Dictionary = Defs.furniture[id]
		var stored := SaveManager.stored(id)
		var cost := int(d.cost["item.stone"])
		var b := _button("%s   %s" % [d.name, "stored × %d" % stored if stored > 0 else "%d stone" % cost],
			world.furniture.begin_place.bind(id))
		b.icon = Visuals.texture(d.icon)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = stored == 0 and not SaveManager.can_afford(d.cost)
		_bag_list.add_child(b)
	var f := world.furniture
	_arrange_button.set_pressed_no_signal(f.arranging)
	_store_button.visible = f.mode == FurnitureController.Mode.MOVING
	_cancel_button.visible = f.mode != FurnitureController.Mode.NONE
	match f.mode:
		FurnitureController.Mode.PLACING:
			_hint.text = "Placing %s — left click to place, right click to cancel" % Defs.furniture[f.def_id].name
		FurnitureController.Mode.MOVING:
			_hint.text = "Moving %s — left click to drop, Store to put away, right click to cancel" % Defs.furniture[f.def_id].name
		_:
			_hint.text = "Arrange: click furniture to move or store it" if f.arranging else ""


func _refresh_reply() -> void:
	var c := world.conversation
	_reply_panel.visible = c.is_open()
	if not c.is_open():
		_reply_field.release_focus()
		return
	var note := ""
	if c.queued_message:
		note = "   (your message is next)"
	elif c.is_waiting():
		note = "   (%s is replying…)" % Defs.characters[c.speaker].name if c.is_group() else "   (waiting for a reply…)"
	_reply_to.text = c.label + note
	_send_button.disabled = not c.can_send()


func _refresh_history() -> void:
	for c in _history_list.get_children():
		c.queue_free()
	if _show_memory:
		_refresh_memory()
		return
	_history_title.text = "History"
	var events := SaveManager.read_history(_history_key)
	if events.is_empty():
		_history_list.add_child(_label("No conversations yet.", 10))
	for ev in events:
		var who: String = "You" if ev.speaker == "player" else Defs.characters.get(ev.speaker, {"name": ev.speaker}).name
		if ev.speaker != "player" and Defs.characters.has(ev.addressee):
			who += " → " + Defs.characters[ev.addressee].name  # one character talking to the other
		_history_list.add_child(_wrapped("%s: %s" % [who, ev.text], 10))


## What the selected character currently remembers, with where each entry came from.
func _refresh_memory() -> void:
	_history_title.text = "Memory"
	if not Defs.characters.has(_history_key):
		_history_list.add_child(_wrapped("Group talk has no memory of its own. Choose Witch or Blacksmith to see what each one took from it.", 10))
		return
	var m := MemoryStore.get_memory(_history_key)
	var status := "%s · revision %d · %d new event(s) not yet remembered" % [
		Defs.characters[_history_key].name, int(m.revision), MemoryStore.pending_events(_history_key).size()]
	if MemoryStore.is_updating(_history_key):
		status += " · updating…"
	elif MemoryStore.last_error.has(_history_key):
		status += " · last update failed: " + MemoryStore.last_error[_history_key]
	_history_list.add_child(_wrapped(status, 9))
	var any := false
	for section in MemoryStore.SECTIONS:
		for entry in m[section]:
			any = true
			_history_list.add_child(_wrapped("[%s · %s · from %s] %s" % [
				section, entry.share_scope, entry.learned_from, entry.text], 10))
	if not any:
		_history_list.add_child(_label("Nothing remembered yet.", 10))


func _on_health(ok: bool, mode: String) -> void:
	_status.text = "Backend: %s" % (mode if ok else "offline — start the server to chat")


# --- Input ---

func _send() -> void:
	if world.conversation.send(_reply_field.text):
		_reply_field.clear()
	_reply_field.release_focus()


## Clicking anywhere outside the reply field gives movement keys back to the player.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _reply_field.has_focus():
		if not _reply_field.get_global_rect().has_point(event.position):
			_reply_field.release_focus()


func _toggle(panel: Control) -> void:
	panel.visible = not panel.visible


# --- Widgets and theme ---

func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # so Space never presses a focused button
	b.custom_minimum_size.y = BUTTON_H
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	return l


func _wrapped(text: String, font_size: int) -> Label:
	var l := _label(text, font_size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 340
	return l


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 10
	t.set_stylebox("panel", "PanelContainer", _box(COLORS.panel, 6))
	for state in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(state, "Button", _box(COLORS[state], 5))
	t.set_stylebox("hover_pressed", "Button", _box(COLORS.pressed, 5))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("normal", "LineEdit", _box(COLORS.field, 5))
	t.set_stylebox("focus", "LineEdit", _box(COLORS.field, 5))
	for type in ["Label", "Button", "LineEdit"]:
		t.set_color("font_color", type, COLORS.text)
	for c in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", COLORS.text)
	t.set_color("font_disabled_color", "Button", Color("#7d776c"))
	t.set_color("caret_color", "LineEdit", COLORS.text)
	t.set_color("font_placeholder_color", "LineEdit", Color("#9a8f80"))
	t.set_constant("separation", "HBoxContainer", 4)
	t.set_constant("separation", "VBoxContainer", 4)
	return t


func _box(color: Color, margin: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = COLORS.border
	s.set_border_width_all(1)
	s.content_margin_left = margin + 2
	s.content_margin_right = margin + 2
	s.content_margin_top = margin - 2
	s.content_margin_bottom = margin - 2
	return s
