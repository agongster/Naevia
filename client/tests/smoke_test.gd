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
var _focus_losses := 0


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
	# Godot releases held buttons when the window loses focus, so a hold that starts
	# while macOS is still switching windows gets dropped. Take focus before input.
	DisplayServer.window_move_to_foreground()
	await _wait_until(DisplayServer.window_is_focused, 3.0)
	if not DisplayServer.window_is_focused():
		print("  warn window not focused; held-input checks may fail")
	await _run()
	if failures and _focus_losses > 1:
		print("  note the window lost focus %d times. Godot drops held mouse buttons on focus loss, so mining" % _focus_losses
			+ " and click failures may come from using the computer during the run. Rerun without touching it.")
	print("SMOKE %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(1 if failures else 0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# macOS hands focus back to the launching app a few seconds in; take it back.
		_focus_losses += 1
		print("  info window lost focus at %.1fs; refocusing" % (Time.get_ticks_msec() / 1000.0))
		DisplayServer.window_move_to_foreground.call_deferred()


func _run() -> void:
	_memory_validation_checks()
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
		await _hold_until(func() -> bool: return world.resources.get_cell_source_id(cell) == -1, 3.0)
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

	# Memory: the completed exchange is folded into the witch's own memory file.
	await _wait_until(func() -> bool: return MemoryStore.get_memory("witch").revision == 1, 5.0)
	var wm := MemoryStore.get_memory("witch")
	_check(wm.revision == 1 and wm.last_processed_event_id == hist[1].event_id, "witch memory at revision 1, cursor on last event")
	_check(FileAccess.file_exists(SaveManager.dir + "characters/witch.memory.json"), "witch memory file written")
	_check(_memory_text("witch").contains("exams") and wm.experiences[0].learned_from == "player"
		and wm.experiences[0].share_scope == "private", "witch remembers the exams privately, learned from the player")
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

	# Isolation: each character's memory holds only what they heard.
	await _wait_until(func() -> bool: return MemoryStore.get_memory("blacksmith").revision == 1, 5.0)
	_check(_memory_text("blacksmith").contains("grinding wheel") and not _memory_text("blacksmith").contains("exams"),
		"blacksmith remembers only his own conversation")
	_check(not _memory_text("witch").contains("grinding"), "witch memory untouched by the blacksmith chat")

	# Memory failure: chat still works, the old snapshot stays, and the events stay pending.
	var real_url := ApiClient.base_url
	ApiClient.base_url = "http://127.0.0.1:1"
	await _type_and_send("The bellows need patching too.")
	await _wait_until(func() -> bool: return not world.conversation.is_waiting(), 10.0)
	await _wait_until(func() -> bool: return MemoryStore.last_error.has("blacksmith"), 5.0)
	_check(MemoryStore.last_error.has("blacksmith") and MemoryStore.get_memory("blacksmith").revision == 1
		and MemoryStore.pending_events("blacksmith").size() == 2, "failed memory update keeps old snapshot and pending events")
	ApiClient.base_url = real_url

	# Persistence: rebuild the world from disk and compare.
	SaveManager.save_world()
	var stone := SaveManager.count("item.stone")
	var pos := world.player.global_position
	world.free()
	SaveManager._ready()  # re-read world.json as a fresh launch would
	MemoryStore._reset()  # drop cached memory; the restart resumes pending work
	MemoryStore.update_all()
	_load_world()
	await _frames(10)
	_check(SaveManager.count("item.stone") == stone, "stone persisted")
	_check(world.get_node("Furniture").get_child_count() == 3, "furniture persisted")
	_check(world.resources.get_cell_source_id(Vector2i(42, 17)) == -1, "mined cells persisted")
	_check(world.player.global_position.distance_to(pos) < 2.0, "player position persisted")
	await _shot("11_reloaded")

	# Memory across restarts: pending work resumed, and the witch recalls the exams.
	await _wait_until(func() -> bool: return MemoryStore.get_memory("blacksmith").revision == 2, 5.0)
	_check(_memory_text("blacksmith").contains("bellows"), "pending blacksmith memory update resumed after restart")
	_check(MemoryStore.get_memory("witch").revision == 1 and _memory_text("witch").contains("exams"), "witch memory reloaded from disk")
	world.contacts.summon_pigeon()
	await _seconds(3.0)
	await _click_world(world.contacts.pigeon.global_position + Vector2(0, -10))
	await _wait_until(world.conversation.is_open, 2.0)
	await _type_and_send("Any advice for studying?")
	await _wait_until(func() -> bool: return not world.conversation.is_waiting(), 10.0)
	var last: Dictionary = SaveManager.read_history("witch")[-1]
	_check(last.speaker == "witch" and last.text.contains("I remember") and last.text.contains("exams"),
		"witch reply draws on her saved memory")
	await _seconds(0.3)
	await _shot("12_witch_remembers")
	await _click_button("History")
	await _click_button("Memory")
	await _shot("13_memory_panel")
	world.ui._history_panel.visible = false
	world.ui._show_memory = false
	await _group_checks()


## Milestone D: Invite Both, turn-taking, recipient markers, shared history, and
## listeners learning from each other without seeing private memory.
func _group_checks() -> void:
	var witch := world.contacts.witch
	var smith := world.contacts.blacksmith
	await _teleport(Vector2(9 * 16 + 8, 18 * 16))
	await _click_button("Contacts")
	await _click_button("Invite Both")
	await _click_button("Contacts")
	_check(world.conversation.is_group() and witch.visible and smith.visible, "Invite Both opens a group conversation with both characters")
	await _wait_until(func() -> bool: return not witch.is_walking() and not smith.is_walking(), 6.0)
	_check(world.cell_at(witch.position + Vector2(0, -8)) == Vector2i(12, 17)
		and world.cell_at(smith.position + Vector2(0, -8)) == Vector2i(16, 17), "both walked in to their places in the house")
	await _shot("14_group_arrived")

	# Announcement: the first responder nominates the other, who answers; then control returns.
	await _type_and_send("I made the Dean's List!")
	await _wait_until(func() -> bool: return not world.conversation.is_waiting(), 10.0)
	var g := SaveManager.read_history("group")
	_check(g.size() == 3 and g[0].speaker == "player" and g[1].speaker == "witch" and g[1].addressee == "blacksmith"
		and g[2].speaker == "blacksmith" and g[2].addressee == "player", "witch addressed the blacksmith, he answered, control returned")
	var bubbles: Dictionary = world.ui.bubbles._bubbles
	_check(bubbles.has(witch) and bubbles.has(smith) and bubbles[witch].name_label.text == "Witch"
		and bubbles[smith].name_label.text == "Blacksmith", "each reply is in its speaker's own bubble")
	await _seconds(0.3)
	_check(not bubbles[witch].get_rect().intersects(bubbles[smith].get_rect()), "the two bubbles don't overlap")
	await _shot("15_group_exchange")

	# Privacy: group requests carry shared memory only, never private entries.
	var wreq: Dictionary = ApiClient.last_chat_requests.witch
	var breq: Dictionary = ApiClient.last_chat_requests.blacksmith
	_check(wreq.participants.size() == 3 and _only_shared(wreq.memory) and not JSON.stringify(wreq).contains("exams"),
		"witch's group request omits her private memory")
	_check(_only_shared(breq.memory) and not JSON.stringify(breq).contains("bellows")
		and not JSON.stringify(breq).contains("coming along"), "blacksmith's group request omits his private memory")

	# Naming a character makes them answer first.
	await _type_and_send("Blacksmith, how is the workshop?")
	await _wait_until(func() -> bool: return not world.conversation.is_waiting(), 10.0)
	g = SaveManager.read_history("group")
	_check(g[3].addressee == "blacksmith" and g[4].speaker == "blacksmith", "the named character answers first")

	# Turn cap: characters that keep nominating each other stop after three turns.
	await _type_and_send("#chain keep talking")
	await _wait_until(func() -> bool: return not world.conversation.is_waiting(), 10.0)
	var turns := _turns_after(SaveManager.read_history("group"), "#chain keep talking")
	_check(turns == 3, "at most three character turns per message (got %d)" % turns)

	# A message sent mid-turn cancels the queued turns after the current one.
	await _type_and_send("#chain again")
	await _wait_until(world.conversation.is_waiting, 2.0)
	await _type_and_send("Never mind, tea anyone?")
	_check(world.conversation.queued_message != "" or not world.conversation.is_waiting(), "second message accepted while a character talks")
	await _wait_until(func() -> bool: return not world.conversation.is_waiting() and world.conversation.queued_message == "", 10.0)
	var cut := _turns_after(SaveManager.read_history("group"), "#chain again")
	_check(cut < 3 and _turns_after(SaveManager.read_history("group"), "Never mind, tea anyone?") > 0,
		"new message cut the chain short (%d turn(s)) and got its own reply" % cut)

	# Closing: guests leave through the door, and each one's memory takes in what they heard.
	await _click_button("Close")
	_check(not world.conversation.is_open(), "group conversation closed")
	await _wait_until(func() -> bool: return not witch.visible and not smith.visible, 6.0)
	_check(not witch.visible and not smith.visible, "guests left through the door")
	var settled := func() -> bool:
		return MemoryStore.pending_events("witch").is_empty() and MemoryStore.pending_events("blacksmith").is_empty()
	await _wait_until(settled, 10.0)
	_check(_learned("witch", "blacksmith", "grinding wheel"), "witch learned the blacksmith's news from him (shared)")
	_check(_learned("blacksmith", "player", "Dean's List"), "blacksmith learned the announcement (shared)")
	_check(not _memory_text("blacksmith").contains("exams"), "blacksmith still knows nothing of the witch's private exams talk")

	# Restart: what was learned in the group survives.
	MemoryStore._reset()
	_check(_learned("witch", "blacksmith", "grinding wheel") and _memory_text("witch").contains("exams"),
		"after restart the witch keeps both her private and group knowledge")
	await _click_button("History")
	await _click_button("Group")
	await _shot("16_group_history")
	world.ui._history_panel.visible = false


func _only_shared(memory: Dictionary) -> bool:
	for section in MemoryStore.SECTIONS:
		for e in memory[section]:
			if e.share_scope != "shared":
				return false
	return true


## Character events after the player message with this text, up to the next player message.
func _turns_after(events: Array, player_text: String) -> int:
	var n := -1
	for ev in events:
		if ev.speaker == "player":
			if n >= 0:
				break
			if ev.text == player_text:
				n = 0
		elif n >= 0:
			n += 1
	return maxi(n, 0)


## True if id's memory has a shared entry learned from `from` containing the text.
func _learned(id: String, from: String, text: String) -> bool:
	var m := MemoryStore.get_memory(id)
	for section in MemoryStore.SECTIONS:
		for e in m[section]:
			if e.learned_from == from and e.share_scope == "shared" and String(e.text).contains(text):
				return true
	return false


## Client-side proposal checks (SPEC 5.4), without the backend.
func _memory_validation_checks() -> void:
	var job := {"request_id": "m1", "base_revision": 0, "last_event_id": "e2", "allowed": {"e1": true, "e2": true}}
	var good := MemoryStore.empty_memory("witch")
	good.revision = 1.0
	good.last_processed_event_id = "e2"
	good.facts = [{"id": "f1", "text": "Has exams soon.", "source_event_ids": ["e1"],
		"learned_from": "player", "share_scope": "private"}]
	var check := func(m: Dictionary, cid: String) -> String:
		return MemoryStore._check_proposal("witch", job,
			{"request_id": "m1", "character_id": cid, "base_revision": 0, "memory": m})
	_check(check.call(good, "witch") == "", "valid memory proposal accepted")
	var bad := good.duplicate(true)
	bad.facts[0].source_event_ids = ["e99"]
	_check(check.call(bad, "witch") != "", "proposal citing an invented event rejected")
	bad = good.duplicate(true)
	bad.revision = 2.0
	_check(check.call(bad, "witch") != "", "proposal skipping a revision rejected")
	bad = good.duplicate(true)
	bad.facts[0].text = "x".repeat(MemoryStore.ENTRY_CAP + 1)
	_check(check.call(bad, "witch") != "", "oversized memory entry rejected")
	bad = good.duplicate(true)
	bad.facts[0].share_scope = "public"
	_check(check.call(bad, "witch") != "", "invalid share scope rejected")
	_check(check.call(good, "blacksmith") != "", "proposal for another character rejected")


func _memory_text(id: String) -> String:
	return JSON.stringify(MemoryStore.get_memory(id))


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


## Keeps the simulated button down until cond holds. Focus changes make Godot
## release held buttons, so the press is re-sent if that happens, as a real
## still-held button would be.
func _hold_until(cond: Callable, timeout: float) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < deadline:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_mouse_button(MOUSE_BUTTON_LEFT, true)
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
