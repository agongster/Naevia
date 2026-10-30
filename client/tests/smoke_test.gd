extends Node
## End-to-end smoke test for the playable demo. Drives the real World scene with
## simulated mouse/keyboard input, asserts game state, and saves screenshots.
##
## Needs a rendering window (not --headless) and the backend in mock mode:
##   godot --path client --fixed-fps 60 res://tests/smoke_test.tscn -- --save-slot=smoke --shots=/tmp/shots \
##       [--backend-url=http://127.0.0.1:8010]
## Uses a separate save slot and refuses to run on "default".

var world: World
var shots := ""
var failures := 0
var _mouse := Vector2.ZERO  # simulated pointer, viewport coordinates


func _ready() -> void:
	assert(SaveManager.slot != "default", "smoke test must use --save-slot=<test slot>")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots = arg.get_slice("=", 1)
			DirAccess.make_dir_recursive_absolute(shots)
	# Let real mouse events pass through the window so a moving cursor can't
	# interfere with the simulated pointer.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)]))
	SaveManager.wipe_slot()
	await _run()
	print("SMOKE %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(1 if failures else 0)


func _run() -> void:
	_load_world()
	await _frames(20)
	await _shot("01_start")

	# Movement: holding D moves right and plays the walk animation.
	var x0 := world.player.global_position.x
	Input.action_press("move_right")
	await _seconds(0.5)
	_check(world.player.sprite.animation == "walk", "walk animation while moving")
	await _seconds(0.5)
	Input.action_release("move_right")
	_check(world.player.global_position.x > x0 + 40, "player walked right")

	# Mining: stand beside the stone mound and hold the mouse on reachable cells.
	await _teleport(Vector2(40 * 16 + 8, 18 * 16))
	for cell in [Vector2i(42, 17), Vector2i(42, 18), Vector2i(43, 16)]:
		await _mouse_move_world(world.cell_center(cell))
		_mouse_button(MOUSE_BUTTON_LEFT, true)
		await _seconds(0.55)
		if cell == Vector2i(42, 17):
			_check(world.player.sprite.animation == "mine", "mine animation while holding")
			await _shot("02_mining_cracks")
		await _seconds(0.6)
		_mouse_button(MOUSE_BUTTON_LEFT, false)
		await _frames(2)
	_check(SaveManager.count("item.stone") == 3, "three stone mined (got %d)" % SaveManager.count("item.stone"))
	_check(world.resources.get_cell_source_id(Vector2i(42, 17)) == -1, "mined cell removed")

	# Out of reach: a far cell is not mined.
	await _mouse_move_world(world.cell_center(Vector2i(56, 20)))
	_mouse_button(MOUSE_BUTTON_LEFT, true)
	await _seconds(1.2)
	_mouse_button(MOUSE_BUTTON_LEFT, false)
	_check(SaveManager.count("item.stone") == 3, "out-of-reach cell not mined")
	await _shot("03_after_mining")

	# Furniture: buy a table through the Bag UI and place it in the house.
	await _teleport(world.spawn_position() - Vector2(12 * 16, 0))
	await _click_button("Bag")
	await _click_button("Table")
	await _mouse_move_world(world.cell_center(Vector2i(8, 16)))
	await _shot("04_table_preview")
	await _click_world(world.cell_center(Vector2i(8, 16)))
	_check(SaveManager.world.placed.size() == 1, "table placed")
	_check(SaveManager.count("item.stone") == 0, "table cost three stone")

	# UI consumes clicks: clicking the Bag panel must not place or mine.
	SaveManager.add_material("item.stone", 9)
	await _click_button("Chair")
	await _click_button("Lamp")  # clicking a bag button while placing switches item, not place
	_check(SaveManager.world.placed.size() == 1, "click on UI did not place furniture")
	await _click_world(world.cell_center(Vector2i(13, 16)))
	await _click_button("Chair")
	await _click_world(world.cell_center(Vector2i(11, 17)))
	_check(SaveManager.world.placed.size() == 3, "lamp and chair placed")
	_check(SaveManager.count("item.stone") == 3, "lamp and chair cost six stone")

	# Arrange: move the table, then store the chair and place it again for free.
	await _click_button("Arrange")
	await _click_world(world.cell_center(Vector2i(8, 17)))
	await _click_world(world.cell_center(Vector2i(17, 17)))
	var table_cell: Array = SaveManager.world.placed.filter(func(r): return r.def == "furniture.table")[0].cell
	_check(table_cell == [16, 17], "table moved (now %s)" % [table_cell])
	await _click_world(world.cell_center(Vector2i(11, 17)))
	await _click_button("Store")
	_check(SaveManager.stored("furniture.chair") == 1 and SaveManager.world.placed.size() == 2, "chair stored")
	await _click_button("Arrange")
	await _click_button("Chair")
	await _click_world(world.cell_center(Vector2i(6, 17)))
	_check(SaveManager.stored("furniture.chair") == 0 and SaveManager.count("item.stone") == 3, "stored chair placed without paying")
	await _click_button("Bag")
	await _shot("05_furnished")

	# Conversation via pigeon: click it, type, Send; the world keeps running meanwhile.
	world.contacts.summon_pigeon()
	await _seconds(3.0)
	await _shot("06_pigeon_arrived")
	await _click_world(world.contacts.pigeon.global_position + Vector2(0, -10))
	await _wait_until(world.conversation.is_open, 2.0)
	_check(world.conversation.is_open() and world.conversation.character_id == "witch", "pigeon opens witch conversation")
	await _type_and_send("I have exams next week and I'm a bit nervous.")
	_check(world.get_viewport().gui_get_focus_owner() == null, "send released text focus")
	Input.action_press("move_left")
	await _seconds(0.4)
	Input.action_release("move_left")
	await _shot("07_streaming")
	await _wait_until(func() -> bool: return not world.conversation.is_waiting(), 10.0)
	await _seconds(0.3)
	await _shot("08_witch_reply")
	var hist := SaveManager.read_history("witch")
	_check(hist.size() == 2 and hist[1].speaker == "witch", "exchange committed to witch history")
	await _click_button("Close")
	_check(not world.conversation.is_open(), "conversation closed")

	# Typing must not move the player.
	world.contacts.summon_blacksmith()
	await _wait_until(func() -> bool: return not world.contacts.blacksmith.is_walking(), 15.0)
	await _click_world(world.contacts.blacksmith.global_position + Vector2(0, -24))
	_check(world.conversation.character_id == "blacksmith", "blacksmith opens his conversation")
	await _click_line_edit()
	var px := world.player.global_position.x
	_key(KEY_D, true)
	await _seconds(0.3)
	_key(KEY_D, false)
	_check(absf(world.player.global_position.x - px) < 1.0, "typing D in the field did not move the player")
	_check(world.ui._reply_field.text.to_lower() == "d", "the key went into the field instead")
	world.ui._reply_field.clear()

	# API failure: clear error, message kept, retry does not duplicate the player's message.
	var real_port := ApiClient._port
	ApiClient._port = 1
	await _type_and_send("How is the grinding wheel coming along?")
	await _wait_until(func() -> bool: return world.conversation.last_error != "", 5.0)
	await _shot("09_api_error")
	_check(world.conversation.last_error != "", "unreachable backend shows an error")
	ApiClient._port = real_port
	await _click_button("Retry")
	await _wait_until(func() -> bool: return not world.conversation.is_waiting(), 10.0)
	var bh := SaveManager.read_history("blacksmith")
	_check(bh.size() == 2 and bh[0].speaker == "player" and bh[1].speaker == "blacksmith", "retry completed without duplicating (%d events)" % bh.size())
	await _seconds(0.3)
	await _shot("10_blacksmith_reply")

	# Persistence: rebuild the world from disk and compare.
	SaveManager.save_world()
	var stone := SaveManager.count("item.stone")
	var pos := world.player.global_position
	world.free()
	SaveManager._ready()  # re-read world.json as a fresh launch would
	_load_world()
	await _frames(10)
	_check(SaveManager.count("item.stone") == stone, "stone persisted")
	_check(world.get_node("Furniture").get_child_count() == 3, "furniture persisted")
	_check(world.resources.get_cell_source_id(Vector2i(42, 17)) == -1, "mined cells persisted")
	_check(world.player.global_position.distance_to(pos) < 2.0, "player position persisted")
	await _shot("11_reloaded")


# --- Helpers ---

func _load_world() -> void:
	world = load("res://scenes/World.tscn").instantiate()
	add_child(world)


## Moves the player and snaps the smoothed camera so screen->world mapping is stable.
func _teleport(p: Vector2) -> void:
	world.player.global_position = p
	await _frames(2)
	world.player.get_node("Camera2D").reset_smoothing()
	await _frames(5)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


## Timeout is wall-clock: with --fixed-fps, game time can run faster than the backend.
func _wait_until(cond: Callable, timeout: float) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	if shots:
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shots, name])


