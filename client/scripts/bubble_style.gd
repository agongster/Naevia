class_name BubbleStyle
extends Resource
## All bubble sizing in one editable resource (SPEC 4.2). Units are 640 x 360
## game units: at the 1280 x 720 window each unit is 2 display pixels.

@export var body_font_size := 11       # 22 px at 1280 x 720
@export var name_font_size := 8        # 16 px
@export var padding_h := 8             # 16 px
@export var padding_v := 6             # 12 px
@export var max_width := 160.0         # 320 px
@export var max_height := 80.0         # 160 px
@export var segment_chars := 110       # sentences are packed up to this length
@export var screen_margin := 4.0
@export var top_margin := 34.0         # keep bubbles below the HUD's top button bar
@export var background := Color("#f4e9d2")
@export var border := Color("#4b382d")
@export var text_color := Color("#352c2a")
@export var muted_color := Color("#7a6656")
