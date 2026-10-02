extends RefCounted
## Presentation choices are serializable; character identity is immutable.

const EXPRESSIONS := ["自然", "腮红", "高光", "惊讶", "阴沉", "微笑", "难过", "生气", "放松"]
const MOUTH_SYMBOLS := ["关闭 · 原嘴", "紧张 ～", "惊讶 ○", "平嘴 —"]
const EYE_SYMBOLS := ["关闭 · 原眼", "挤眼 ><", "开心 ^^", "无语 --", "眩晕 XX"]
const KEYS := [
	"schema",
	"character",
	"palette",
	"colors",
	"stocking_transparency",
	"expression",
	"equipment",
	"action",
	"blink",
	"secondary",
	"hosiery_style",
	"hosiery_stitch",
	"hosiery_height",
	"hosiery_sheen",
	"hosiery_weave",
	"hosiery_roughness",
	"wetness_regions",
	"eye_wetness",
	"eye_left",
	"eye_right",
	"eye_symbol",
	"mouth_symbol",
	"eye_symbol_size",
	"mouth_symbol_size",
	"eye_symbol_stroke",
	"mouth_symbol_stroke",
	"wind_strength",
	"soft_tissue_pressure",
	"droplets_enabled",
	"droplet_count",
	"droplet_speed",
	"droplet_seed",
	"tulle_geometry_enabled",
	"eye_geometry_enabled",
	"hair_dynamic_enabled",
	"hair_collision_enabled",
	"authored_materials_enabled",
]

var palette := 0
var colors: Array[Color] = []
var stocking_transparency := 0.5
var expression := 0
var equipment: Array = [false, false, false, false]
var action := 0
var blink := true
var secondary := true
var hosiery_style := 0
var hosiery_stitch := 0.0
var hosiery_height := 0.0
var hosiery_sheen := 0.20
var hosiery_weave := 0.035
var hosiery_roughness := 0.27
var wetness_regions := [0.0, 0.0, 0.0, 0.0]
var eye_wetness := 0.0
var eye_left := [0.0, 0.0, 1.0]
var eye_right := [0.0, 0.0, 1.0]
var eye_symbol := 0
var mouth_symbol := 0
var eye_symbol_size := 1.0
var mouth_symbol_size := 1.0
var eye_symbol_stroke := 0.10
var mouth_symbol_stroke := 0.10
var wind_strength := 0.0
var soft_tissue_pressure := 0.0
var droplets_enabled := false
var droplet_count := 0
var droplet_speed := 0.35
var droplet_seed := 17
var tulle_geometry_enabled := false
# Retained for internal comparison fixtures only; not a user-facing saved option.
var eye_geometry_enabled := false
var hair_dynamic_enabled := false
var hair_collision_enabled := false
var authored_materials_enabled := false
var _character_id: String
var _palette_profile: NPRShowcasePaletteProfile
var _height_profile: NPRShowcaseHeightProfile


func _init(
	character_id: String, profile: NPRShowcasePaletteProfile, height: NPRShowcaseHeightProfile
) -> void:
	_character_id = character_id
	_height_profile = height.duplicate(true)
	hosiery_height = _height_profile.default_height
	_palette_profile = profile.duplicate(true)
	select_palette(_palette_profile.default_index)


func select_palette(index: int) -> void:
	palette = clampi(index, 0, _palette_profile.labels.size() - 1)
	colors = _palette_profile.colors_at(palette)


