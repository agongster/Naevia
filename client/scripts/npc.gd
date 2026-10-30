class_name Npc
extends Node2D
## A character in the world (witch, blacksmith) with an Area2D click target (SPEC 3.1).
## Origin is the character's feet; movement is horizontal walking on the ground.

signal clicked(npc: Node2D)
signal arrived

@export var character_id := "blacksmith"
@export var walk_speed := 60.0
## Height above the feet where this character's speech bubble attaches.
@export var bubble_height := 64.0

var _target_x := NAN

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var area: Area2D = $ClickArea


func _ready() -> void:
	sprite.sprite_frames = Visuals.sprite_frames({
		"idle": "character.%s.idle" % character_id,
		"walk": "character.%s.walk" % character_id,
	})
	sprite.offset = -Visuals.anchor("character.%s.idle" % character_id)
	sprite.play("idle")
	area.input_event.connect(_on_area_input)
	visibility_changed.connect(func() -> void: area.input_pickable = visible)
	area.input_pickable = visible


func bubble_anchor() -> Vector2:
	return global_position + Vector2(0, -bubble_height)


func walk_to(x: float) -> void:
	_target_x = x
	sprite.flip_h = x < position.x
	sprite.play("walk")


func is_walking() -> bool:
	return not is_nan(_target_x)


func _process(delta: float) -> void:
	if is_nan(_target_x):
		return
	position.x = move_toward(position.x, _target_x, walk_speed * delta)
	if is_equal_approx(position.x, _target_x):
		_target_x = NAN
		sprite.play("idle")
		arrived.emit()


func _on_area_input(_viewport: Node, event: InputEvent, _shape: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		clicked.emit(self)
