extends Node
## SaveManager: world state, dialogue history, and safe file replacement (SPEC 6.1, 7).
## Owns everything under user://saves/<slot>/. Pass `-- --save-slot=<name>` to use
## a separate slot (for fresh-save testing without touching the real save).

signal inventory_changed

const SCHEMA_VERSION := 1

var slot := "default"
var dir: String
## Current world state; see _default_world() for the shape.
var world: Dictionary

var _position_timer: Timer


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save-slot="):
			slot = arg.get_slice("=", 1)
	dir = "user://saves/%s/" % slot
	DirAccess.make_dir_recursive_absolute(dir + "characters")
	DirAccess.make_dir_recursive_absolute(dir + "history")
	var loaded: Variant = read_json(dir + "world.json")
	world = loaded if loaded is Dictionary and loaded.get("schema_version") == SCHEMA_VERSION else _default_world()

	_position_timer = Timer.new()
	_position_timer.one_shot = true
	_position_timer.wait_time = Defs.config.position_save_debounce
	_position_timer.timeout.connect(save_world)
	add_child(_position_timer)


func _default_world() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"player": null,          # [x, y] in world pixels; null = level spawn
		"materials": {},         # item id -> count
		"stored_furniture": {},  # furniture id -> count
		"placed": [],            # [{uid, def, cell: [x, y]}], cell = bottom-left of footprint
		"resources": null,       # [[x, y, tile id]]; null = level defaults
		"next_uid": 1,
	}


func has_world_save() -> bool:
	return FileAccess.file_exists(dir + "world.json")


func save_world() -> void:
	write_json_atomic(dir + "world.json", world)


func request_position_save(pos: Vector2) -> void:
	world.player = [roundi(pos.x), roundi(pos.y)]
	if _position_timer.is_stopped():
		_position_timer.start()


# --- Inventory helpers (saving follows every material/furniture change) ---

func count(item_id: String) -> int:
	return int(world.materials.get(item_id, 0))


func add_material(item_id: String, amount: int) -> void:
	world.materials[item_id] = count(item_id) + amount
	_changed()


func can_afford(cost: Dictionary) -> bool:
	for item_id in cost:
		if count(item_id) < int(cost[item_id]):
			return false
	return true


func spend(cost: Dictionary) -> void:
	for item_id in cost:
		world.materials[item_id] = count(item_id) - int(cost[item_id])
	_changed()


func stored(furniture_id: String) -> int:
	return int(world.stored_furniture.get(furniture_id, 0))


func add_stored(furniture_id: String, amount: int) -> void:
	world.stored_furniture[furniture_id] = stored(furniture_id) + amount
	_changed()


func new_uid() -> String:
	var uid := "obj%d" % int(world.next_uid)
	world.next_uid = int(world.next_uid) + 1
	return uid


func _changed() -> void:
	save_world()
	inventory_changed.emit()


# --- Dialogue history (JSONL, append-only) ---

func append_history(key: String, event: Dictionary) -> void:
	var path := dir + "history/%s.jsonl" % key
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file == null:
		push_error("Could not open history file " + path)
		return
	file.seek_end()
	file.store_line(JSON.stringify(event))


func read_history(key: String, limit := 0) -> Array:
	var path := dir + "history/%s.jsonl" % key
	var out: Array = []
	if not FileAccess.file_exists(path):
		return out
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		var ev: Variant = JSON.parse_string(line)
		if ev is Dictionary:
			out.append(ev)
	return out.slice(-limit) if limit > 0 else out


# --- File helpers ---

static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Writes to a temporary file, then replaces the target, so a crash mid-write
## never leaves a truncated save.
static func write_json_atomic(path: String, data: Variant) -> bool:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("Could not write " + tmp)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("Could not replace %s (error %d)" % [path, err])
		return false
	return true


## Development action: delete this slot's saves. Callers reload the scene afterwards.
func wipe_slot() -> void:
	for sub in ["", "characters/", "history/"]:
		var d := DirAccess.open(dir + sub)
		if d:
			for f in d.get_files():
				d.remove(f)
	world = _default_world()
