class_name ContactScheduler
extends Node
## Brings the pigeon or the blacksmith to the player on timers, one visitor at a
## time (SPEC 4.1). An ignored visitor simply leaves: no message, no penalty.

var _cfg: Dictionary
var _pigeon_in := 0.0
var _blacksmith_in := 0.0
var _visitor: Node2D = null
var _ignore_left := 0.0

@onready var world: World = get_parent()
@onready var pigeon: Pigeon = world.get_node("Characters/Pigeon")
@onready var blacksmith: Npc = world.get_node("Characters/Blacksmith")


## Called by World once its node references exist.
func setup() -> void:
	_cfg = Defs.config.contacts
	_pigeon_in = _cfg.pigeon_first_delay
	_blacksmith_in = _cfg.blacksmith_first_delay
	pigeon.visible = false
	blacksmith.visible = false
	pigeon.clicked.connect(_on_clicked)
	blacksmith.clicked.connect(_on_clicked)
	world.conversation.closed.connect(_dismiss)


func _process(delta: float) -> void:
	if _cfg.is_empty():
		return
	if _visitor:
		if not world.conversation.is_open():
			_ignore_left -= delta
			if _ignore_left <= 0.0:
				_dismiss()
		return
	_pigeon_in -= delta
	_blacksmith_in -= delta
	if _pigeon_in <= 0.0:
		summon_pigeon()
	elif _blacksmith_in <= 0.0:
		summon_blacksmith()


## Also used by the Contacts menu and the development buttons.
func summon_pigeon() -> void:
	_pigeon_in = _cfg.pigeon_interval
	if _visitor == pigeon:
		return
	_dismiss()
	var p := world.player.global_position
	var x := clampf(p.x + 40.0, 16.0, world.size.x * world.TILE - 16.0)
	pigeon.position = Vector2(world.camera_right() + 20.0, p.y - 140.0)
	pigeon.fly_to(Vector2(x, world.ground_y_at(x)))
	_arrive(pigeon)


func summon_blacksmith() -> void:
	_blacksmith_in = _cfg.blacksmith_interval
	if _visitor == blacksmith:
		return
	_dismiss()
	var spot := Defs.vec2i(Defs.level.blacksmith_visit_cell)
	blacksmith.position = Vector2(minf(world.camera_right() + 20.0, world.size.x * world.TILE), (spot.y + 1) * world.TILE)
	blacksmith.visible = true
	blacksmith.walk_to(spot.x * world.TILE + world.TILE / 2.0)
	_arrive(blacksmith)


func _arrive(visitor: Node2D) -> void:
	_visitor = visitor
	_ignore_left = _cfg.ignore_timeout


func _on_clicked(npc: Node2D) -> void:
	if npc != _visitor:
		return
	_ignore_left = _cfg.ignore_timeout
	if npc == pigeon:
		world.conversation.open("witch", pigeon, "Witch · via pigeon",
			"The witch is at home in her garden. The player's words reach her by messenger pigeon, and her replies are carried back.")
	else:
		world.conversation.open("blacksmith", blacksmith, "Blacksmith",
			"The blacksmith has dropped by and is standing at the player's front door.")


func _dismiss() -> void:
	if _visitor == pigeon:
		pigeon.fly_to(pigeon.position + Vector2(260, -220), true)
	elif _visitor == blacksmith:
		blacksmith.walk_to(world.size.x * world.TILE + 40.0)
		if not blacksmith.arrived.is_connected(_hide_blacksmith_if_gone):
			blacksmith.arrived.connect(_hide_blacksmith_if_gone, CONNECT_ONE_SHOT)
	_visitor = null


## Only hide once he has actually left; he may have been summoned back meanwhile.
func _hide_blacksmith_if_gone() -> void:
	if blacksmith.position.x > world.size.x * world.TILE:
		blacksmith.visible = false