func to_data() -> Dictionary:
	return {
		"schema": 10,
		"character": _character_id,
		"palette": palette,
		"colors": [colors[0].to_html(false), colors[1].to_html(false), colors[2].to_html(false)],
		"stocking_transparency": stocking_transparency,
		"expression": expression,
		"equipment": equipment.duplicate(),
		"action": action,
		"blink": blink,
		"secondary": secondary,
		"hosiery_style": hosiery_style,
		"hosiery_stitch": hosiery_stitch,
		"hosiery_height": hosiery_height,
		"hosiery_sheen": hosiery_sheen,
		"hosiery_weave": hosiery_weave,
		"hosiery_roughness": hosiery_roughness,
		"wetness_regions": wetness_regions.duplicate(),
		"eye_wetness": eye_wetness,
		"eye_left": eye_left.duplicate(),
		"eye_right": eye_right.duplicate(),
		"eye_symbol": eye_symbol,
		"mouth_symbol": mouth_symbol,
		"eye_symbol_size": eye_symbol_size,
		"mouth_symbol_size": mouth_symbol_size,
		"eye_symbol_stroke": eye_symbol_stroke,
		"mouth_symbol_stroke": mouth_symbol_stroke,
		"wind_strength": wind_strength,
		"soft_tissue_pressure": soft_tissue_pressure,
		"droplets_enabled": droplets_enabled,
		"droplet_count": droplet_count,
		"droplet_speed": droplet_speed,
		"droplet_seed": droplet_seed,
		"tulle_geometry_enabled": tulle_geometry_enabled,
		"eye_geometry_enabled": false,
		"hair_dynamic_enabled": hair_dynamic_enabled,
		"hair_collision_enabled": hair_collision_enabled,
		"authored_materials_enabled": authored_materials_enabled,
	}


func load_data(data: Variant) -> bool:
	# Saved V1.2 preview schemes predate equipment and visual-direction controls.
	if data is Dictionary and data.get("schema") == 1:
		data = data.duplicate(true)
		data.schema = 2
		if not data.has("equipment"):
			data.equipment = [false, false, false, false]
		if not data.has("action"):
			data.action = 0
		if not data.has("blink"):
			data.blink = true
		if not data.has("secondary"):
			data.secondary = true
	if data is Dictionary and data.get("schema") == 2:
		data = data.duplicate(true)
		data.schema = 3
		if not data.has("hosiery_style"):
			data.hosiery_style = 0
		if not data.has("hosiery_stitch"):
			data.hosiery_stitch = 0.0
		if not data.has("wetness_regions"):
			data.wetness_regions = [0.0, 0.0, 0.0, 0.0]
		if not data.has("eye_wetness"):
			data.eye_wetness = 0.0
		if not data.has("wind_strength"):
			data.wind_strength = 0.0
		if not data.has("soft_tissue_pressure"):
			data.soft_tissue_pressure = 0.0
	if data is Dictionary and data.get("schema") == 3:
		data = data.duplicate(true)
		data.schema = 4
		if not data.has("droplets_enabled"):
			data.droplets_enabled = false
		if not data.has("droplet_count"):
			data.droplet_count = 0
		if not data.has("droplet_speed"):
			data.droplet_speed = 0.35
		if not data.has("droplet_seed"):
			data.droplet_seed = 17
		if not data.has("tulle_geometry_enabled"):
			data.tulle_geometry_enabled = false
		if not data.has("eye_geometry_enabled"):
			data.eye_geometry_enabled = false
	if data is Dictionary and data.get("schema") == 4:
		data = data.duplicate(true)
		data.schema = 5
		for key in ["hair_dynamic_enabled", "hair_collision_enabled", "authored_materials_enabled"]:
			if not data.has(key):
				data[key] = false
	if data is Dictionary and data.get("schema") == 5:
		data = data.duplicate(true)
		data.schema = 6
		if not data.has("hosiery_height"):
			data.hosiery_height = 1.34
	if data is Dictionary and data.get("schema") == 6:
		data = data.duplicate(true)
		data.schema = 7
		for key in ["hosiery_sheen", "hosiery_weave", "hosiery_roughness"]:
			if not data.has(key):
				data[key] = {
					"hosiery_sheen": 0.20, "hosiery_weave": 0.035, "hosiery_roughness": 0.27
				}[key]
	if data is Dictionary and data.get("schema") == 7:
		data = data.duplicate(true)
		data.schema = 8
		for key in ["eye_left", "eye_right"]:
			if not data.has(key):
				data[key] = [0.0, 0.0, 1.0]
	if data is Dictionary and data.get("schema") == 8:
		data = data.duplicate(true)
		data.schema = 9
		data.eye_symbol = 0
		data.eye_symbol_size = 1.0
		data.eye_symbol_stroke = 0.10
	if data is Dictionary and data.get("schema") == 9:
		data = data.duplicate(true)
		data.schema = 10
		data.mouth_symbol = 0
		data.mouth_symbol_size = 1.0
		data.mouth_symbol_stroke = 0.10
	if not _valid_structure(data) or not _valid_choices(data):
		return false
	palette = int(data.palette)
	expression = int(data.expression)
	equipment = data.equipment.duplicate()
	action = int(data.action)
	blink = data.blink
	secondary = data.secondary
	stocking_transparency = data.stocking_transparency
	hosiery_style = int(data.hosiery_style)
	hosiery_stitch = float(data.hosiery_stitch)
	hosiery_height = float(data.hosiery_height)
	hosiery_sheen = float(data.hosiery_sheen)
	hosiery_weave = float(data.hosiery_weave)
	hosiery_roughness = float(data.hosiery_roughness)
	for index in wetness_regions.size():
		wetness_regions[index] = float(data.wetness_regions[index])
	eye_wetness = float(data.eye_wetness)
	eye_left = data.eye_left.duplicate()
	eye_right = data.eye_right.duplicate()
	eye_symbol = int(data.eye_symbol)
	mouth_symbol = int(data.mouth_symbol)
	eye_symbol_size = float(data.eye_symbol_size)
	mouth_symbol_size = float(data.mouth_symbol_size)
	eye_symbol_stroke = float(data.eye_symbol_stroke)
	mouth_symbol_stroke = float(data.mouth_symbol_stroke)
	wind_strength = float(data.wind_strength)
	soft_tissue_pressure = float(data.soft_tissue_pressure)
	droplets_enabled = data.droplets_enabled
	droplet_count = int(data.droplet_count)
	droplet_speed = float(data.droplet_speed)
	droplet_seed = int(data.droplet_seed)
	tulle_geometry_enabled = data.tulle_geometry_enabled
	# Accept old schema 6 schemes without bringing back the retired replacement eyes.
	eye_geometry_enabled = false
	hair_dynamic_enabled = data.hair_dynamic_enabled
	hair_collision_enabled = data.hair_collision_enabled
	authored_materials_enabled = data.authored_materials_enabled
	for channel in 3:
		colors[channel] = Color(data.colors[channel])
	return true