## Viewport (640 x 360) coordinates -> window coordinates for input events.
func _to_window(viewport_pos: Vector2) -> Vector2:
	return get_viewport().get_screen_transform() * viewport_pos


func _world_to_viewport(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * p


func _mouse_move_world(p: Vector2) -> void:
	await _mouse_move(_world_to_viewport(p))


func _mouse_move(viewport_pos: Vector2) -> void:
	_mouse = viewport_pos
	var ev := InputEventMouseMotion.new()
	ev.position = _to_window(viewport_pos)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	await _frames(2)


func _mouse_button(button: MouseButton, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = _to_window(_mouse)
	ev.global_position = ev.position
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	Input.parse_input_event(ev)


func _click_at(viewport_pos: Vector2) -> void:
	await _mouse_move(viewport_pos)
	_mouse_button(MOUSE_BUTTON_LEFT, true)
	await _frames(2)
	_mouse_button(MOUSE_BUTTON_LEFT, false)
	await _frames(3)


func _click_world(p: Vector2) -> void:
	await _camera_settle()
	await _click_at(_world_to_viewport(p))


func _camera_settle() -> void:
	await _seconds(0.4)


func _click_button(text_prefix: String) -> void:
	var b := _find_button(world.ui, text_prefix)
	_check(b != null, "button '%s' visible" % text_prefix)
	if b:
		await _click_at(b.get_global_rect().get_center())


func _find_button(node: Node, prefix: String) -> Button:
	for c in node.get_children():
		if c is Button and c.is_visible_in_tree() and not c.disabled and c.text.begins_with(prefix):
			return c
		var found := _find_button(c, prefix)
		if found:
			return found
	return null


func _click_line_edit() -> void:
	await _click_at(world.ui._reply_field.get_global_rect().get_center())


func _type_and_send(text: String) -> void:
	await _click_line_edit()
	_check(world.ui._reply_field.has_focus(), "reply field focused by click")
	world.ui._reply_field.insert_text_at_caret(text)
	await _click_button("Send")


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.unicode = code if pressed else 0
	ev.pressed = pressed
	Input.parse_input_event(ev)
