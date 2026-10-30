extends Node
## MemoryStore: each character's concise memory snapshot (SPEC 5.4, 6.1, 6.2).
## After a completed exchange, sends that character's memory plus the events they
## heard since the processing cursor to /v1/memory/update. The proposal is
## re-validated here and replaces characters/<id>.memory.json atomically.
## Updates are serialized per character. On any failure the old snapshot is kept,
## the events stay pending, and a timer retries; launching the game also resumes
## pending work, since history is saved before any update is requested.

signal updated(character_id: String)
## Emitted when a character has no update in flight any more (success or failure).
signal settled(character_id: String)

const TEXT_CAP := 3000   # combined entry text per character (SPEC 6.1, proposal P4)
const ENTRY_CAP := 400
const BATCH_LIMIT := 24  # events per request; the rest go in the next request
const RETRY_SECONDS := 20.0
const SECTIONS := ["facts", "ongoing", "experiences"]

## Last failure per character, for the History panel and debugging. Never holds dialogue.
var last_error: Dictionary = {}

var _cache: Dictionary = {}      # character id -> snapshot
var _in_flight: Dictionary = {}  # character id -> job {request_id, base_revision, last_event_id, allowed}
var _retry_timer: Timer


func _ready() -> void:
	_retry_timer = Timer.new()
	_retry_timer.one_shot = true
	_retry_timer.wait_time = RETRY_SECONDS
	_retry_timer.timeout.connect(update_all)
	add_child(_retry_timer)
	SaveManager.wiped.connect(_reset)
	update_all.call_deferred()


func update_all() -> void:
	for id in Defs.characters:
		request_update(id)


func get_memory(id: String) -> Dictionary:
	if not _cache.has(id):
		var loaded: Variant = SaveManager.read_json(_path(id))
		if loaded == null:
			_cache[id] = empty_memory(id)
		elif validate_snapshot(loaded, id) == "":
			_cache[id] = _normalize(loaded)
		else:
			# Keep the bad file on disk until a valid update replaces it.
			push_warning("Ignoring invalid memory file for %s: %s" % [id, validate_snapshot(loaded, id)])
			_cache[id] = empty_memory(id)
	return _cache[id]


func is_updating(id: String) -> bool:
	return _in_flight.has(id)


## Shared entries only, for group prompts (SPEC 6.3).
func shareable(id: String) -> Dictionary:
	var m := get_memory(id).duplicate(true)
	for section in SECTIONS:
		m[section] = m[section].filter(func(e: Dictionary) -> bool: return e.share_scope == "shared")
	return m


## Events this character heard that the memory has not processed yet: their private
## history and the group transcript, merged in time order.
func pending_events(id: String) -> Array:
	var events := SaveManager.read_history(id) + SaveManager.read_history(ConversationCoordinator.GROUP)
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _event_ms(a) < _event_ms(b))
	var cursor: Variant = get_memory(id).last_processed_event_id
	if cursor != null:
		var at := events.find_custom(func(e: Dictionary) -> bool: return e.event_id == cursor)
		if at != -1:
			events = events.slice(at + 1)
	return events.filter(func(e: Dictionary) -> bool: return id in e.audience)


func request_update(id: String) -> void:
	if _in_flight.has(id):
		return  # the finished request re-checks for newer events
	var events := pending_events(id).slice(0, BATCH_LIMIT)
	if events.is_empty():
		return
	var memory := get_memory(id)
	var new_events: Array = []
	var allowed := {}
	for ev in events:
		new_events.append({"event_id": ev.event_id, "speaker": ev.speaker, "addressee": ev.addressee,
			"audience": ev.audience, "text": ev.text})
		allowed[ev.event_id] = true
	for section in SECTIONS:
		for entry in memory[section]:
			for source in entry.source_event_ids:
				allowed[source] = true
	var job := {
		"request_id": "m%d_%04d" % [int(Time.get_unix_time_from_system() * 1000.0), randi() % 10000],
		"base_revision": int(memory.revision),
		"last_event_id": events[-1].event_id,
		"allowed": allowed,
	}
	_in_flight[id] = job
	ApiClient.post_json("/v1/memory/update", {
		"request_id": job.request_id,
		"character_id": id,
		"base_revision": job.base_revision,
		"memory": memory,
		"new_events": new_events,
	}, func(code: int, data: Variant) -> void: _on_result(id, job, code, data))


