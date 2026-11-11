extends RefCounted

# Every playback knob and the main synthesis knobs of the procedural SFX library.
# Playback: volume_db, pitch_jitter (fraction), volume_jitter_db, max_voices,
# strength_db (attenuation at strength 0), strength_pitch (pitch offset per unit of strength above 0.5),
# variations, tiers (strength picks the tier; synth gets weight 0..1), surfaces, loop.
# "synth" holds per-recipe parameters read by sfx_synth.gd.

const SAMPLE_RATE := 22050
const BASE_SEED := 7331
const TARGET_PEAK := 0.84 # about -1.5 dBFS after normalization
const FADE_IN_MS := 1.0
const FADE_OUT_MS := 8.0
const TRIM_DB := -66.0

const BUS_NAME := &"SFX"
const BUS_VOLUME_DB := 0.0
const DRY_BUS_NAME := &"SFX_UI" # ids with dry = true: UI and the underwater bed, never muffled
const UNDERWATER := {cutoff_hz = 650.0, open_hz = 20500.0, resonance = 0.6, pitch = 0.93}
const COMPRESSOR := {threshold = -14.0, ratio = 3.0, attack_us = 2000.0, release_ms = 120.0, gain = 0.0}
const MASTER_LIMITER := {ceiling_db = -1.0, pre_gain_db = 0.0, release = 0.12}

const POOL_FLAT := 16
const POOL_2D := 24
const LOOP_FADE_IN := 0.04
const MAX_DISTANCE_2D := 2400.0
const ATTENUATION_2D := 1.4
const PANNING_2D := 0.6

const DEFAULTS := {
	volume_db = -6.0,
	pitch_jitter = 0.05,
	volume_jitter_db = 1.5,
	max_voices = 4,
	strength_db = 10.0,
	strength_pitch = -0.08,
	variations = 5,
	tiers = 1,
	surfaces = [],
	default_surface = &"",
	loop = false,
	dry = false,
	loop_pitch_low = 1.0, # loop pitch at set_loop_strength 0 (brightness)
	loop_pitch_high = 1.0, # loop pitch at set_loop_strength 1
	synth = {},
}

