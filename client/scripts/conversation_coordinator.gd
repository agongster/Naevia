class_name ConversationCoordinator
extends Node
## ConversationCoordinator: participants, speaker order, and conversation IDs (SPEC 4.2, 4.3).
## Private mode only so far; group mode (Invite Both) is milestone D.
## Request IDs guard against late replies landing in a different conversation.

signal opened
signal closed
signal state_changed

const RECENT_LIMIT := 12

var conversation_id := ""
var character_id := ""
var label := ""
var scene_context := ""
var anchor: Node2D
var pending_request := ""
var last_error := ""

var _reply := ""

@onready var world: World = get_parent()


func _ready() -> void:
	ApiClient.text_delta.connect(_on_delta)
	ApiClient.reply_done.connect(_on_done)
	ApiClient.reply_failed.connect(_on_failed)


func is_open() -> bool:
	return conversation_id != ""


func is_waiting() -> bool:
	return pending_request != ""


func open(id: String, anchor_node: Node2D, display_label: String, context: String) -> void:
	if is_open() and anchor_node == anchor:
		return
	close()
	conversation_id = _new_id("c")
	character_id = id
	anchor = anchor_node
	label = display_label
	scene_context = context
	last_error = ""
	opened.emit()


## Closing cancels any reply still streaming; the player's message stays in history.
func close() -> void:
	if not is_open():
		return
	if pending_request:
		ApiClient.cancel(pending_request)
		pending_request = ""
	world.ui.bubbles.dismiss(anchor)
	conversation_id = ""
	closed.emit()


func send(text: String) -> bool:
	text = text.strip_edges()
	if text.is_empty() or is_waiting() or not is_open():
		return false
	SaveManager.append_history(character_id, _event("player", character_id, text))
	_request_reply()
	return true


## Re-requests the reply only; the player's message was already saved once.
func retry() -> void:
	if is_open() and not is_waiting() and last_error:
		_request_reply()


func _request_reply() -> void:
	last_error = ""
	_reply = ""
	pending_request = _new_id("r")
	world.ui.bubbles.show_waiting(anchor, label)
	var recent: Array = []
	for ev in SaveManager.read_history(character_id, RECENT_LIMIT):
		recent.append({"event_id": ev.event_id, "speaker": ev.speaker, "addressee": ev.addressee,
			"audience": ev.audience, "text": ev.text})
	ApiClient.stream_chat({
		"request_id": pending_request,
		"conversation_id": conversation_id,
		"speaker_id": character_id,
		"participants": ["player", character_id],
		"profile": Defs.characters[character_id],
		"memory": _empty_memory(character_id),  # MemoryStore arrives with milestone C
		"recent_messages": recent,
		"scene_context": scene_context,
	})
	state_changed.emit()


func _on_delta(request_id: String, text: String) -> void:
	if request_id != pending_request:
		return
	_reply += text
	world.ui.bubbles.show_text(anchor, label, _reply, true)


## Only a completed character turn is committed to history (SPEC 5.3).
func _on_done(request_id: String, speaker_id: String, addressee: String) -> void:
	if request_id != pending_request:
		return
	pending_request = ""
	var text := _reply.strip_edges()
	SaveManager.append_history(character_id, _event(speaker_id, addressee, text))
	world.ui.bubbles.show_text(anchor, label, text, false)
	state_changed.emit()


func _on_failed(request_id: String, message: String) -> void:
	if request_id != pending_request:
		return
	pending_request = ""
	last_error = message
	world.ui.bubbles.show_error(anchor, label, message, retry)
	state_changed.emit()


func _event(speaker: String, addressee: String, text: String) -> Dictionary:
	return {
		"event_id": _new_id("e"),
		"conversation_id": conversation_id,
		"speaker": speaker,
		"addressee": addressee,
		"audience": ["player", character_id],
		"text": text,
		"time": Time.get_datetime_string_from_system(true),
	}


static func _empty_memory(id: String) -> Dictionary:
	return {"schema_version": 1, "character_id": id, "revision": 0, "last_processed_event_id": null,
		"facts": [], "ongoing": [], "experiences": []}


static func _new_id(prefix: String) -> String:
	return "%s%d_%04d" % [prefix, int(Time.get_unix_time_from_system() * 1000.0), randi() % 10000]
