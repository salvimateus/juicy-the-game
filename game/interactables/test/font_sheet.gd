extends SceneTree

# Font check sheet: godot --headless -s res://game/interactables/test/font_sheet.gd -- <out.png>
# Accented glyphs and sample phrases at 1x and 3x, plus real prompt boxes.

const PixelFont := preload("res://game/interactables/pixel_font.gd")
const Art := preload("res://game/interactables/interactables_art.gd")

const BG := Color("#20202c")
const FG := Color("#f2e8d0")
const ACCENTED := ["áéíóú âêô ãõ à ç", "ÁÉÍÓÚ ÂÊÔ ÃÕ À Ç"]
const PHRASES := ["E aí, sentiu o juicy?", "Restaurar a parede", "Levantar", "Abrir o buraco", "Curar o espantalho"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://font_sheet.png"
	var lines: Array = ACCENTED + PHRASES
	# Each line drawn once at 1x into its own strip (rows ACCENT_TOP..LINE_BOTTOM + 1 margin).
	var line_h := PixelFont.LINE_BOTTOM - PixelFont.ACCENT_TOP + 3
	var w1 := 0
	for t in lines:
		w1 = maxi(w1, PixelFont.measure(t) + 4)
	var strip := Image.create(w1, line_h * lines.size(), false, Image.FORMAT_RGBA8)
	strip.fill(BG)
	for i in lines.size():
		PixelFont.draw(strip, lines[i], Vector2i(2, i * line_h + 1 - PixelFont.ACCENT_TOP), FG)
	var big := strip.duplicate() as Image
	big.resize(strip.get_width() * 3, strip.get_height() * 3, Image.INTERPOLATE_NEAREST)
	# Real prompt boxes (pad and key) for the phrases, at 3x.
	var boxes: Array[Image] = []
	for t in PHRASES:
		for pad in [true, false]:
			var b: Image = (Art.prompt_box(t, pad).texture as Texture2D).get_image()
			boxes.append(b)
	var bw := 0
	var bh := 0
	for b in boxes:
		bw = maxi(bw, b.get_width())
		bh += b.get_height() + 2
	var box_img := Image.create(bw * 2 + 6, bh / 2 + 4, false, Image.FORMAT_RGBA8)
	box_img.fill(BG)
	var y := 2
	for i in range(0, boxes.size(), 2):
		box_img.blend_rect(boxes[i], Rect2i(Vector2i.ZERO, boxes[i].get_size()), Vector2i(2, y))
		box_img.blend_rect(boxes[i + 1], Rect2i(Vector2i.ZERO, boxes[i + 1].get_size()), Vector2i(bw + 4, y))
		y += boxes[i].get_height() + 2
	box_img.resize(box_img.get_width() * 3, box_img.get_height() * 3, Image.INTERPOLATE_NEAREST)
	var W := maxi(big.get_width(), box_img.get_width()) + strip.get_width() + 30
	var H := maxi(big.get_height(), strip.get_height()) + box_img.get_height() + 30
	var sheet := Image.create(W, H, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#141018"))
	sheet.blit_rect(strip, Rect2i(Vector2i.ZERO, strip.get_size()), Vector2i(10, 10))
	sheet.blit_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), Vector2i(strip.get_width() + 20, 10))
	sheet.blit_rect(box_img, Rect2i(Vector2i.ZERO, box_img.get_size()), Vector2i(10, maxi(big.get_height(), strip.get_height()) + 20))
	var err := sheet.save_png(out)
	print("SHEET ", out, " ", sheet.get_size(), " err=", err, " top_row(E aí)=", PixelFont.top_row("E aí, sentiu o juicy?"), " top_row(ÁÉ)=", PixelFont.top_row("ÁÉ"))
	quit()
