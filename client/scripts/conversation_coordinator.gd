class_name ConversationCoordinator
extends Node
## ConversationCoordinator: participants, speaker order, and conversation IDs (SPEC 4.2, 4.3).
## Private mode talks to one character. Group mode (Invite Both) talks to both:
## a character the player names answers first, otherwise the first responder
## alternates; a reply can nominate the other character with @to:; at most
## MAX_TURNS character turns per player message, then control returns to the
## player. A message to everyone gives each character a turn (they may decline
## with "..."), so neither is left silent when the first one answers the player.
## A message sent during group turns cancels the queued turns after the current one. Request IDs guard against late replies landing in a different
## conversation. When a message's turns finish, each listener's memory update is queued.

signal opened
signal closed
signal state_changed

const RECENT_LIMIT := 12
const MAX_TURNS := 3
const GROUP := "group"

var conversation_id := ""
## The character in private mode, or GROUP. Also the history file key.
var character_id := ""
var participants: Array = []  # character ids present, without "player"
var label := ""
var scene_context := ""
var anchors: Dictionary = {}  # character id -> Node2D the bubble attaches to
var pending_request := ""
var speaker := ""             # character whose turn is streaming, or failed and awaiting retry
var turns_taken := 0
var queued_message := ""      # player message sent while group turns were running
var _to_all := false          # the current player message was addressed to everyone
var _spoken: Array = []       # characters who have had a turn for the current player message
var last_error := ""

var _reply := ""
var _first_responder := 0     # alternates the first responder in group mode

@onready var world: World = get_parent()


func _ready() -> void:
	ApiClient.text_delta.connect(_on_delta)
	ApiClient.reply_done.connect(_on_done)
	ApiClient.reply_failed.connect(_on_failed)


func is_open() -> bool:
	return conversation_id != ""


func is_group() -> bool:
	return character_id == GROUP


func is_waiting() -> bool:
	return pending_request != ""


## One pending player submission per conversation (SPEC 4.2). In group mode the
## player may send while characters talk; it waits for the current turn.
func can_send() -> bool:
	return is_open() and (not is_waiting() or (is_group() and queued_message == ""))


func open(id: String, anchor_node: Node2D, display_label: String, context: String) -> void:
	_open(id, [id], {id: anchor_node}, display_label, context)


func open_group(anchor_nodes: Dictionary, display_label: String, context: String) -> void:
	_open(GROUP, anchor_nodes.keys(), anchor_nodes, display_label, context)


func _open(key: String, ids: Array, anchor_nodes: Dictionary, display_label: String, context: String) -> void:
	if is_open() and character_id == key:
		return
	close()
	conversation_id = _new_id("c")
	character_id = key
	participants = ids
	anchors = anchor_nodes
	label = display_label
	scene_context = context
	speaker = ""
	turns_taken = 0
	queued_message = ""
	last_error = ""
	opened.emit()


## Closing cancels any reply still streaming; the player's message stays in history.
func close() -> void:
	if not is_open():
		return
	if pending_request:
		ApiClient.cancel(pending_request)
		pending_request = ""
	for a: Node2D in anchors.values():
		world.ui.bubbles.dismiss(a)
	queued_message = ""
	conversation_id = ""
	_queue_memory_updates()
	closed.emit()


func send(text: String) -> bool:
	text = text.strip_edges()
	if text.is_empty() or not can_send():
		return false
	if is_waiting():
		queued_message = text  # taken up when the current turn ends (SPEC 4.3)
		state_changed.emit()
		return true
	_start_player_message(text)
	return true


## Re-requests the failed turn only; the player's message was already saved once.
func retry() -> void:
	if is_open() and not is_waiting() and last_error:
		_request_reply()


func _start_player_message(text: String) -> void:
	var addressee := character_id
	speaker = character_id
	if is_group():
		var named := participants.filter(func(id: String) -> bool: return _mentions(text, id))
		if named.size() == 1:
			addressee = named[0]
			speaker = named[0]
		else:
			addressee = "all"
			speaker = participants[_first_responder % participants.size()]
			_first_responder += 1
	SaveManager.append_history(character_id, _event("player", addressee, text))
	turns_taken = 0
	_to_all = addressee == "all"
	_spoken = []
	_request_reply()


