class_name FurnitureController
extends Node2D
## FurnitureController: purchasing, placement, moving, storing (SPEC 3.4).
## Furniture snaps to the tile grid, rests on solid ground, and never blocks walking.
## Payment happens on placement, so cancelling a preview costs nothing.

signal mode_changed

enum Mode { NONE, PLACING, MOVING }

var mode := Mode.NONE
var arranging := false
var def_id := ""

var _moving: Sprite2D  # existing node being moved, hidden while carried
var _preview: Sprite2D
var _preview_cell := Vector2i(-1, -1)  # bottom-left of footprint, or -1 when invalid

@onready var world: World = get_parent()
@onready var root: Node2D = world.get_node("Furniture")


func _ready() -> void:
	_preview = Sprite2D.new()
	_preview.centered = false
	_preview.visible = false
	_preview.z_index = 10
	add_child(_preview)


func is_busy() -> bool:
	return mode != Mode.NONE or arranging


## Rebuild placed furniture from the save.
func restore() -> void:
	for rec in SaveManager.world.placed:
		_spawn(rec.uid, rec.def, Defs.vec2i(rec.cell))


# --- Commands from the UI ---

func begin_place(id: String) -> void:
	var d: Dictionary = Defs.furniture[id]
	if SaveManager.stored(id) == 0 and not SaveManager.can_afford(d.cost):
		return
	_end_move(false)
	def_id = id
	mode = Mode.PLACING
	_show_preview(id)
	mode_changed.emit()


func set_arranging(on: bool) -> void:
	cancel()
	arranging = on
	mode_changed.emit()


func cancel() -> void:
	_end_move(false)
	mode = Mode.NONE
	def_id = ""
	_preview.visible = false
	mode_changed.emit()


## Put the carried piece into storage; it can be placed again without paying.
func store_moving() -> void:
	if mode != Mode.MOVING:
		return
	var uid: String = _moving.get_meta("uid")
	SaveManager.world.placed = SaveManager.world.placed.filter(func(r): return r.uid != uid)
	SaveManager.add_stored(def_id, 1)
	_moving.queue_free()
	_moving = null
	cancel()


# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and mode != Mode.NONE:
		cancel()
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if mode != Mode.NONE:
			_confirm()
			get_viewport().set_input_as_handled()
		elif arranging:
			var hit := _furniture_at(world.mouse_world())
			if hit:
				_begin_move(hit)
				get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if mode == Mode.NONE:
		return
	var w: Vector2i = Defs.vec2i(Defs.furniture[def_id].footprint)
	var mouse_cell := world.cell_at(world.mouse_world())
	var bottom_left := Vector2i(mouse_cell.x - (w.x - 1) / 2, mouse_cell.y)
	_preview_cell = _snap(bottom_left, w)
	var shown := _preview_cell if _preview_cell.x >= 0 else bottom_left
	_preview.position = _sprite_position(shown, w) - Visuals.anchor(Defs.furniture[def_id].visual)
	_preview.modulate = Color(1, 1, 1, 0.7) if _preview_cell.x >= 0 else Color(1, 0.35, 0.35, 0.6)


func _confirm() -> void:
	if _preview_cell.x < 0:
		return
	if mode == Mode.PLACING:
		if SaveManager.stored(def_id) > 0:
			SaveManager.add_stored(def_id, -1)
		elif SaveManager.can_afford(Defs.furniture[def_id].cost):
			SaveManager.spend(Defs.furniture[def_id].cost)
		else:
			cancel()
			return
		var uid := SaveManager.new_uid()
		_spawn(uid, def_id, _preview_cell)
		SaveManager.world.placed.append({"uid": uid, "def": def_id, "cell": [_preview_cell.x, _preview_cell.y]})
	else:
		var uid: String = _moving.get_meta("uid")
		_moving.set_meta("cell", _preview_cell)
		_moving.position = _sprite_position(_preview_cell, Defs.vec2i(Defs.furniture[def_id].footprint))
		for r in SaveManager.world.placed:
			if r.uid == uid:
				r.cell = [_preview_cell.x, _preview_cell.y]
		_moving.visible = true
		_moving = null
	SaveManager.save_world()
	mode = Mode.NONE
	_preview.visible = false
	mode_changed.emit()


# --- Helpers ---

func _begin_move(node: Sprite2D) -> void:
	_moving = node
	def_id = node.get_meta("def")
	node.visible = false
	mode = Mode.MOVING
	_show_preview(def_id)
	mode_changed.emit()


## Cancelling a move puts the piece back where it was.
func _end_move(_keep: bool) -> void:
	if _moving:
		_moving.visible = true
		_moving = null


func _show_preview(id: String) -> void:
	_preview.texture = Visuals.texture(Defs.furniture[id].visual)
	_preview.visible = true


## Drop from the cursor row down onto the first valid resting place (max 10 rows).
func _snap(bottom_left: Vector2i, w: Vector2i) -> Vector2i:
	for y in range(bottom_left.y, bottom_left.y + 10):
		var c := Vector2i(bottom_left.x, y)
		if _fits(c, w):
			return c
		for dx in w.x:
			if world.is_solid(Vector2i(c.x + dx, y)):
				return Vector2i(-1, -1)
	return Vector2i(-1, -1)


func _fits(bottom_left: Vector2i, w: Vector2i) -> bool:
	var taken := _occupied_cells()
	for dx in w.x:
		for dy in w.y:
			var c := bottom_left + Vector2i(dx, -dy)
			if not world.in_bounds(c) or world.is_solid(c) or taken.has(c):
				return false
		if not world.is_solid(bottom_left + Vector2i(dx, 1)):
			return false
	return true


func _occupied_cells() -> Dictionary:
	var out := {}
	for node: Sprite2D in root.get_children():
		if node == _moving:
			continue
		var w := Defs.vec2i(Defs.furniture[node.get_meta("def")].footprint)
		var bl: Vector2i = node.get_meta("cell")
		for dx in w.x:
			for dy in w.y:
				out[bl + Vector2i(dx, -dy)] = true
	return out


func _furniture_at(pos: Vector2) -> Sprite2D:
	for node: Sprite2D in root.get_children():
		if node.visible and node.get_rect().has_point(node.to_local(pos)):
			return node
	return null


func _sprite_position(bottom_left: Vector2i, w: Vector2i) -> Vector2:
	return Vector2((bottom_left.x + w.x / 2.0) * world.TILE, (bottom_left.y + 1) * world.TILE)


func _spawn(uid: String, id: String, cell: Vector2i) -> void:
	var d: Dictionary = Defs.furniture[id]
	var s := Sprite2D.new()
	s.texture = Visuals.texture(d.visual)
	s.centered = false
	s.offset = -Visuals.anchor(d.visual)
	s.position = _sprite_position(cell, Defs.vec2i(d.footprint))
	s.set_meta("uid", uid)
	s.set_meta("def", id)
	s.set_meta("cell", cell)
	root.add_child(s)
