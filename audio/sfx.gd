extends Node

# Autoload `Sfx`: synthesizes the whole library once at load, then plays it from pooled players.
# Command line: `-- --sfx-dump <dir>` writes every variation as .wav plus manifest.json and quits.

const Tuning := preload("res://audio/sfx_tuning.gd")
const Synth := preload("res://audio/sfx_synth.gd")

signal library_ready(generation_ms: float)

## Parent for positional players. Set it when the game world lives in a SubViewport.
var world: Node = null:
	set(value):
		world = value
		_reparent_2d()

var generation_ms := 0.0
var generation_cpu_ms := 0.0

var _banks: Dictionary = {} # StringName key -> Array (tiers) of Array[AudioStreamWAV]
var _configs: Dictionary = {}
var _jobs: Array = []
var _results: Array = []
var _job_us: PackedInt64Array = PackedInt64Array()
var _mutex := Mutex.new()

var _flat: Array[AudioStreamPlayer] = []
var _pos: Array[AudioStreamPlayer2D] = []
var _voice_id: Dictionary = {} # player -> id
var _voice_start: Dictionary = {} # player -> ticks
var _last_variation: Dictionary = {}
var _loops: Dictionary = {} # handle -> player
var _loop_free: Array[Node] = []
var _next_handle := 1
var _rng := RandomNumberGenerator.new()
var _warned: Dictionary = {}
var _underwater_mix := 0.0
var _underwater_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_setup_buses()
	_generate()
	_build_pools()
	var args := OS.get_cmdline_user_args()
	var i := args.find("--sfx-dump")
	if i >= 0:
		var dir := args[i + 1] if i + 1 < args.size() else ProjectSettings.globalize_path("res://captures/sfx")
		_dump(dir)
		get_tree().quit.call_deferred()


func _exit_tree() -> void:
	var players: Array = []
	players.append_array(_flat)
	players.append_array(_pos)
	players.append_array(_loops.values())
	players.append_array(_loop_free)
	for p: Node in players:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	_loops.clear()
	_banks.clear()
	Synth.release_tables()


# ---------------------------------------------------------------- public API

func play(id: StringName, at: Vector2 = Vector2.INF, strength: float = 1.0, surface: StringName = &"") -> void:
	var cfg := _config(id)
	if cfg.is_empty() or cfg.loop:
		_warn_once(id, "Sfx.play: unknown or loop-only id '%s'" % id)
		return
	var tiers: Array = _bank(id, surface, cfg)
	if tiers.is_empty():
		return
	var s := maxf(strength, 0.0)
	var tier := clampi(roundi(minf(s, 1.0) * (tiers.size() - 1)), 0, tiers.size() - 1)
	var variants: Array = tiers[tier]
	var key := "%s|%s|%d" % [id, surface, tier]
	var pick := _rng.randi_range(0, variants.size() - 1)
	if variants.size() > 1 and pick == int(_last_variation.get(key, -1)):
		pick = (pick + 1 + _rng.randi_range(0, variants.size() - 2)) % variants.size()
	_last_variation[key] = pick

	var vol := float(cfg.volume_db) + _strength_db(s, float(cfg.strength_db)) \
		+ _rng.randf_range(-float(cfg.volume_jitter_db), float(cfg.volume_jitter_db)) * 0.5
	var jitter := float(cfg.pitch_jitter)
	var pitch := (1.0 + _rng.randf_range(-jitter, jitter)) * (1.0 + float(cfg.strength_pitch) * (minf(s, 1.5) - 0.5))

	var positional := at != Vector2.INF
	if not cfg.dry:
		pitch *= _pitch_mul()
	var player := _acquire(id, int(cfg.max_voices), positional)
	player.bus = _bus_for(cfg)
	player.stream = variants[pick]
	player.volume_db = vol
	player.pitch_scale = maxf(pitch, 0.05)
	if positional:
		(player as AudioStreamPlayer2D).global_position = at
	player.play()


func start_loop(id: StringName, at: Vector2 = Vector2.INF) -> int:
	var cfg := _config(id)
	if cfg.is_empty() or not cfg.loop:
		_warn_once(id, "Sfx.start_loop: '%s' is not a loop id" % id)
		return 0
	var tiers: Array = _bank(id, &"", cfg)
	if tiers.is_empty():
		return 0
	var positional := at != Vector2.INF
	var player := _loop_player(positional)
	player.stream = tiers[0][0]
	player.bus = _bus_for(cfg)
	player.set_meta(&"id", id)
	player.set_meta(&"jitter", 1.0 + _rng.randf_range(-float(cfg.pitch_jitter), float(cfg.pitch_jitter)))
	if positional:
		player.global_position = at
	_apply_loop_strength(player, cfg, 1.0)
	player.volume_db = -60.0
	player.play(_rng.randf_range(0.0, (player.stream as AudioStreamWAV).get_length() * 0.9))
	var tw := player.create_tween()
	tw.tween_method(_set_gain.bind(player), 0.001, 1.0, Tuning.LOOP_FADE_IN)
	player.set_meta(&"tween", tw)
	var handle := _next_handle
	_next_handle += 1
	_loops[handle] = player
	return handle


