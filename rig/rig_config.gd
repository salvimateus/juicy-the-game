class_name RigConfig
extends RefCounted
## Pixel-art pipeline constants shared by the rig and the game layer.
##
## 1 world unit = 1 source pixel of the art, drawn in ART_PIXEL blocks. A crisp art pixel needs the
## world-to-device scale to be k / ART_PIXEL with k an integer. The project renders with stretch
## mode canvas_items over BASE_RESOLUTION with integer scaling, so the world is drawn at native
## resolution (rotated parts keep the fine source-pixel stairs of the JS rig) and the base-to-device
## factor f is an integer: one art pixel spans ART_PIXEL * CAMERA_ZOOM * f = 3 * f device pixels
## (3 px windowed at 1280x720, 6 px fullscreen at 1440p, where 1 source px = 1 device px).

const ART_PIXEL := 6
## Base resolution of the canvas_items stretch (integer scale, aspect expand).
const BASE_RESOLUTION := Vector2i(1280, 720)
## Camera2D zoom in base units: 3 / ART_PIXEL, the character fills about 30% of the base height.
const CAMERA_ZOOM := 0.5
## Character height standing (sole to the top of the hair), in world units.
const CHARACTER_HEIGHT := 428.0


## Device pixels covered by one art pixel in a window (integer by construction).
static func art_pixel_device(window: Window) -> float:
	var visible := window.get_visible_rect().size
	var factor := maxf(1.0, float(window.size.y) / maxf(1.0, visible.y))
	return ART_PIXEL * CAMERA_ZOOM * factor
