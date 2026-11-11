extends RefCounted
## Gun FX on the art grid (masks from the JS shoot, cock and rifle clips): revolver and rifle
## muzzle flashes (origin on the barrel line), the hammer click glint and the rifle casing.

const FLASH_PAL := {"w": "#ffffff", "y": "#ffd040", "o": "#ff8020"}
const CASING_PAL := {"h": "#fff0a0", "y": "#e0b040", "o": "#9a6a1c"}


static func sprites() -> Array:
	return [
		# Frames 0-1 regular shot, 2-3 the heavier shot.
		RigFxSprites.masked("revolverFlash", 9, 7, Vector2(0, 3), PI / 4.0, FLASH_PAL, [
			[".........", "..o.o....", ".yyyyy...", "wwwwwyo..", ".yyyyy...", "..o.o....", "........."],
			[".........", ".........", "..y.y....", "wwwyo....", "..y.y....", ".........", "........."],
			["..o...o..", "...yyyy..", ".yyywwyy.", "wwwwwwwyo", ".yyywwyy.", "...yyyy..", "..o...o.."],
			[".........", "...o.o...", "..yyyy...", "wwwwyyo..", "..yyyy...", "...o.o...", "........."],
		]),
		# Three full shapes plus a small fading frame.
		RigFxSprites.masked("rifleFlash", 9, 7, Vector2(0, 3), PI / 4.0, FLASH_PAL, [
			["..o...o..", "...yyyy..", ".yyywwyy.", "wwwwwwwyo", ".yyywwyy.", "...yyyy..", "..o...o.."],
			[".....o...", "..yyyy...", "yyywwyyo.", "wwwwwwwww", "yyywwyyo.", "..yyyy...", ".....o..."],
			["...o.....", ".o.yy.o..", "..ywwyy..", "wwwwwwyyo", "..ywwyy..", ".o.yy.o..", "...o....."],
			[".........", ".........", "..y.y....", "wwwyo....", "..y.y....", ".........", "........."],
		]),
		# Pop, full star, scattered dots.
		RigFxSprites.masked("cockGlint", 7, 7, Vector2(3, 3), PI / 2.0, FLASH_PAL, [
			[".......", ".......", "...y...", "..ywy..", "...y...", ".......", "......."],
			["...w...", "...w...", "..ywy..", "wwwwwww", "..ywy..", "...w...", "...w..."],
			["...y...", ".o...o.", ".......", "y.....y", ".......", ".o...o.", "...y..."],
		]),
		RigFxSprites.masked("rifleCasing", 3, 2, Vector2(1, 1), PI / 4.0, CASING_PAL, [
			["hyy", "yoo"],
		]),
	]