func stop_loop(handle: int, fade: float = 0.08) -> void:
	if not _loops.has(handle):
		return
	var player: Node = _loops[handle]
	_loops.erase(handle)
	var old: Tween = player.get_meta(&"tween", null)
	if old and old.is_valid():
		old.kill()
	if fade <= 0.0:
		_release_loop(player)
		return
	var from := db_to_linear(player.volume_db - float(player.get_meta(&"base_db", 0.0)))
	var tw := player.create_tween()
	tw.tween_method(_set_gain.bind(player), clampf(from, 0.001, 1.0), 0.001, fade)
	tw.tween_callback(_release_loop.bind(player))


## Live strength (0..1) of a running loop: scales volume and brightness (pitch), e.g. slide speed.
func set_loop_strength(handle: int, strength: float) -> void:
	var player: Node = _loops.get(handle)
	if player == null:
		return
	_apply_loop_strength(player, _config(player.get_meta(&"id")), strength)
	var tw: Tween = player.get_meta(&"tween", null)
	if tw == null or not tw.is_valid() or not tw.is_running():
		player.volume_db = float(player.get_meta(&"base_db"))


## Freezes (true) or resumes (false) every running loop, dry ones included; one-shots keep playing.
func pause_loops(on: bool) -> void:
	for handle in _loops:
		_loops[handle].stream_paused = on


## Muffles every non-dry sound (low-pass on the SFX bus plus a slight pitch drop) while submerged.
func set_underwater(on: bool, fade: float = 0.25) -> void:
	if _underwater_tween and _underwater_tween.is_valid():
		_underwater_tween.kill()
	var target := 1.0 if on else 0.0
	if fade <= 0.0:
		_set_underwater_mix(target)
		return
	_underwater_tween = create_tween()
	_underwater_tween.tween_method(_set_underwater_mix, _underwater_mix, target, fade)


func is_underwater() -> bool:
	return _underwater_mix > 0.5


## Moves a running loop (e.g. the skid following the player).
func set_loop_position(handle: int, at: Vector2) -> void:
	var player: Node = _loops.get(handle)
	if player is AudioStreamPlayer2D:
		player.global_position = at


func is_loop(id: StringName) -> bool:
	return bool(_config(id).get("loop", false))


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in Tuning.SOUNDS:
		out.append(id)
	return out


func surfaces(id: StringName) -> Array:
	return _config(id).get("surfaces", [])


# ---------------------------------------------------------------- generation

func _generate() -> void:
	Synth.prepare_tables()
	_jobs.clear()
	for id: StringName in Tuning.SOUNDS:
		var cfg := _config(id)
		var surf: Array = cfg.surfaces if not cfg.surfaces.is_empty() else [&""]
		for surface: StringName in surf:
			var key := _bank_key(id, surface)
			var tiers: Array = []
			for t in int(cfg.tiers):
				var variants: Array = []
				variants.resize(int(cfg.variations))
				tiers.append(variants)
				for v in int(cfg.variations):
					_jobs.append([key, id, surface, t, v, _cost(cfg)])
			_banks[key] = tiers
	# Longest renders first so the thread pool does not end on a straggler.
	_jobs.sort_custom(func(a: Array, b: Array) -> bool: return a[5] > b[5])
	_results.resize(_jobs.size())
	_job_us.resize(_jobs.size())
	var t0 := Time.get_ticks_usec()
	var group := WorkerThreadPool.add_group_task(_run_job, _jobs.size(), -1, true, "sfx synth")
	WorkerThreadPool.wait_for_group_task_completion(group)
	generation_ms = (Time.get_ticks_usec() - t0) / 1000.0
	var cpu := 0
	for i in _jobs.size():
		var job: Array = _jobs[i]
		_banks[job[0]][job[3]][job[4]] = _results[i]
		cpu += _job_us[i]
	generation_cpu_ms = cpu / 1000.0
	_results.clear()
	print("Sfx: %d streams in %.1f ms (%.1f ms CPU across threads)" % [_jobs.size(), generation_ms, generation_cpu_ms])
	library_ready.emit(generation_ms)


