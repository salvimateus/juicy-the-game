extends StaticBody2D

# Riveted steel ricochet surface (meta ricochet): hanging on two chains that run up out of view, or
# standing on the ground as a barricade (chain_top at or below the top: no chains, no rattle).
# Walkable on top like any block (surface metal); a hanging plate's art rattles one art pixel when
# a projectile glances off it. Built from code: setup(rect, chain_top) before adding it to the tree.

const PixelArt := preload("res://game/pixel_art.gd")
const GameScale := preload("res://game/game_scale.gd")
const Ricochet := preload("res://game/ricochet/ricochet.gd")

# Share of speed the plate gives back (Ricochet contract).
var restitution := 1.0
var rattle_time := 0.16
var chain_inset := 3

var rect := Rect2(0, -1020, 96, 1020)
var chain_top := -2400.0
var _sprite: Sprite2D
var _rattle := 0.0
var _a := 6


func setup(plate_rect: Rect2, chain_top_y: float) -> void:
	rect = plate_rect
	chain_top = chain_top_y


func _ready() -> void:
	_a = GameScale.art_pixel()
	position = rect.position
	set_meta(&"surface", &"metal")
	set_meta(&"wall_top", rect.position.y)
	set_meta(&"wall_bottom", rect.end.y)
	set_meta(Ricochet.META, restitution)
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.size * 0.5
	add_child(shape)
	var w := int(rect.size.x / _a)
	var h := int(rect.size.y / _a)
	var chain_h := int((rect.position.y - chain_top) / _a)
	if chain_h > 0:
		var chain_tex := PixelArt.steel_chain(chain_h)
		for cx in [chain_inset, w - chain_inset - 3]:
			var chain := Sprite2D.new()
			chain.name = "Chain"
			chain.texture = chain_tex
			chain.centered = false
			chain.scale = Vector2(_a, _a)
			chain.position = Vector2(cx * _a, -chain_h * _a)
			add_child(chain)
	_sprite = Sprite2D.new()
	_sprite.name = "Plate"
	_sprite.texture = PixelArt.steel_plate(w, h)
	_sprite.centered = false
	_sprite.scale = Vector2(_a, _a)
	add_child(_sprite)
	set_process(false)


# Ricochet contract hook: a short rattle, longer for stronger hits.
func on_ricochet(_point: Vector2, _normal: Vector2, strength: float) -> void:
	if chain_top >= rect.position.y:
		return
	_rattle = maxf(_rattle, rattle_time * clampf(strength, 0.4, 1.2))
	set_process(true)


func _process(delta: float) -> void:
	_rattle = maxf(0.0, _rattle - delta)
	var phase := int(_rattle * 50.0) % 2
	_sprite.position.x = (float(_a) if phase == 0 else -float(_a)) if _rattle > 0.0 else 0.0
	if _rattle <= 0.0:
		set_process(false)
