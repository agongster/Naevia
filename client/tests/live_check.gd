extends "res://tests/smoke_test.gd"
## Live-model check in the real game (SPEC 11.2). Plays private chats with both
## characters and one group conversation against a backend in LIVE mode, checks
## streaming into bubbles, marker stripping, request privacy and memory updates,
## and prints every reply so a person can judge voice and relevance. Live replies
## differ every run, so only structural properties are asserted.
##
##   godot --path client --fixed-fps 60 res://tests/live_check.tscn -- --save-slot=live --shots=DIR \
##       --backend-url=http://127.0.0.1:8010
## Makes roughly 10-15 model calls. Uses its own save slot and wipes it first.

const REPLY_TIMEOUT := 60.0


func _run() -> void:
	_load_world()
	await _frames(20)
	var mode := [""]
	ApiClient.health_checked.connect(func(_ok: bool, m: String) -> void: mode[0] = m)
	ApiClient.check_health()
	await _wait_until(func() -> bool: return mode[0] != "", 5.0)
	_check(mode[0] == "live", "backend reports live mode (got '%s')" % mode[0])
	if mode[0] != "live":
		return
	await _teleport(Vector2(9 * 16 + 8, 18 * 16))

	# Private: witch, via pigeon.
	world.contacts.summon_pigeon()
	await _seconds(3.0)
	await _click_world(world.contacts.pigeon.global_position + Vector2(0, -10))
	await _wait_until(world.conversation.is_open, 2.0)
	await _live_turn("My statistics exam is on Thursday and I'm honestly pretty nervous about it.", "witch")
	await _shot("live_01_witch")
	await _click_button("Close")
	await _wait_memory("witch", 1)
	_check(_memory_text("witch").contains("Thursday") or _memory_text("witch").to_lower().contains("exam"),
		"witch's memory holds the exam detail")
	print("  live witch memory: ", _entries("witch"))

	# Private: blacksmith.
	world.contacts.summon_blacksmith()
	await _wait_until(func() -> bool: return not world.contacts.blacksmith.is_walking(), 15.0)
	await _click_world(world.contacts.blacksmith.global_position + Vector2(0, -24))
	await _live_turn("Hey! What have you been working on lately?", "blacksmith")
	await _shot("live_02_blacksmith")
	_check(not JSON.stringify(ApiClient.last_chat_requests.blacksmith).contains("Thursday"),
		"blacksmith's request has nothing from the witch's private chat")
	await _click_button("Close")

	# Private follow-up: does the witch use what she remembers? (judged by reading)
	world.contacts.summon_pigeon()
	await _seconds(3.0)
	await _click_world(world.contacts.pigeon.global_position + Vector2(0, -10))
	await _wait_until(world.conversation.is_open, 2.0)
	await _live_turn("Any idea what I should do the night before?", "witch")
	await _click_button("Close")

	# Group: an announcement to everyone.
	await _click_button("Contacts")
	await _click_button("Invite Both")
	await _click_button("Contacts")
	await _wait_until(func() -> bool: return not world.contacts.witch.is_walking() and not world.contacts.blacksmith.is_walking(), 6.0)
	await _type_and_send("Guess what, I made the Dean's List!")
	await _wait_until(func() -> bool: return not world.conversation.is_waiting(), REPLY_TIMEOUT * 3)
	var group := SaveManager.read_history("group")
	var replies := group.filter(func(e: Dictionary) -> bool: return e.speaker != "player")
	for e in group:
		print("  live group [%s -> %s] %s" % [e.speaker, e.addressee, e.text])
	_check(replies.size() >= 1 and replies.size() <= 3, "group gave 1-3 character turns (got %d)" % replies.size())
	_check(replies.all(func(e: Dictionary) -> bool: return not String(e.text).contains("@to:")), "no @to: markers shown or saved")
	_check(replies.any(func(e: Dictionary) -> bool: return e.speaker == "witch")
		and replies.any(func(e: Dictionary) -> bool: return e.speaker == "blacksmith"), "both characters spoke (or declined) in turn")
	var wreq: Dictionary = ApiClient.last_chat_requests.witch
	_check(_only_shared(wreq.memory) and not JSON.stringify(wreq).contains("Thursday"),
		"witch's group request omits her private memory")
	await _seconds(0.5)
	await _shot("live_03_group")
	await _click_button("Close")
	await _wait_memory("blacksmith", 2)
	_check(_learned("blacksmith", "player", "Dean"), "blacksmith learned the announcement as shared knowledge")
	print("  live blacksmith memory: ", _entries("blacksmith"))
	print("  live witch memory: ", _entries("witch"))
	for id in ["witch", "blacksmith"]:
		_check(not MemoryStore.last_error.has(id), "%s memory updates all accepted (%s)" % [id, MemoryStore.last_error.get(id, "ok")])


## Sends a message and checks the reply streamed into the bubble before finishing.
func _live_turn(text: String, who: String) -> void:
	var partial_seen := [false]
	await _type_and_send(text)
	var deadline := Time.get_ticks_msec() + int(REPLY_TIMEOUT * 1000.0)
	while world.conversation.is_waiting() and Time.get_ticks_msec() < deadline:
		if world.conversation._reply != "":
			partial_seen[0] = true
		await get_tree().process_frame
	var last: Dictionary = SaveManager.read_history(who)[-1]
	print("  live %s: %s" % [who, last.text])
	_check(last.speaker == who and world.conversation.last_error == "", "%s replied (%s)" % [who, world.conversation.last_error])
	_check(partial_seen[0], "%s's reply streamed into the bubble before it finished" % who)
	_check(not String(last.text).contains("@to:"), "%s's reply has no @to: marker" % who)


func _wait_memory(id: String, revision: int) -> void:
	await _wait_until(func() -> bool: return MemoryStore.get_memory(id).revision >= revision and not MemoryStore.is_updating(id), REPLY_TIMEOUT)
	_check(MemoryStore.get_memory(id).revision >= revision, "%s memory reached revision %d (error: %s)" % [id, revision, MemoryStore.last_error.get(id, "none")])


func _entries(id: String) -> String:
	var out := PackedStringArray()
	var m := MemoryStore.get_memory(id)
	for section in MemoryStore.SECTIONS:
		for e in m[section]:
			out.append("\n      [%s %s from %s] %s" % [section, e.share_scope, e.learned_from, e.text])
	return "".join(out)