const SOUNDS := {
	# Movement
	&"footstep": {volume_db = -11.0, max_voices = 3, variations = 4, tiers = 2, strength_db = 12.0,
		surfaces = [&"grass", &"stone", &"wood", &"dirt", &"metal"], default_surface = &"dirt", pitch_jitter = 0.07,
		synth = {dur = 0.16, thump_hz = 110.0}},
	&"jump": {volume_db = -9.0, max_voices = 2, variations = 4, synth = {dur = 0.22}},
	&"land": {volume_db = -5.0, max_voices = 2, variations = 3, tiers = 3, strength_db = 9.0,
		surfaces = [&"grass", &"stone", &"wood", &"dirt", &"metal"], default_surface = &"dirt",
		synth = {dur_light = 0.18, dur_heavy = 0.55, thump_hz = 105.0}},
	&"skid": {volume_db = -10.0, loop = true, variations = 1, max_voices = 2, synth = {dur = 1.2, band_hz = 1700.0}},
	&"wall_slide": {volume_db = -9.0, loop = true, variations = 1, max_voices = 2, strength_db = 14.0,
		loop_pitch_low = 0.8, loop_pitch_high = 1.08, synth = {dur = 1.4, band_hz = 2300.0, pebbles = 55}},
	&"roll": {volume_db = -8.0, max_voices = 2, variations = 4, synth = {dur = 0.42}},
	&"ledge_grab": {volume_db = -7.0, max_voices = 2, variations = 5, synth = {dur = 0.36, pebbles = 5}},
	&"climb": {volume_db = -11.0, max_voices = 2, variations = 5, synth = {dur = 0.28}},
	&"whoosh_small": {volume_db = -10.0, max_voices = 3, variations = 5, synth = {dur = 0.17, lo_hz = 500.0, hi_hz = 2200.0}},
	&"whoosh_big": {volume_db = -8.0, max_voices = 2, variations = 5, synth = {dur = 0.32, lo_hz = 260.0, hi_hz = 1300.0}},
	# Melee
	&"punch_swing": {volume_db = -10.0, max_voices = 3, variations = 5, synth = {dur = 0.12, lo_hz = 800.0, hi_hz = 3000.0}},
	&"punch_hit": {volume_db = -4.0, max_voices = 3, variations = 6, synth = {dur = 0.2, thump_hz = 170.0, drive = 1.8}},
	&"kick_hit": {volume_db = -3.0, max_voices = 2, variations = 5, synth = {dur = 0.38, thump_hz = 125.0, drive = 2.2}},
	&"kunai_slash": {volume_db = -8.0, max_voices = 3, variations = 5, synth = {dur = 0.26}},
	&"ninja_poof": {volume_db = -7.0, max_voices = 2, variations = 4, synth = {dur = 0.45}},
	# Firearms
	&"revolver_cock": {volume_db = -8.0, max_voices = 1, variations = 4, synth = {dur = 0.24, gap = 0.11}},
	&"revolver_shot": {volume_db = -2.0, max_voices = 3, variations = 5, pitch_jitter = 0.04, synth = {dur = 0.95, drive = 2.5}},
	&"rifle_shot": {volume_db = -5.0, max_voices = 5, variations = 6, pitch_jitter = 0.035, volume_jitter_db = 1.0,
		synth = {dur = 0.34, drive = 2.5}},
	# Ricochet off a steel surface (surface = what bounced: bullet whine, arrow knock, blade clang)
	&"ricochet": {volume_db = -7.0, max_voices = 4, variations = 6, pitch_jitter = 0.08, strength_db = 9.0,
		surfaces = [&"bullet", &"arrow", &"blade"], default_surface = &"bullet", synth = {dur = 0.42, ring_hz = 2600.0}},
	&"casing_bounce": {volume_db = -14.0, max_voices = 4, variations = 6, pitch_jitter = 0.08, synth = {dur = 0.3}},
	# Bow
	&"bow_draw": {volume_db = -10.0, max_voices = 1, variations = 4, synth = {dur = 0.65}},
	&"bow_release": {volume_db = -6.0, max_voices = 2, variations = 4, synth = {dur = 0.42, string_hz = 98.0}},
	&"arrow_whoosh": {volume_db = -11.0, max_voices = 3, variations = 4, synth = {dur = 0.28}},
	&"arrow_hit": {volume_db = -6.0, max_voices = 3, variations = 5, synth = {dur = 0.36}},
	# Damage
	&"hurt_hit": {volume_db = -4.0, max_voices = 2, variations = 6, synth = {dur = 0.24, thump_hz = 105.0}},
	&"bullet_hit_body": {volume_db = -4.0, max_voices = 3, variations = 5, synth = {dur = 0.34}},
	&"blood_splat": {volume_db = -11.0, max_voices = 2, variations = 5, synth = {dur = 0.5, drops = 6}},
	# Breakable wall
	&"wall_crack": {volume_db = -6.0, max_voices = 2, variations = 4, synth = {dur = 0.5}},
	&"wall_break": {volume_db = -1.0, max_voices = 1, variations = 4, pitch_jitter = 0.04, synth = {dur = 1.6, chunks = 46, drive = 2.0}},
	&"debris_bounce": {volume_db = -12.0, max_voices = 6, variations = 6, pitch_jitter = 0.1, synth = {dur = 0.32}},
	# Props
	&"chair_creak": {volume_db = -10.0, max_voices = 1, variations = 4, synth = {dur = 0.5, formant_hz = 850.0}},
	&"bed_creak": {volume_db = -10.0, max_voices = 1, variations = 4, synth = {dur = 0.75, formant_hz = 520.0}},
	&"trap_snap": {volume_db = -4.0, max_voices = 2, variations = 4, synth = {dur = 0.4}},
	&"turret_shot": {volume_db = -6.0, max_voices = 4, variations = 5, synth = {dur = 0.36, drive = 2.0}},
	# Training props (scarecrow_hit surface = hit type: blunt or slash)
	&"scarecrow_hit": {volume_db = -6.0, max_voices = 3, variations = 5, surfaces = [&"blunt", &"slash"],
		default_surface = &"blunt", synth = {dur = 0.34}},
	&"cup_hit": {volume_db = -10.0, max_voices = 4, variations = 6, pitch_jitter = 0.08, synth = {dur = 0.12}},
	&"cup_fall": {volume_db = -13.0, max_voices = 4, variations = 6, pitch_jitter = 0.08, synth = {dur = 0.5}},
	&"button_press": {volume_db = -9.0, max_voices = 2, variations = 4, pitch_jitter = 0.03, synth = {dur = 0.16}},
	# Balloons
	&"balloon_pop": {volume_db = -6.0, max_voices = 4, variations = 6, pitch_jitter = 0.1, synth = {dur = 0.12}},
	&"balloon_release": {volume_db = -10.0, max_voices = 2, variations = 4, synth = {dur = 0.45}},
	# Bow aim (loop, set_loop_strength = draw force)
	&"bow_aim": {volume_db = -12.0, loop = true, variations = 1, max_voices = 1, strength_db = 10.0,
		loop_pitch_low = 0.85, loop_pitch_high = 1.12, synth = {dur = 1.0}},
	# Water
	&"splash": {volume_db = -5.0, max_voices = 3, variations = 4, tiers = 3, strength_db = 9.0,
		synth = {dur_light = 0.3, dur_heavy = 0.95}},
	&"splash_out": {volume_db = -9.0, max_voices = 2, variations = 4, synth = {dur = 0.8}},
	&"swim_stroke": {volume_db = -11.0, max_voices = 2, variations = 6, pitch_jitter = 0.07, synth = {dur = 0.28}},
	&"swim_under": {volume_db = -11.0, max_voices = 2, variations = 6, synth = {dur = 0.4}},
	&"bubble": {volume_db = -14.0, max_voices = 6, variations = 8, pitch_jitter = 0.12, synth = {dur = 0.1}},
	&"underwater": {dry = true, volume_db = -12.0, loop = true, variations = 1, max_voices = 1, synth = {dur = 2.0}},
	&"water_flow": {volume_db = -9.0, loop = true, variations = 1, max_voices = 3, strength_db = 16.0,
		loop_pitch_low = 0.85, loop_pitch_high = 1.1, synth = {dur = 1.6, gurgles = 26}},
	&"dam_break": {volume_db = -1.0, max_voices = 1, variations = 3, pitch_jitter = 0.03, synth = {dur = 2.4, chunks = 40, drive = 1.8}},
	&"oxygen_warning": {dry = true, volume_db = -14.0, max_voices = 1, variations = 2, pitch_jitter = 0.0, synth = {dur = 0.22}},
	&"drown_hit": {volume_db = -5.0, max_voices = 2, variations = 5, synth = {dur = 0.42}},
	# Ending sequence
	&"quake_rumble": {volume_db = -6.0, loop = true, variations = 1, max_voices = 1, strength_db = 18.0,
		loop_pitch_low = 0.8, loop_pitch_high = 1.15, synth = {dur = 2.2, creaks = 34}},
	&"rock_fall": {volume_db = -5.0, max_voices = 6, variations = 4, tiers = 3, strength_db = 8.0, pitch_jitter = 0.08,
		synth = {dur_light = 0.25, dur_heavy = 0.7}},
	&"cave_in": {volume_db = 0.0, max_voices = 1, variations = 2, pitch_jitter = 0.02, synth = {dur = 4.0, gravel = 120, drive = 2.0}},
	&"ending_sting": {dry = true, volume_db = -8.0, max_voices = 1, variations = 1, pitch_jitter = 0.0, synth = {dur = 2.8}},
	# Motocross (moto_engine: set_loop_strength = throttle / rpm)
	&"moto_engine": {volume_db = -10.0, loop = true, variations = 1, max_voices = 1, strength_db = 8.0,
		loop_pitch_low = 0.55, loop_pitch_high = 1.9, synth = {dur = 1.2, hz = 46.0}},
	&"moto_crash": {volume_db = -3.0, max_voices = 1, variations = 3, synth = {dur = 0.9}},
	# UI
	&"achievement": {dry = true, volume_db = -7.0, max_voices = 1, variations = 1, pitch_jitter = 0.0, synth = {dur = 1.3, step = 0.09}},
	&"menu_move": {dry = true, volume_db = -16.0, max_voices = 2, variations = 3, pitch_jitter = 0.015, synth = {dur = 0.05}},
	&"menu_select": {dry = true, volume_db = -11.0, max_voices = 2, variations = 2, pitch_jitter = 0.0, synth = {dur = 0.18}},
	&"pause_open": {dry = true, volume_db = -12.0, max_voices = 1, variations = 2, pitch_jitter = 0.0, synth = {dur = 0.16}},
	&"pause_close": {dry = true, volume_db = -12.0, max_voices = 1, variations = 2, pitch_jitter = 0.0, synth = {dur = 0.16}},
	&"prompt_pop": {dry = true, volume_db = -22.0, max_voices = 1, variations = 4, pitch_jitter = 0.03, synth = {dur = 0.1}},
	&"weapon_switch": {dry = true, volume_db = -10.0, max_voices = 2, variations = 4, pitch_jitter = 0.02, synth = {dur = 0.09}},
}


static func config(id: StringName) -> Dictionary:
	if not SOUNDS.has(id):
		return {}
	var merged := DEFAULTS.duplicate()
	merged.merge(SOUNDS[id], true)
	return merged
