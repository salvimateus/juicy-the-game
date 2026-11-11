extends RefCounted
## Swimming FX on the art grid: bubbles (small, large, popping), water drops (rising, falling,
## streak) and the foam crest that slides along the water line.

const PALETTE := {"o": "#1e4a6a", "w": "#f4fcff", "l": "#a8e0f4", "m": "#58a8d8"}


static func sprites() -> Array:
	return [
		RigFxSprites.masked("swimBubble", 4, 4, Vector2(2, 2), PI / 2, PALETTE, [
			["....", ".wl.", ".lo.", "...."],
			[".ll.", "lw.l", "l..l", ".ll."],
			["l..l", "....", "....", "l..l"],
		]),
		RigFxSprites.masked("swimDrop", 2, 3, Vector2(1, 1), PI / 2, PALETTE, [
			["w.", "lm", ".."],
			["w.", "l.", "m."],
			["l.", "m.", ".."],
		]),
		RigFxSprites.masked("swimFoam", 7, 3, Vector2(3, 2), PI / 2, PALETTE, [
			["..ww...", ".wllw..", "lmmmml."],
			[".w..ww.", "wl.wllw", "mm.lmmm"],
			["w....w.", ".l..l.l", "m.m..m."],
		]),
	]
