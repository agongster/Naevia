class_name Pigeon
extends Node2D
## The witch's messenger. Clicking it opens a remote conversation with the witch;
## her replies anchor to the pigeon (SPEC 4.1).

signal clicked(npc: Node2D)
signal arrived

const FLIGHT_TIME := 2.5

@export var character_id := "witch"
@export var bubble_height := 28.0

var _tween: Tween

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var area: Area2D = $ClickArea


func _ready() -> void:
	sprite.sprite_frames = Visuals.sprite_frames({
		"idle": "character.pigeon.idle",
		"fly": "character.pigeon.fly",
	})
	sprite.offset = -Visuals.anchor("character.pigeon.idle")
	sprite.play("idle")
	area.input_event.connect(_on_area_input)
	visibility_changed.connect(func() -> void: area.input_pickable = visible)
	area.input_pickable = visible


func bubble_anchor() -> Vector2:
	return global_position + Vector2(0, -bubble_height)


func fly_to(target: Vector2, then_hide := false) -> void:
	if _tween:
		_tween.kill()
	visible = true
	sprite.flip_h = target.x < position.x
	sprite.play("fly")
	_tween = create_tween()
	_tween.tween_property(self, "position", target, FLIGHT_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func() -> void:
		if then_hide:
			visible = false
		else:
			sprite.play("idle")
			arrived.emit())


func _on_area_input(_viewport: Node, event: InputEvent, _shape: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		clicked.emit(self)