func _on_result(id: String, job: Dictionary, code: int, data: Variant) -> void:
	if _in_flight.get(id) != job:
		return  # the save was wiped while this request was out
	_in_flight.erase(id)
	var err := ""
	if code == 0:
		err = "backend unreachable"
	elif code != 200:
		err = "backend rejected the update (HTTP %d)" % code
	else:
		err = _check_proposal(id, job, data)
	if err:
		last_error[id] = err
		push_warning("Memory update for %s failed: %s; events stay pending" % [id, err])
		if _retry_timer.is_stopped():
			_retry_timer.start()
	else:
		var memory := _normalize(data.memory)
		if SaveManager.write_json_atomic(_path(id), memory):
			_cache[id] = memory
			last_error.erase(id)
			updated.emit(id)
			request_update(id)  # events that arrived meanwhile, or the next batch
	if not _in_flight.has(id):
		settled.emit(id)


## The client's own checks before replacing the file (SPEC 5.4); the backend checks too.
func _check_proposal(id: String, job: Dictionary, data: Variant) -> String:
	if not data is Dictionary or not data.get("memory") is Dictionary:
		return "malformed response"
	if data.get("request_id") != job.request_id or data.get("character_id") != id:
		return "response is for another request or character"
	if int(get_memory(id).revision) != job.base_revision:
		return "stale: memory changed since the request"
	var m: Dictionary = data.memory
	var problem := validate_snapshot(m, id)
	if problem:
		return problem
	if int(m.revision) != job.base_revision + 1:
		return "revision must be base_revision + 1"
	if m.last_processed_event_id != job.last_event_id:
		return "processing cursor does not match the events sent"
	for section in SECTIONS:
		for entry in m[section]:
			for source in entry.source_event_ids:
				if not job.allowed.has(source):
					return "entry %s cites an unknown event" % entry.id
	return ""


## Event ids start with their creation time in ms ("e<ms>_<rand>"), so they sort in time order.
static func _event_ms(event: Dictionary) -> int:
	return int(String(event.event_id).substr(1).get_slice("_", 0))


## Shape and size checks shared by loading and accepting (SPEC 6.1). Returns "" if valid.
static func validate_snapshot(m: Variant, id: String) -> String:
	if not m is Dictionary:
		return "not an object"
	if not _is_number(m.get("schema_version")) or int(m.schema_version) != 1:
		return "unsupported schema_version"
	if m.get("character_id") != id:
		return "belongs to another character"
	if not _is_number(m.get("revision")) or m.revision < 0:
		return "invalid revision"
	var cursor: Variant = m.get("last_processed_event_id")
	if cursor != null and not cursor is String:
		return "invalid processing cursor"
	var ids := {}
	var total := 0
	for section in SECTIONS:
		if not m.get(section) is Array:
			return "missing " + section
		for entry in m[section]:
			if not entry is Dictionary or not entry.get("id") is String or ids.has(entry.id):
				return "missing or duplicate entry id"
			ids[entry.id] = true
			var text: Variant = entry.get("text")
			if not text is String or text.is_empty() or text.length() > ENTRY_CAP:
				return "entry %s has missing or oversized text" % entry.id
			total += text.length()
			var sources: Variant = entry.get("source_event_ids")
			if not sources is Array or sources.is_empty() or not sources.all(func(s: Variant) -> bool: return s is String):
				return "entry %s has no sources" % entry.id
			if not entry.get("learned_from") is String:
				return "entry %s has no learned_from" % entry.id
			if not entry.get("share_scope") in ["private", "shared"]:
				return "entry %s has an invalid share_scope" % entry.id
	if total > TEXT_CAP:
		return "memory exceeds %d characters" % TEXT_CAP
	return ""


## Parsed JSON numbers are floats; snapshots built in code use ints.
static func _is_number(v: Variant) -> bool:
	return v is int or v is float


static func empty_memory(id: String) -> Dictionary:
	return {"schema_version": 1, "character_id": id, "revision": 0, "last_processed_event_id": null,
		"facts": [], "ongoing": [], "experiences": []}


## Stores whole numbers as ints so the file stays tidy.
static func _normalize(m: Dictionary) -> Dictionary:
	var out := m.duplicate(true)
	out.schema_version = int(out.schema_version)
	out.revision = int(out.revision)
	return out


func _path(id: String) -> String:
	return SaveManager.dir + "characters/%s.memory.json" % id


func _reset() -> void:
	_cache.clear()
	_in_flight.clear()
	last_error.clear()
	_retry_timer.stop()