func _request_reply() -> void:
	last_error = ""
	_reply = ""
	var request := _new_id("r")
	pending_request = request
	world.ui.bubbles.show_waiting(anchors[speaker], _bubble_label())
	state_changed.emit()
	# Context uses the newest memory (SPEC 6.2 step 1); the world keeps running meanwhile.
	while MemoryStore.is_updating(speaker):
		await MemoryStore.settled
	if pending_request != request:
		return  # closed while waiting
	var recent: Array = []
	for ev in SaveManager.read_history(character_id, RECENT_LIMIT):
		recent.append({"event_id": ev.event_id, "speaker": ev.speaker, "addressee": ev.addressee,
			"audience": ev.audience, "text": ev.text})
	ApiClient.stream_chat({
		"request_id": pending_request,
		"conversation_id": conversation_id,
		"speaker_id": speaker,
		"participants": ["player"] + participants,
		"profile": Defs.characters[speaker],
		# Group prompts get shareable memory only (SPEC 6.3); the backend filters again.
		"memory": MemoryStore.shareable(speaker) if is_group() else MemoryStore.get_memory(speaker),
		"recent_messages": recent,
		"scene_context": scene_context,
	})


func _on_delta(request_id: String, text: String) -> void:
	if request_id != pending_request:
		return
	_reply += text
	world.ui.bubbles.show_text(anchors[speaker], _bubble_label(), _reply, true)


## Only a completed character turn is committed to history (SPEC 5.3). A reply of
## just "..." means the character declined to add anything.
func _on_done(request_id: String, speaker_id: String, addressee: String) -> void:
	if request_id != pending_request:
		return
	pending_request = ""
	var text := _reply.strip_edges()
	var declined := text.replace("…", "...").trim_suffix(".").trim_suffix(".").trim_suffix(".") == ""
	if declined:
		world.ui.bubbles.dismiss(anchors[speaker])
	else:
		SaveManager.append_history(character_id, _event(speaker_id, addressee, text))
		world.ui.bubbles.show_text(anchors[speaker], _bubble_label(), text, false)
	turns_taken += 1
	_spoken.append(speaker)
	var next := _next_speaker(addressee if not declined else "player")
	if queued_message:
		_take_queued_message()
	elif next:
		speaker = next
		_request_reply()
	else:
		_queue_memory_updates()
		state_changed.emit()


## Group turn order after a reply (SPEC 4.3): a nominated character answers;
## otherwise, for a message to everyone, a character who hasn't spoken yet goes.
func _next_speaker(addressee: String) -> String:
	if not is_group() or turns_taken >= MAX_TURNS:
		return ""
	if addressee in participants and addressee != speaker:
		return addressee
	if _to_all:
		for id in participants:
			if not id in _spoken:
				return id
	return ""


func _on_failed(request_id: String, message: String) -> void:
	if request_id != pending_request:
		return
	pending_request = ""
	if queued_message:
		_take_queued_message()  # the newer message replaces the failed turn
		return
	last_error = message
	world.ui.bubbles.show_error(anchors[speaker], _bubble_label(), message, retry)
	state_changed.emit()


func _take_queued_message() -> void:
	var text := queued_message
	queued_message = ""
	_start_player_message(text)


## Listeners fold what they heard into their own memory (SPEC 6.2 step 4, 6.3).
func _queue_memory_updates() -> void:
	for id in participants:
		MemoryStore.request_update(id)


func _bubble_label() -> String:
	return Defs.characters[speaker].name if is_group() else label


func _mentions(text: String, id: String) -> bool:
	var lower := text.to_lower()
	return lower.contains(id) or lower.contains(String(Defs.characters[id].name).to_lower())


func _event(from: String, addressee: String, text: String) -> Dictionary:
	return {
		"event_id": _new_id("e"),
		"conversation_id": conversation_id,
		"speaker": from,
		"addressee": addressee,
		"audience": ["player"] + participants,
		"text": text,
		"time": Time.get_datetime_string_from_system(true),
	}


static func _new_id(prefix: String) -> String:
	return "%s%d_%04d" % [prefix, int(Time.get_unix_time_from_system() * 1000.0), randi() % 10000]