func _valid_structure(data: Variant) -> bool:
	var valid: bool = data is Dictionary and data.size() == KEYS.size() and data.has_all(KEYS)
	if not valid:
		return false
	valid = data.schema == 10 and data.character == _character_id
	for key in [
		"eye_symbol",
		"eye_symbol_size",
		"eye_symbol_stroke",
		"mouth_symbol",
		"mouth_symbol_size",
		"mouth_symbol_stroke"
	]:
		if not (data[key] is float or data[key] is int) or not is_finite(float(data[key])):
			return false
	valid = valid and data.eye_symbol == int(data.eye_symbol)
	valid = valid and data.eye_symbol >= 0 and data.eye_symbol < EYE_SYMBOLS.size()
	valid = valid and data.eye_symbol_size >= 0.65 and data.eye_symbol_size <= 1.2
	valid = valid and data.eye_symbol_stroke >= 0.05 and data.eye_symbol_stroke <= 0.18
	valid = valid and data.mouth_symbol == int(data.mouth_symbol)
	valid = valid and data.mouth_symbol >= 0 and data.mouth_symbol < MOUTH_SYMBOLS.size()
	valid = valid and data.mouth_symbol_size >= 0.65 and data.mouth_symbol_size <= 1.2
	valid = valid and data.mouth_symbol_stroke >= 0.05 and data.mouth_symbol_stroke <= 0.18
	# Eye controllers store scale in Vector3 (real_t), then JSON preserves that value.
	# Accept the exact represented endpoints, not an arbitrary validation tolerance.
	var pupil_range := Vector2(0.65, 1.35)
	for key in ["eye_left", "eye_right"]:
		if not data[key] is Array or data[key].size() != 3:
			return false
		for value in data[key]:
			if not (value is float or value is int) or not is_finite(float(value)):
				return false
		var eye: Array = data[key]
		valid = valid and Vector2(eye[0], eye[1]).length() <= 1.000001
		valid = (
			valid and eye[2] >= minf(0.65, pupil_range.x) and eye[2] <= maxf(1.35, pupil_range.y)
		)
	for key in [
		"palette",
		"stocking_transparency",
		"expression",
		"action",
		"hosiery_style",
		"hosiery_stitch",
		"hosiery_height",
		"hosiery_sheen",
		"hosiery_weave",
		"hosiery_roughness",
		"eye_wetness",
		"wind_strength",
		"soft_tissue_pressure"
	]:
		valid = valid and (data[key] is float or data[key] is int) and is_finite(float(data[key]))
	valid = valid and data.colors is Array and data.colors.size() == 3
	if data.colors is Array:
		for color in data.colors:
			valid = valid and color is String and color.length() == 6 and Color.html_is_valid(color)
	valid = valid and data.wetness_regions is Array and data.wetness_regions.size() == 4
	if data.wetness_regions is Array:
		for value in data.wetness_regions:
			valid = valid and (value is float or value is int) and is_finite(float(value))
	valid = valid and data.droplets_enabled is bool
	valid = valid and data.tulle_geometry_enabled is bool
	valid = valid and data.eye_geometry_enabled is bool
	for key in ["hair_dynamic_enabled", "hair_collision_enabled", "authored_materials_enabled"]:
		valid = valid and data[key] is bool
	for key in ["droplet_count", "droplet_seed"]:
		var value: Variant = data[key]
		valid = (
			valid
			and (value is int or value is float)
			and is_finite(float(value))
			and is_equal_approx(float(value), floorf(float(value)))
		)
	valid = valid and (data.droplet_speed is float or data.droplet_speed is int)
	valid = valid and is_finite(float(data.droplet_speed))
	return valid