func _cost(cfg: Dictionary) -> float:
	var syn: Dictionary = cfg.synth
	var cost := float(syn.get("dur", syn.get("dur_heavy", 0.3)))
	return cost * (3.0 if cfg.loop or cfg.dry else 1.0)


func _run_job(i: int) -> void:
	var t0 := Time.get_ticks_usec()
	var job: Array = _jobs[i]
	var id: StringName = job[1]
	var cfg: Dictionary = Tuning.config(id)
	var synth := Synth.new()
	synth.rng.seed = Synth.job_seed(job[0], job[3], job[4])
	var tiers := int(cfg.tiers)
	var weight := float(job[3]) / (tiers - 1) if tiers > 1 else 1.0
	var buf := synth.render(id, cfg.synth, weight, job[2])
	if not cfg.loop:
		buf = synth.finish(buf)
	var stream := synth.to_stream(buf, cfg.loop)
	_mutex.lock()
	_results[i] = stream
	_job_us[i] = Time.get_ticks_usec() - t0
	_mutex.unlock()


func _dump(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var manifest := {sample_rate = Tuning.SAMPLE_RATE, generation_ms = generation_ms,
		generation_cpu_ms = generation_cpu_ms, streams = []}
	for key: StringName in _banks:
		var tiers: Array = _banks[key]
		for t in tiers.size():
			for v in tiers[t].size():
				var s: AudioStreamWAV = tiers[t][v]
				var file := "%s_t%d_v%d.wav" % [String(key).replace("@", "-"), t, v]
				s.save_to_wav(dir.path_join(file))
				manifest.streams.append({key = String(key), tier = t, variation = v, file = file,
					loop = s.loop_mode != AudioStreamWAV.LOOP_DISABLED})
	var f := FileAccess.open(dir.path_join("manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "\t"))
	f.close()
	print("Sfx: dumped %d files to %s" % [manifest.streams.size(), dir])


# ---------------------------------------------------------------- playback internals

func _config(id: StringName) -> Dictionary:
	if not _configs.has(id):
		_configs[id] = Tuning.config(id)
	return _configs[id]


func _bank_key(id: StringName, surface: StringName) -> StringName:
	return id if surface == &"" else StringName("%s@%s" % [id, surface])


func _bank(id: StringName, surface: StringName, cfg: Dictionary) -> Array:
	if not cfg.surfaces.is_empty():
		var s := surface if cfg.surfaces.has(surface) else StringName(cfg.default_surface)
		return _banks.get(_bank_key(id, s), [])
	return _banks.get(id, [])


func _strength_db(s: float, range_db: float) -> float:
	if s <= 1.0:
		return -range_db * (1.0 - s) * (1.0 - s * 0.35)
	return minf((s - 1.0) * 6.0, 3.0)


func _setup_buses() -> void:
	var idx := AudioServer.get_bus_index(Tuning.BUS_NAME)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, Tuning.BUS_NAME)
		AudioServer.set_bus_send(idx, &"Master")
		var comp := AudioEffectCompressor.new()
		comp.threshold = Tuning.COMPRESSOR.threshold
		comp.ratio = Tuning.COMPRESSOR.ratio
		comp.attack_us = Tuning.COMPRESSOR.attack_us
		comp.release_ms = Tuning.COMPRESSOR.release_ms
		comp.gain = Tuning.COMPRESSOR.gain
		AudioServer.add_bus_effect(idx, comp)
	AudioServer.set_bus_volume_db(idx, Tuning.BUS_VOLUME_DB)
	if _find_effect(idx, "AudioEffectLowPassFilter") < 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = Tuning.UNDERWATER.open_hz
		lp.resonance = Tuning.UNDERWATER.resonance
		AudioServer.add_bus_effect(idx, lp, 0)
		AudioServer.set_bus_effect_enabled(idx, 0, false)
	if AudioServer.get_bus_index(Tuning.DRY_BUS_NAME) < 0:
		AudioServer.add_bus()
		var dry := AudioServer.bus_count - 1
		AudioServer.set_bus_name(dry, Tuning.DRY_BUS_NAME)
		AudioServer.set_bus_send(dry, &"Master")
	var master := AudioServer.get_bus_index(&"Master")
	for e in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, e) is AudioEffectHardLimiter:
			return
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = Tuning.MASTER_LIMITER.ceiling_db
	lim.pre_gain_db = Tuning.MASTER_LIMITER.pre_gain_db
	lim.release = Tuning.MASTER_LIMITER.release
	AudioServer.add_bus_effect(master, lim)


func _build_pools() -> void:
	for i in Tuning.POOL_FLAT:
		var p := AudioStreamPlayer.new()
		p.bus = Tuning.BUS_NAME
		add_child(p)
		_flat.append(p)
	for i in Tuning.POOL_2D:
		_pos.append(_make_2d())


func _make_2d() -> AudioStreamPlayer2D:
	var p := AudioStreamPlayer2D.new()
	p.bus = Tuning.BUS_NAME
	p.max_distance = Tuning.MAX_DISTANCE_2D
	p.attenuation = Tuning.ATTENUATION_2D
	p.panning_strength = Tuning.PANNING_2D
	(world if is_instance_valid(world) else self).add_child(p)
	return p


func _reparent_2d() -> void:
	var parent: Node = world if is_instance_valid(world) else self
	for p in _pos:
		if p.get_parent() != parent:
			p.reparent(parent, false)
	for handle in _loops:
		var p: Node = _loops[handle]
		if p is AudioStreamPlayer2D and p.get_parent() != parent:
			p.reparent(parent, false)


func _acquire(id: StringName, max_voices: int, positional: bool) -> Node:
	if positional and not _pos.all(is_instance_valid):
		_pos.assign(_pos.filter(is_instance_valid))
		while _pos.size() < Tuning.POOL_2D:
			_pos.append(_make_2d())
	var pool: Array = _pos if positional else _flat
	var same_count := 0
	var oldest_same: Node = null
	var oldest_any: Node = null
	var free: Node = null
	for p: Node in pool:
		if not p.playing:
			if free == null:
				free = p
			continue
		var start: int = _voice_start.get(p, 0)
		if oldest_any == null or start < int(_voice_start.get(oldest_any, 0)):
			oldest_any = p
		if _voice_id.get(p) == id:
			same_count += 1
			if oldest_same == null or start < int(_voice_start.get(oldest_same, 0)):
				oldest_same = p
	var chosen: Node = free
	if same_count >= max_voices and oldest_same:
		chosen = oldest_same
	elif chosen == null:
		chosen = oldest_any
	chosen.stop()
	_voice_id[chosen] = id
	_voice_start[chosen] = Time.get_ticks_usec()
	return chosen


func _loop_player(positional: bool) -> Node:
	for i in _loop_free.size():
		var p := _loop_free[i]
		if (p is AudioStreamPlayer2D) == positional:
			_loop_free.remove_at(i)
			return p
	if positional:
		return _make_2d()
	var flat := AudioStreamPlayer.new()
	flat.bus = Tuning.BUS_NAME
	add_child(flat)
	return flat


func _apply_loop_strength(player: Node, cfg: Dictionary, strength: float) -> void:
	var s := clampf(strength, 0.0, 1.0)
	player.set_meta(&"base_db", float(cfg.volume_db) + _strength_db(s, float(cfg.strength_db)))
	player.set_meta(&"pitch", float(player.get_meta(&"jitter", 1.0)) \
		* lerpf(float(cfg.loop_pitch_low), float(cfg.loop_pitch_high), s))
	player.pitch_scale = float(player.get_meta(&"pitch")) * (1.0 if cfg.dry else _pitch_mul())


func _bus_for(cfg: Dictionary) -> StringName:
	return Tuning.DRY_BUS_NAME if cfg.dry else Tuning.BUS_NAME


func _pitch_mul() -> float:
	return lerpf(1.0, float(Tuning.UNDERWATER.pitch), _underwater_mix)


func _set_underwater_mix(m: float) -> void:
	_underwater_mix = m
	var idx := AudioServer.get_bus_index(Tuning.BUS_NAME)
	var e := _find_effect(idx, "AudioEffectLowPassFilter")
	if e >= 0:
		var lp: AudioEffectLowPassFilter = AudioServer.get_bus_effect(idx, e)
		lp.cutoff_hz = float(Tuning.UNDERWATER.open_hz) * pow(float(Tuning.UNDERWATER.cutoff_hz) / float(Tuning.UNDERWATER.open_hz), m)
		AudioServer.set_bus_effect_enabled(idx, e, m > 0.001)
	for handle in _loops:
		var p: Node = _loops[handle]
		if not _config(p.get_meta(&"id")).dry:
			p.pitch_scale = float(p.get_meta(&"pitch", 1.0)) * _pitch_mul()


func _find_effect(bus: int, type: String) -> int:
	if bus < 0:
		return -1
	for e in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, e).is_class(type):
			return e
	return -1


func _release_loop(player: Node) -> void:
	player.stream_paused = false
	player.stop()
	_loop_free.append(player)


func _set_gain(g: float, player: Node) -> void:
	player.volume_db = float(player.get_meta(&"base_db", 0.0)) + linear_to_db(maxf(g, 0.001))


func _warn_once(id: StringName, msg: String) -> void:
	if not _warned.has(id):
		_warned[id] = true
		push_warning(msg)
