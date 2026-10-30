class_name World
extends Node2D
## World: builds the editable level from data/level.json, owns the shared TileSet,
## and answers tile queries for the controllers. The flattened scene preview in
## art/previews is a reference only; every tile, prop and character is separate.

const TILE := 16

@onready var walls: TileMapLayer = $Walls
@onready var terrain: TileMapLayer = $Terrain
@onready var resources: TileMapLayer = $Resources
@onready var props: Node2D = $Props
@onready var player: PlayerController = $Player
@onready var furniture: FurnitureController = $FurnitureController
@onready var conversation: ConversationCoordinator = $ConversationCoordinator
@onready var contacts: ContactScheduler = $ContactScheduler
@onready var ui: Hud = $UI

var size: Vector2i
## Last pointer position in viewport coordinates, taken from mouse events.
var mouse_screen := Vector2.ZERO
var _source_to_tile: Dictionary = {}  # TileSet source id -> tile definition id
var _tile_to_source: Dictionary = {}


func _enter_tree() -> void:
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("jump", KEY_SPACE)


func _ready() -> void:
	get_viewport().physics_object_picking = true
	size = Defs.vec2i(Defs.level.size)
	var tile_set := _build_tile_set()
	for layer: TileMapLayer in [walls, terrain, resources]:
		layer.tile_set = tile_set
	walls.collision_enabled = false
	_build_level()
	_build_props()
	_build_backdrop()
	_build_bounds()
	_place_player()
	furniture.restore()
	contacts.setup()
	ui.setup()
	if not SaveManager.has_world_save():
		save_resources()
	ApiClient.check_health()


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		mouse_screen = event.position


# --- Queries ---

## Pointer in world coordinates, recomputed every frame so it tracks camera motion.
func mouse_world() -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * mouse_screen


func tile_at(layer: TileMapLayer, cell: Vector2i) -> String:
	return _source_to_tile.get(layer.get_cell_source_id(cell), "")


func tile_def(layer: TileMapLayer, cell: Vector2i) -> Dictionary:
	var id := tile_at(layer, cell)
	return Defs.tiles.get(id, {})


func is_solid(cell: Vector2i) -> bool:
	return tile_def(terrain, cell).get("solid", false) or tile_def(resources, cell).get("solid", false)


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func cell_at(world_pos: Vector2) -> Vector2i:
	return terrain.local_to_map(terrain.to_local(world_pos))


func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell * TILE) + Vector2(TILE, TILE) / 2.0


## Top surface (world y) of the first solid cell in the column under x.
func ground_y_at(x: float) -> float:
	var col := clampi(floori(x / TILE), 0, size.x - 1)
	for y in size.y:
		if is_solid(Vector2i(col, y)):
			return y * TILE
	return size.y * TILE


func camera_right() -> float:
	var cam: Camera2D = player.get_node("Camera2D")
	return cam.get_screen_center_position().x + get_viewport_rect().size.x / 2.0


func spawn_position() -> Vector2:
	var c := Defs.vec2i(Defs.level.spawn)
	return Vector2(c.x * TILE + TILE / 2.0, (c.y + 1) * TILE)


# --- Persistence of mineable cells ---

func save_resources() -> void:
	var cells: Array = []
	for c in resources.get_used_cells():
		cells.append([c.x, c.y, tile_at(resources, c)])
	SaveManager.world.resources = cells
	SaveManager.save_world()


## Development action: restore every resource cell from the level definition.
func reset_resources() -> void:
	resources.clear()
	_fill_layer("resources", resources)
	save_resources()
	var feet := cell_at(player.global_position + Vector2(0, -1))
	if is_solid(feet) or is_solid(feet + Vector2i.UP) or is_solid(feet + Vector2i.UP * 2):
		player.global_position = spawn_position()


# --- Construction ---

func _build_tile_set() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	var half := TILE / 2.0
	var square := PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
	for tile_id: String in Defs.tiles:
		var d: Dictionary = Defs.tiles[tile_id]
		var source := TileSetAtlasSource.new()
		source.texture = Visuals.texture(d.visual)
		source.texture_region_size = Vector2i(TILE, TILE)
		var source_id := ts.add_source(source)
		source.create_tile(Vector2i.ZERO)
		if d.get("solid", false):
			var data := source.get_tile_data(Vector2i.ZERO, 0)
			data.add_collision_polygon(0)
			data.set_collision_polygon_points(0, 0, square)
		_source_to_tile[source_id] = tile_id
		_tile_to_source[tile_id] = source_id
	return ts


func _build_level() -> void:
	_fill_layer("walls", walls)
	_fill_layer("terrain", terrain)
	# Terrain is open wherever the level defines a resource, mined or not.
	for fill in Defs.level.fills:
		if fill.layer == "resources":
			for cell in _rect_cells(fill.rect):
				terrain.erase_cell(cell)
	var saved: Variant = SaveManager.world.resources
	if saved is Array:
		for e in saved:
			if _tile_to_source.has(e[2]):
				resources.set_cell(Vector2i(int(e[0]), int(e[1])), _tile_to_source[e[2]], Vector2i.ZERO)
	else:
		_fill_layer("resources", resources)


func _fill_layer(layer_name: String, layer: TileMapLayer) -> void:
	for fill in Defs.level.fills:
		if fill.layer != layer_name:
			continue
		for cell in _rect_cells(fill.rect):
			layer.set_cell(cell, _tile_to_source[fill.tile], Vector2i.ZERO)


func _rect_cells(r: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(int(r[0]), int(r[0]) + int(r[2])):
		for y in range(int(r[1]), int(r[1]) + int(r[3])):
			out.append(Vector2i(x, y))
	return out


## Props are visual only. The door is configured passable by having no collider.
func _build_props() -> void:
	for p in Defs.level.props:
		var cell := Defs.vec2i(p.cell)
		for i in int(p.get("repeat_y", 1)):
			var s := Sprite2D.new()
			s.texture = Visuals.texture(p.visual)
			s.centered = false
			s.position = Vector2(cell.x * TILE, (cell.y + i) * TILE)
			props.add_child(s)


func _build_backdrop() -> void:
	var sky: TextureRect = $Sky/SkyRect
	sky.texture = Visuals.texture("background.sky")
	var landscape: Sprite2D = $Landscape/Sprite
	landscape.texture = Visuals.texture("background.distant_landscape")
	landscape.centered = false
	# Line the landscape's treeline up with the ground surface; it repeats horizontally.
	landscape.position = Vector2(0, Defs.level.spawn[1] * TILE + TILE - 258)


func _build_bounds() -> void:
	var body := StaticBody2D.new()
	for x in [-TILE / 2.0, size.x * TILE + TILE / 2.0]:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(TILE, size.y * TILE * 2)
		shape.shape = rect
		shape.position = Vector2(x, size.y * TILE / 2.0)
		body.add_child(shape)
	add_child(body)


func _place_player() -> void:
	var saved: Variant = SaveManager.world.player
	player.global_position = Vector2(saved[0], saved[1]) if saved is Array else spawn_position()
	var cam: Camera2D = player.get_node("Camera2D")
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = size.x * TILE
	cam.limit_bottom = size.y * TILE
	cam.reset_smoothing()


func _add_key_action(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)
