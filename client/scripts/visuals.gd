extends Node
## Visual lookup keyed by stable visual IDs (SPEC 3.3 step 4).
## data/visuals.json is generated from art/export/manifest.json by tools/sync_art.py.

var _defs: Dictionary


func _ready() -> void:
	_defs = Defs.load_json("res://data/visuals.json")


func def(id: String) -> Dictionary:
	assert(_defs.has(id), "Unknown visual id: " + id)
	return _defs[id]


func texture(id: String) -> Texture2D:
	return load(def(id).path)


func anchor(id: String) -> Vector2:
	var a: Array = def(id).anchor
	return Vector2(a[0], a[1])


func frame_size(id: String) -> Vector2:
	var d := def(id)
	return Vector2(d.frame_width, d.frame_height)


## Builds SpriteFrames from {animation_name: visual_id}, using manifest frame
## layout and playback rates. Static sheets (fps 0) play as a single held pose.
func sprite_frames(animations: Dictionary) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for anim: String in animations:
		var vid: String = animations[anim]
		var d := def(vid)
		var tex := texture(vid)
		frames.add_animation(anim)
		frames.set_animation_speed(anim, maxf(d.fps, 1.0))
		frames.set_animation_loop(anim, d.loop)
		for i in int(d.frame_count):
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(i * d.frame_width, 0, d.frame_width, d.frame_height)
			frames.add_frame(anim, atlas)
	return frames
