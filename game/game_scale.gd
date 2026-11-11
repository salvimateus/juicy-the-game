extends RefCounted

# Scale constants from res://rig/rig_config.gd (RigConfig) when it exists, with fallbacks.
# 1 unit = 1 source px of the art; ART_PIXEL source px make one chunky art pixel.

const RIG_CONFIG_PATH := "res://rig/rig_config.gd"
const FALLBACK_ART_PIXEL := 6
const FALLBACK_ZOOM := 0.5
const FALLBACK_CHARACTER_HEIGHT := 380.0

static var _constants: Dictionary = {}
static var _loaded := false


static func _config() -> Dictionary:
	if not _loaded:
		_loaded = true
		if ResourceLoader.exists(RIG_CONFIG_PATH):
			var script := load(RIG_CONFIG_PATH) as Script
			if script:
				_constants = script.get_script_constant_map()
	return _constants


static func art_pixel() -> int:
	return int(_config().get("ART_PIXEL", FALLBACK_ART_PIXEL))


# RigConfig.CAMERA_ZOOM (base units, canvas_items stretch with integer scale), snapped to a
# multiple of 1 / ART_PIXEL so one art pixel is a whole number of base pixels.
static func camera_zoom(_window: Window = null) -> float:
	var value: Variant = _config().get("CAMERA_ZOOM", null)
	if value == null:
		for key in _config():
			if "ZOOM" in String(key):
				value = _config()[key]
				break
	var zoom := FALLBACK_ZOOM
	if value is float or value is int:
		zoom = float(value)
	elif value is Vector2:
		zoom = value.x
	var a := float(art_pixel())
	return maxf(1.0 / a, roundf(zoom * a) / a)


static func character_height() -> float:
	for key in ["CHARACTER_HEIGHT", "HEIGHT", "BODY_HEIGHT"]:
		if _config().has(key):
			return float(_config()[key])
	return FALLBACK_CHARACTER_HEIGHT
