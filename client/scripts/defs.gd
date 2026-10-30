extends Node
## Static gameplay definitions shipped with the client (SPEC 3.3 step 4).
## Gameplay behavior comes from these files, never from PNG names or pixels.

var config: Dictionary
var items: Dictionary
var tiles: Dictionary
var furniture: Dictionary
var level: Dictionary
var characters: Dictionary = {}


func _ready() -> void:
	config = load_json("res://data/config.json")
	items = load_json("res://data/items.json")
	tiles = load_json("res://data/tiles.json")
	furniture = load_json("res://data/furniture.json")
	level = load_json("res://data/level.json")
	for id in config.characters:
		characters[id] = load_json("res://data/characters/%s.json" % id)


static func load_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "Missing data file: " + path)
	var data: Variant = JSON.parse_string(file.get_as_text())
	assert(data != null, "Invalid JSON: " + path)
	return data


static func vec2i(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))
