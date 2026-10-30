extends Node2D
## MiningController: hold left mouse on a resource cell within reach to mine it
## (SPEC 3.4). Crack frames follow progress manually (manifest playback: manual_progress).

const REACH_TILES := 4.0

var _holding := false
var _cell := Vector2i(-1, -1)
var _progress := 0.0
var _cracks: Sprite2D

@onready var world: World = get_parent()


func _ready() -> void:
	_cracks = Sprite2D.new()
	_cracks.texture = Visuals.texture("effect.mining_cracks")
	_cracks.hframes = int(Visuals.def("effect.mining_cracks").frame_count)
	_cracks.centered = false
	_cracks.visible = false
	add_child(_cracks)


## Only clicks the UI did not consume reach here, so UI never mines behind it.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_holding = event.pressed


func _process(delta: float) -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_holding = false
	var target := _target_cell() if _holding else Vector2i(-1, -1)
	if target.x < 0:
		_stop()
		return
	if target != _cell:
		_cell = target
		_progress = 0.0
	var d := world.tile_def(world.resources, _cell)
	_progress += delta / float(d.get("mine_seconds", 1.0))
	world.player.set_mining(true, world.cell_center(_cell))
	_cracks.visible = true
	_cracks.position = Vector2(_cell * world.TILE)
	_cracks.frame = mini(int(_progress * _cracks.hframes), _cracks.hframes - 1)
	if _progress >= 1.0:
		_break(_cell, d)


func _target_cell() -> Vector2i:
	if world.furniture.is_busy():
		return Vector2i(-1, -1)
	var cell: Vector2i = world.cell_at(world.mouse_world())
	if not world.tile_def(world.resources, cell).get("mineable", false):
		return Vector2i(-1, -1)
	var reach := REACH_TILES * world.TILE + world.TILE / 2.0
	if world.player.body_center().distance_to(world.cell_center(cell)) > reach:
		return Vector2i(-1, -1)
	return cell


func _break(cell: Vector2i, d: Dictionary) -> void:
	world.resources.erase_cell(cell)
	_spawn_chips(world.cell_center(cell))
	_stop()
	world.save_resources()
	SaveManager.add_material(d.drops, int(d.get("drop_count", 1)))


func _stop() -> void:
	_cell = Vector2i(-1, -1)
	_progress = 0.0
	_cracks.visible = false
	world.player.set_mining(false)


func _spawn_chips(at: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.texture = Visuals.texture("effect.stone_chip")
	p.position = at
	p.amount = 8
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.5
	p.direction = Vector2.UP
	p.spread = 70.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 90.0
	p.gravity = Vector2(0, 400)
	p.emitting = true
	add_child(p)
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)