func _valid_choices(data: Dictionary) -> bool:
	var valid: bool = data.equipment is Array and data.equipment.size() == 4
	if data.equipment is Array:
		for choice in data.equipment:
			valid = valid and choice is bool
	valid = (
		valid
		and data.palette == int(data.palette)
		and data.palette >= -1
		and data.palette < _palette_profile.labels.size()
	)
	valid = (
		valid
		and data.expression == int(data.expression)
		and data.expression >= 0
		and data.expression < EXPRESSIONS.size()
	)
	valid = valid and data.stocking_transparency >= 0 and data.stocking_transparency <= 1
	valid = valid and _height_profile.accepts(data.hosiery_height)
	valid = valid and data.hosiery_sheen >= 0.0 and data.hosiery_sheen <= 0.5
	valid = valid and data.hosiery_weave >= 0.0 and data.hosiery_weave <= 0.1
	valid = valid and data.hosiery_roughness >= 0.18 and data.hosiery_roughness <= 0.6
	valid = (
		valid
		and data.hosiery_style == int(data.hosiery_style)
		and data.hosiery_style >= 0
		and data.hosiery_style <= 2
	)
	for key in ["hosiery_stitch", "eye_wetness", "wind_strength", "soft_tissue_pressure"]:
		valid = valid and data[key] >= 0 and data[key] <= 1
	valid = valid and data.droplet_count >= 0 and data.droplet_count <= 12
	valid = valid and data.droplet_speed >= 0 and data.droplet_speed <= 1
	valid = valid and data.droplet_seed >= 0 and data.droplet_seed <= 2147483647
	for value in data.wetness_regions:
		valid = valid and float(value) >= 0.0 and float(value) <= 1.0
	return (
		valid
		and (
			data.action == int(data.action)
			and data.action >= 0
			and data.action < 4
			and data.blink is bool
			and data.secondary is bool
		)
	)
