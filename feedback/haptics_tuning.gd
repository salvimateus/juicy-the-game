extends RefCounted

# Rumble profiles. weak = small high-frequency motor, strong = big low-frequency motor (0..1).
# Pulse layer: weak, strong, dur (s), curve (decay exponent of (1 - t/dur); 0 = flat), delay (s),
# hold (s at full amplitude, default DEFAULT_HOLD), wobble_hz / wobble_depth (tremor). Profile: layers, gate (min strength to fire),
# strength_exp (amplitude = layer * strength^exp). Loop profile: loop = true, weak, strong, wobble_*.

const QUANT_STEP := 0.04
const MAX_STRENGTH := 1.5
const AXIS_DEADZONE := 0.35
const LOOP_FADE := 0.1
# Full-amplitude time before the decay starts; motors need a few frames to spin up.
const DEFAULT_HOLD := 0.017

const PROFILES := {
	&"footstep": {gate = 0.85, layers = [{weak = 0.14, strong = 0.0, dur = 0.05, curve = 2.0}]},
	&"jump": {layers = [{weak = 0.25, strong = 0.1, dur = 0.07, curve = 1.5}]},
	&"land": {strength_exp = 1.5, layers = [
		{weak = 0.45, strong = 0.6, dur = 0.14, curve = 2.0},
		{weak = 0.0, strong = 0.3, dur = 0.25, curve = 1.0, delay = 0.03}]},
	&"skid": {loop = true, weak = 0.18, strong = 0.32, wobble_hz = 14.0, wobble_depth = 0.35},
	&"wall_slide": {loop = true, weak = 0.08, strong = 0.22, wobble_hz = 22.0, wobble_depth = 0.6},
	&"roll": {layers = [{weak = 0.3, strong = 0.2, dur = 0.12, curve = 1.5}]},
	&"ledge_grab": {layers = [{weak = 0.4, strong = 0.25, dur = 0.08, curve = 2.0}]},
	&"climb": {layers = [{weak = 0.12, strong = 0.0, dur = 0.05, curve = 1.5}]},
	&"punch_hit": {layers = [{weak = 0.7, strong = 0.55, dur = 0.09, curve = 2.5}]},
	&"kick_hit": {layers = [{weak = 0.8, strong = 0.85, dur = 0.16, curve = 2.0}]},
	&"ninja_poof": {layers = [{weak = 0.2, strong = 0.3, dur = 0.15, curve = 1.5}]},
	&"revolver_shot": {layers = [{weak = 0.9, strong = 0.75, dur = 0.12, hold = 0.03, curve = 3.0}]},
	&"rifle_shot": {layers = [{weak = 0.55, strong = 0.45, dur = 0.06, hold = 0.03, curve = 2.0}]},
	# Own shot glancing off steel: a sharp tick on the small motor.
	&"ricochet": {strength_exp = 1.3, layers = [{weak = 0.5, strong = 0.12, dur = 0.05, curve = 2.5}]},
	&"bow_release": {layers = [{weak = 0.6, strong = 0.15, dur = 0.06, curve = 3.0}]},
	&"hurt_hit": {layers = [{weak = 0.75, strong = 0.8, dur = 0.2, curve = 2.0}]},
	&"bullet_hit_body": {layers = [
		{weak = 1.0, strong = 1.0, dur = 0.18, curve = 1.2},
		{weak = 0.4, strong = 0.8, dur = 0.45, curve = 2.0, delay = 0.1, wobble_hz = 10.0, wobble_depth = 0.4}]},
	&"wall_break": {layers = [
		{weak = 1.0, strong = 1.0, dur = 0.12, curve = 1.5},
		{weak = 0.35, strong = 0.7, dur = 0.6, curve = 1.6, delay = 0.05, wobble_hz = 18.0, wobble_depth = 0.5}]},
	&"trap_snap": {layers = [{weak = 0.8, strong = 0.7, dur = 0.14, curve = 2.0}]},
	&"turret_shot": {layers = [{weak = 0.5, strong = 0.5, dur = 0.09, curve = 2.0}]},
	&"scarecrow_hit": {layers = [{weak = 0.45, strong = 0.4, dur = 0.1, curve = 2.0}]},
	&"cup_hit": {layers = [{weak = 0.08, strong = 0.0, dur = 0.03, curve = 1.0}]},
	&"button_press": {layers = [{weak = 0.3, strong = 0.0, dur = 0.03, curve = 1.0}]},
	&"balloon_pop": {layers = [{weak = 0.25, strong = 0.0, dur = 0.03, curve = 1.0}]},
	&"splash": {strength_exp = 1.3, layers = [
		{weak = 0.4, strong = 0.5, dur = 0.15, curve = 2.0},
		{weak = 0.0, strong = 0.25, dur = 0.4, curve = 1.5, delay = 0.05, wobble_hz = 12.0, wobble_depth = 0.5}]},
	&"swim_stroke": {layers = [{weak = 0.08, strong = 0.04, dur = 0.05, curve = 1.5}]},
	&"dam_break": {layers = [
		{weak = 1.0, strong = 1.0, dur = 0.2, curve = 1.2},
		{weak = 0.4, strong = 0.9, dur = 1.4, curve = 1.4, delay = 0.1, wobble_hz = 14.0, wobble_depth = 0.5}]},
	&"drown_hit": {layers = [{weak = 0.45, strong = 0.55, dur = 0.14, curve = 2.0}]},
	&"water_flow": {loop = true, weak = 0.06, strong = 0.14, wobble_hz = 9.0, wobble_depth = 0.5},
	&"chair_creak": {layers = [{weak = 0.18, strong = 0.06, dur = 0.08, curve = 1.5}]},
	&"bed_creak": {layers = [{weak = 0.08, strong = 0.18, dur = 0.16, curve = 1.5}]},
	&"quake": {loop = true, weak = 0.2, strong = 0.55, wobble_hz = 7.0, wobble_depth = 0.5},
	&"rock_fall": {strength_exp = 1.2, layers = [{weak = 0.5, strong = 0.6, dur = 0.1, curve = 2.0}]},
	&"cave_in": {layers = [
		{weak = 1.0, strong = 1.0, dur = 0.3, hold = 0.12, curve = 1.0},
		{weak = 0.6, strong = 1.0, dur = 1.2, curve = 1.3, delay = 0.05, wobble_hz = 10.0, wobble_depth = 0.35}]},
	&"moto_engine": {loop = true, weak = 0.4, strong = 0.22, wobble_hz = 8.0, wobble_depth = 0.3},
	&"moto_crash": {layers = [{weak = 1.0, strong = 1.0, dur = 0.35, hold = 0.04, curve = 1.8}]},
	&"achievement": {layers = [
		{weak = 0.35, strong = 0.2, dur = 0.06, curve = 1.5},
		{weak = 0.5, strong = 0.4, dur = 0.14, curve = 2.0, delay = 0.12}]},
	&"menu_select": {layers = [{weak = 0.25, strong = 0.0, dur = 0.03, curve = 1.0}]},
	&"weapon_switch": {layers = [{weak = 0.2, strong = 0.0, dur = 0.03, curve = 1.0}]},
}
