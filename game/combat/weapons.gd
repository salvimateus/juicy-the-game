extends RefCounted

# Weapon roster in cycle order. `ready` marks weapons whose attacks the game already handles.

const ORDER: Array[StringName] = [&"unarmed", &"fists", &"revolver", &"rifle", &"bow", &"kunai"]
const NAMES := {
	&"unarmed": "Sem armas",
	&"fists": "Mãos",
	&"revolver": "Revólver",
	&"rifle": "Fuzil AK",
	&"bow": "Arco",
	&"kunai": "Kunai",
}
const READY: Array[StringName] = [&"unarmed", &"fists", &"bow", &"revolver", &"rifle", &"kunai"]
# Control hint under the weapon name.
const HINTS := {
	&"unarmed": "X socar · X no ar: voadora",
	&"fists": "X socar · X no ar: voadora",
	&"revolver": "LT mirar · Analógico dir. apontar · RT atirar · X no ar: voadora",
	&"rifle": "LT mirar · Analógico dir. apontar · RT atirar · X no ar: voadora",
	&"bow": "LT mirar · Analógico dir. apontar e força · RT atirar · X no ar: voadora",
	&"kunai": "X golpe ninja · X no ar: voadora",
}


static func hint(id: StringName) -> String:
	return HINTS.get(id, "")


static func label(id: StringName) -> String:
	return NAMES.get(id, String(id)) + ("" if id in READY else " (em breve)")


# Small icons drawn on the art grid (one texel per art pixel), keyed by weapon id.
static func icon(id: StringName) -> ImageTexture:
	var img := Image.create(14, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var ink := Color("#141013")
	var metal := Color("#b8b8c8")
	var wood := Color("#8a5a3a")
	var red := Color("#c84a4a")
	var skin := Color("#eca076")
	match id:
		&"unarmed":
			img.fill_rect(Rect2i(4, 1, 7, 9), ink)
			img.fill_rect(Rect2i(3, 4, 2, 3), ink)
			img.fill_rect(Rect2i(5, 4, 5, 5), skin)
			for x in [5, 7, 9]:
				img.fill_rect(Rect2i(x, 2, 1, 2), skin)
			img.set_pixel(4, 5, skin)
		&"fists":
			img.fill_rect(Rect2i(3, 2, 8, 6), ink)
			img.fill_rect(Rect2i(4, 3, 6, 4), red)
			img.fill_rect(Rect2i(4, 3, 6, 1), Color("#e07070"))
			img.fill_rect(Rect2i(10, 4, 2, 3), red)
		&"revolver":
			img.fill_rect(Rect2i(2, 3, 10, 2), metal)
			img.fill_rect(Rect2i(5, 2, 3, 4), ink)
			img.fill_rect(Rect2i(3, 5, 3, 4), wood)
		&"rifle":
			img.fill_rect(Rect2i(0, 3, 14, 2), metal)
			img.fill_rect(Rect2i(0, 4, 4, 3), wood)
			img.fill_rect(Rect2i(7, 5, 2, 4), ink)
			img.fill_rect(Rect2i(9, 5, 2, 2), wood)
		&"bow":
			for y in 10:
				img.set_pixel(4 + absi(y - 5) / 2, y, wood)
			img.fill_rect(Rect2i(6, 0, 1, 10), Color("#e8e0c8"))
			img.fill_rect(Rect2i(6, 5, 7, 1), metal)
		&"kunai":
			img.fill_rect(Rect2i(2, 4, 6, 2), metal)
			img.fill_rect(Rect2i(8, 3, 2, 4), ink)
			img.fill_rect(Rect2i(10, 4, 3, 2), wood)
			img.set_pixel(1, 4, metal)
	return ImageTexture.create_from_image(img)
