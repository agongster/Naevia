class_name PlayerController
extends CharacterBody2D
## PlayerController: movement and animation (SPEC 3.4). The node origin is the
## player's feet; the 20 x 42 collider is independent of the 48 x 64 sprite canvas.

const SPEED := 90.0
const JUMP_VELOCITY := -320.0  # ~3.5 tiles: enough to climb out of a 3-tile pit
const GRAVITY := 900.0

var _mining := false
var _mine_target := Vector2.ZERO
var _last_saved := Vector2.INF

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	sprite.sprite_frames = Visuals.sprite_frames({
		"idle": "character.player.idle",
		"walk": "character.player.walk",
		"jump": "character.player.jump",
		"mine": "character.player.mine",
	})
	sprite.offset = -Visuals.anchor("character.player.idle")
	sprite.play("idle")


## Called each frame by MiningController while a tile is being mined.
func set_mining(active: bool, target := Vector2.ZERO) -> void:
	_mining = active
	_mine_target = target


func body_center() -> Vector2:
	return global_position + Vector2(0, -21)


func _physics_process(delta: float) -> void:
	# Typing in a text field must not move the player (SPEC 3.4).
	var typing := get_viewport().gui_get_focus_owner() is LineEdit
	var dir := 0.0 if typing else Input.get_axis("move_left", "move_right")
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	elif not typing and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY
	velocity.x = dir * SPEED
	move_and_slide()
	_animate(dir)
	if global_position.distance_to(_last_saved) > 1.0:
		_last_saved = global_position
		SaveManager.request_position_save(global_position)


func _animate(dir: float) -> void:
	if _mining:
		sprite.flip_h = _mine_target.x < global_position.x
		sprite.play("mine")
		return
	if dir != 0.0:
		sprite.flip_h = dir < 0.0
	if not is_on_floor():
		sprite.play("jump")
	elif dir != 0.0:
		sprite.play("walk")
	else:
		sprite.play("idle")
