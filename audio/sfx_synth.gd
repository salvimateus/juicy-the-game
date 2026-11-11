extends RefCounted

# Procedural SFX synthesis: noise, filters, oscillators, envelopes and one recipe per id.
# One instance per job (own RNG); the noise tables are shared and read-only, so jobs can run on threads.
# Time curves are Arrays of [t_seconds, value, ...], interpolated exponentially.

const Tuning := preload("res://audio/sfx_tuning.gd")

enum { WHITE, PINK, BROWN }
enum { LP, BP, HP }
enum { SINE, TRI, SQUARE, SAW }

const NOISE_LEN := 131072

static var _tables: Array = []

var sr: float = Tuning.SAMPLE_RATE
var rng := RandomNumberGenerator.new()


static func prepare_tables() -> void:
	if not _tables.is_empty():
		return
	var r := RandomNumberGenerator.new()
	r.seed = Tuning.BASE_SEED
	var white := PackedFloat32Array()
	var pink := PackedFloat32Array()
	var brown := PackedFloat32Array()
	white.resize(NOISE_LEN)
	pink.resize(NOISE_LEN)
	brown.resize(NOISE_LEN)
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var br := 0.0
	var pk_pink := 0.0
	var pk_brown := 0.0
	for i in NOISE_LEN:
		var w := r.randf() * 2.0 - 1.0
		white[i] = w
		b0 = 0.99765 * b0 + w * 0.0990460
		b1 = 0.96300 * b1 + w * 0.2965164
		b2 = 0.57000 * b2 + w * 1.0526913
		var pv := b0 + b1 + b2 + w * 0.1848
		pink[i] = pv
		pk_pink = maxf(pk_pink, absf(pv))
		br = (br + w * 0.02) * 0.995
		brown[i] = br
		pk_brown = maxf(pk_brown, absf(br))
	for i in NOISE_LEN:
		pink[i] /= pk_pink
		brown[i] /= pk_brown
	_tables = [white, pink, brown]


static func release_tables() -> void:
	_tables = []


static func job_seed(key: String, tier: int, variation: int) -> int:
	return absi(hash("%s|%d|%d" % [key, tier, variation])) + Tuning.BASE_SEED


# Returns the raw float buffer for one variation (before finishing).
func render(id: StringName, p: Dictionary, weight: float, surface: StringName) -> PackedFloat32Array:
	var method := StringName("_r_" + String(id))
	if not has_method(method):
		push_warning("SfxSynth: no recipe %s for id '%s'" % [method, id])
		return PackedFloat32Array()
	return call(method, p, weight, surface)


# ---------------------------------------------------------------- building blocks

func rr(a: float, b: float) -> float:
	return rng.randf_range(a, b)


func make(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(1, int(dur * sr)))
	return out


func noise(dur: float, color: int) -> PackedFloat32Array:
	var n := maxi(1, int(dur * sr))
	var table: PackedFloat32Array = _tables[color]
	var off := rng.randi_range(0, NOISE_LEN - n - 1)
	return table.slice(off, off + n)


func _curve(pts: Array, t: float) -> float:
	if t <= pts[0]:
		return pts[1]
	var j := 2
	var size := pts.size()
	while j < size:
		var t1: float = pts[j]
		if t <= t1:
			var t0: float = pts[j - 2]
			var v0: float = pts[j - 1]
			var v1: float = pts[j + 1]
			var u := (t - t0) / maxf(t1 - t0, 0.000001)
			return v0 * pow(v1 / v0, u)
		j += 2
	return pts[size - 1]


# Zavalishin TPT state-variable filter, stable up to Nyquist. Band output is peak-normalized.
func svf(buf: PackedFloat32Array, mode: int, pts: Array, q: float = 0.707) -> PackedFloat32Array:
	var n := buf.size()
	var k := 1.0 / q
	var ic1 := 0.0
	var ic2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var a3 := 0.0
	var nyq := sr * 0.45
	var inv_sr := 1.0 / sr
	for i in n:
		if i & 15 == 0:
			var fc := minf(_curve(pts, i * inv_sr), nyq)
			var g := tan(PI * fc * inv_sr)
			a1 = 1.0 / (1.0 + g * (g + k))
			a2 = g * a1
			a3 = g * a2
		var v0 := buf[i]
		var v3 := v0 - ic2
		var v1 := a1 * ic1 + a2 * v3
		var v2 := ic2 + a2 * ic1 + a3 * v3
		ic1 = 2.0 * v1 - ic1
		ic2 = 2.0 * v2 - ic2
		if mode == LP:
			buf[i] = v2
		elif mode == BP:
			buf[i] = v1 * k
		else:
			buf[i] = v0 - k * v1 - v2
	return buf


func osc(dur: float, shape: int, pts: Array, phase: float = 0.0) -> PackedFloat32Array:
	var out := make(dur)
	var inv_sr := 1.0 / sr
	var inc := 0.0
	var ph := phase
	for i in out.size():
		if i & 15 == 0:
			inc = _curve(pts, i * inv_sr) * inv_sr
		var v: float
		if shape == SINE:
			v = sin(TAU * ph)
		elif shape == TRI:
			v = 4.0 * absf(ph - 0.5) - 1.0
		elif shape == SQUARE:
			v = 1.0 if ph < 0.5 else -1.0
		else:
			v = 2.0 * ph - 1.0
		out[i] = v
		ph += inc
		if ph >= 1.0:
			ph -= 1.0
	return out


# Linear attack then exponential decay (tau seconds), optionally delayed.
func perc(buf: PackedFloat32Array, attack: float, tau: float, delay: float = 0.0) -> PackedFloat32Array:
	var n := buf.size()
	var d_n := int(delay * sr)
	var a_n := maxi(1, int(attack * sr))
	var r := exp(-1.0 / (maxf(tau, 0.0005) * sr))
	var g := 1.0
	for i in n:
		if i < d_n:
			buf[i] = 0.0
		elif i < d_n + a_n:
			buf[i] *= float(i - d_n) / a_n
		else:
			buf[i] *= g
			g *= r
	return buf


# Attack / hold / release with a power curve; zero after the release.
func ar(buf: PackedFloat32Array, attack: float, hold: float, release: float, curve: float = 1.0, delay: float = 0.0) -> PackedFloat32Array:
	var n := buf.size()
	var d_n := int(delay * sr)
	var a_n := maxi(1, int(attack * sr))
	var h_n := int(hold * sr)
	var r_n := maxi(1, int(release * sr))
	for i in n:
		var j := i - d_n
		var g: float
		if j < 0:
			g = 0.0
		elif j < a_n:
			g = pow(float(j) / a_n, curve)
		elif j < a_n + h_n:
			g = 1.0
		elif j < a_n + h_n + r_n:
			g = pow(1.0 - float(j - a_n - h_n) / r_n, curve)
		else:
			g = 0.0
		buf[i] *= g
	return buf


func am(buf: PackedFloat32Array, hz: float, depth: float) -> PackedFloat32Array:
	var w := TAU * hz / sr
	for i in buf.size():
		buf[i] *= 1.0 - depth * 0.5 * (1.0 - cos(w * i))
	return buf


# Random slow amplitude movement from brown noise smoothed to `hz`.
func wobble(buf: PackedFloat32Array, hz: float, depth: float) -> PackedFloat32Array:
	var m := svf(noise(buf.size() / sr + 0.01, BROWN), LP, [0.0, hz], 0.7)
	normalize(m, 1.0)
	for i in buf.size():
		buf[i] *= 1.0 - depth + depth * absf(m[i])
	return buf


# Mixes src scaled so its peak equals `gain`: layer gains are peak ratios.
func add(dst: PackedFloat32Array, src: PackedFloat32Array, gain: float = 1.0, at: float = 0.0) -> void:
	var pk := peak(src)
	if pk <= 0.0:
		return
	var g := gain / pk
	var off := int(at * sr)
	var n := mini(src.size(), dst.size() - off)
	for i in n:
		dst[off + i] += src[i] * g


func peak(buf: PackedFloat32Array) -> float:
	var pk := 0.0
	for v in buf:
		pk = maxf(pk, absf(v))
	return pk


func normalize(buf: PackedFloat32Array, target: float) -> PackedFloat32Array:
	var pk := peak(buf)
	if pk > 0.0:
		var g := target / pk
		for i in buf.size():
			buf[i] *= g
	return buf


func drive(buf: PackedFloat32Array, amount: float) -> PackedFloat32Array:
	normalize(buf, 1.0)
	var norm := 1.0 / tanh(amount)
	for i in buf.size():
		buf[i] = tanh(buf[i] * amount) * norm
	return buf


func thump(dur: float, f0: float, f1: float, glide: float, tau: float, shape: int = SINE) -> PackedFloat32Array:
	return perc(osc(dur, shape, [0.0, f0, glide, f1], 0.25 if shape == SINE else 0.0), 0.0008, tau)


func click(dur: float, hp_hz: float) -> PackedFloat32Array:
	return perc(svf(noise(dur, WHITE), HP, [0.0, hp_hz], 0.7), 0.0, dur * 0.35)


# Damped resonant ping added into dst (two-pole resonator impulse response).
func ping(dst: PackedFloat32Array, at: float, freq: float, tau: float, amp: float) -> void:
	var start := int(at * sr)
	var len := mini(int(tau * 7.0 * sr), dst.size() - start)
	if len <= 0:
		return
	var w := TAU * minf(freq, sr * 0.45) / sr
	var r := exp(-1.0 / (tau * sr))
	var b1 := 2.0 * r * cos(w)
	var b2 := -r * r
	var s1 := 0.0
	var s2 := 0.0
	var x := amp * sin(w)
	for i in len:
		var s := x + b1 * s1 + b2 * s2
		x = 0.0
		dst[start + i] += s
		s2 = s1
		s1 = s


func tick(dst: PackedFloat32Array, at: float, freq: float, tau: float, amp: float) -> void:
	ping(dst, at, freq, tau, amp)
	var start := int(at * sr)
	for i in mini(4, dst.size() - start):
		dst[start + i] += rr(-1.0, 1.0) * amp * 0.6 * (1.0 - i * 0.25)


func partials(dst: PackedFloat32Array, at: float, base: float, ratios: Array, amps: Array, taus: Array, gain: float) -> void:
	for k in ratios.size():
		ping(dst, at, base * float(ratios[k]) * rr(0.99, 1.01), float(taus[k]), float(amps[k]) * gain)


func crackle(dst: PackedFloat32Array, t0: float, t1: float, count: int, f_lo: float, f_hi: float, tau: float, amp: float) -> void:
	for k in count:
		tick(dst, rr(t0, t1), rr(f_lo, f_hi), tau * rr(0.6, 1.4), amp * rr(0.4, 1.0))


# Water-drop chirp: short sine with a fast upward glide.
func drop(dst: PackedFloat32Array, at: float, f0: float, f1: float, tau: float, amp: float) -> void:
	add(dst, perc(osc(tau * 6.0, SINE, [0.0, f0, tau * 1.5, f1]), 0.0005, tau), amp, at)


# Stick-slip impulse train: the raw material of creaks.
func impulses(dur: float, rate_pts: Array, jitter: float) -> PackedFloat32Array:
	var out := make(dur)
	var t := 0.0
	while t < dur:
		var i := int(t * sr)
		if i < out.size():
			var a := rr(0.4, 1.0)
			out[i] += a
			if i + 1 < out.size():
				out[i + 1] -= a * 0.5
		t += (1.0 / _curve(rate_pts, t)) * (1.0 + rr(-jitter, jitter))
	return out


# Karplus-Strong plucked string.
func pluck(dur: float, freq: float, damping: float) -> PackedFloat32Array:
	var out := make(dur)
	var period := maxi(2, int(sr / freq))
	var line := svf(noise(period / sr + 0.001, WHITE), LP, [0.0, 4000.0], 0.7)
	line.resize(period)
	var idx := 0
	for i in out.size():
		var nxt := (idx + 1) % period
		var v := line[idx]
		out[i] = v
		line[idx] = damping * 0.5 * (v + line[nxt])
		idx = nxt
	return out


func whoosh(dur: float, lo: float, hi: float, q: float, color: int, peak_at: float) -> PackedFloat32Array:
	var n := svf(noise(dur, color), BP, [0.0, lo, dur * peak_at, hi, dur, lo * 1.3], q)
	return ar(n, dur * peak_at, 0.0, dur * (1.0 - peak_at), 1.8)


# ---------------------------------------------------------------- finishing

func finish(buf: PackedFloat32Array) -> PackedFloat32Array:
	_dc_block(buf)
	var mean := 0.0
	for v in buf:
		mean += v
	mean /= buf.size()
	for i in buf.size():
		buf[i] -= mean
	normalize(buf, 1.0)
	var thresh := db_to_linear(Tuning.TRIM_DB)
	var last := buf.size() - 1
	while last > 0 and absf(buf[last]) < thresh:
		last -= 1
	var fade_out := int(Tuning.FADE_OUT_MS * 0.001 * sr)
	buf.resize(mini(buf.size(), last + fade_out + 1))
	var fade_in := maxi(1, int(Tuning.FADE_IN_MS * 0.001 * sr))
	var n := buf.size()
	for i in mini(fade_in, n):
		buf[i] *= float(i) / fade_in
	for i in mini(fade_out, n):
		buf[n - 1 - i] *= float(i) / fade_out
	return normalize(buf, Tuning.TARGET_PEAK)


# The buffer carries `xf` seconds of tail past the loop point; that tail is crossfaded into the head.
func finish_loop(buf: PackedFloat32Array, xf: float) -> PackedFloat32Array:
	var mean := 0.0
	for v in buf:
		mean += v
	mean /= buf.size()
	var x_n := int(xf * sr)
	var n := buf.size() - x_n
	var out := buf.slice(0, n)
	for i in x_n:
		var u := float(i) / x_n
		out[i] = buf[i] * sin(u * PI * 0.5) + buf[n + i] * cos(u * PI * 0.5)
	for i in n:
		out[i] -= mean
	return normalize(out, Tuning.TARGET_PEAK)


func _dc_block(buf: PackedFloat32Array) -> void:
	var r := 1.0 - TAU * 20.0 / sr
	var x1 := 0.0
	var y1 := 0.0
	for i in buf.size():
		var x := buf[i]
		var y := x - x1 + r * y1
		x1 = x
		y1 = y
		buf[i] = y


func to_stream(buf: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = int(sr)
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = buf.size()
	return s


# ---------------------------------------------------------------- recipes: movement

func _r_footstep(p: Dictionary, w: float, surface: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.16)) * lerpf(1.0, 1.25, w)
	var th := float(p.get("thump_hz", 110.0)) * rr(0.9, 1.1)
	var out := make(dur)
	match surface:
		&"grass":
			var n := ar(svf(noise(dur, PINK), BP, [0.0, rr(2400.0, 3400.0), dur, rr(1400.0, 2000.0)], 1.1), 0.012, 0.0, dur * 0.7, 2.0)
			add(out, n, 1.0)
			add(out, perc(svf(noise(0.08, WHITE), HP, [0.0, 4500.0]), 0.004, 0.02), 0.4, rr(0.02, 0.05))
			add(out, thump(0.09, th * 0.8, th * 0.55, 0.05, 0.025), 0.3 + 0.4 * w)
		&"stone":
			add(out, click(0.004, 5000.0), 0.6)
			add(out, perc(svf(noise(dur, WHITE), BP, [0.0, rr(1300.0, 1900.0)], 1.5), 0.0008, 0.022), 0.9)
			add(out, thump(0.09, th * 1.25, th * 0.7, 0.025, 0.018, TRI), 0.35 + 0.35 * w)
			crackle(out, 0.004, 0.05, 2, 3000.0, 6000.0, 0.004, 0.25)
		&"wood":
			add(out, click(0.003, 3500.0), 0.5)
			add(out, thump(dur, th * 1.8, th * 1.3, 0.02, 0.03, TRI), 0.7)
			add(out, perc(svf(noise(dur, PINK), BP, [0.0, rr(450.0, 700.0)], 6.0), 0.0008, 0.045), 0.9)
			ping(out, 0.0, rr(900.0, 1300.0), 0.025, 0.25)
		&"metal":
			# Hollow plate: a dull clunk with a short inharmonic ring.
			add(out, click(0.003, 4500.0), 0.5)
			add(out, thump(dur, th * 1.6, th * 1.1, 0.02, 0.03, TRI), 0.6)
			partials(out, 0.002, rr(700.0, 900.0), [1.0, 2.31, 3.87], [1.0, 0.55, 0.3], [0.07, 0.045, 0.03], 0.3 + 0.15 * w)
			add(out, perc(svf(noise(dur, WHITE), BP, [0.0, rr(2600.0, 3400.0)], 2.0), 0.0006, 0.015), 0.4)
		_:
			add(out, perc(svf(noise(dur, BROWN), LP, [0.0, rr(900.0, 1300.0), dur, 300.0], 0.8), 0.003, 0.05), 1.0)
			add(out, thump(0.1, th, th * 0.6, 0.04, 0.025), 0.45 + 0.4 * w)
			crackle(out, 0.01, 0.08, 3, 1500.0, 3500.0, 0.006, 0.2)
	return out


func _r_jump(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.22))
	var out := make(dur)
	add(out, perc(svf(noise(0.08, BROWN), LP, [0.0, 1500.0]), 0.002, 0.025), 0.7)
	add(out, ar(svf(noise(dur, PINK), BP, [0.0, 600.0, dur * 0.6, rr(1700.0, 2200.0), dur, 1200.0], 1.4), 0.04, 0.0, dur - 0.04, 1.5), 0.8)
	add(out, thump(0.06, 150.0, 95.0, 0.03, 0.018), 0.4)
	return out


func _r_land(p: Dictionary, w: float, surface: StringName) -> PackedFloat32Array:
	var dur := lerpf(float(p.get("dur_light", 0.18)), float(p.get("dur_heavy", 0.55)), w)
	var th := float(p.get("thump_hz", 105.0)) * rr(0.92, 1.08)
	var out := make(dur)
	add(out, thump(dur, th * 1.3, th * lerpf(0.6, 0.38, w), lerpf(0.03, 0.07, w), lerpf(0.03, 0.09, w)), 1.0)
	add(out, perc(svf(noise(dur, BROWN), LP, [0.0, lerpf(1500.0, 2600.0, w), dur, 250.0], 0.8), 0.001, lerpf(0.03, 0.11, w)), lerpf(0.6, 0.9, w))
	add(out, _r_footstep({}, 1.0, surface), 0.55)
	if w > 0.3:
		crackle(out, 0.02, 0.05 + 0.25 * w, int(3 + 10 * w), 1200.0, 4000.0, 0.008, 0.3 * w)
	if w > 0.6:
		drive(out, 1.5 + 2.0 * w)
	return out


func _r_skid(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var xf := 0.12
	var dur := float(p.get("dur", 1.2)) + xf
	var band := float(p.get("band_hz", 1700.0))
	var out := make(dur)
	add(out, wobble(svf(noise(dur, WHITE), BP, [0.0, band], 1.0), 9.0, 0.6), 0.8)
	add(out, wobble(svf(noise(dur, BROWN), LP, [0.0, 420.0]), 4.0, 0.4), 0.7)
	add(out, svf(noise(dur, PINK), HP, [0.0, 3500.0]), 0.18)
	crackle(out, 0.0, dur - 0.02, 34, 2000.0, 5000.0, 0.003, 0.22)
	return finish_loop(out, xf)


func _r_wall_slide(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var xf := 0.12
	var dur := float(p.get("dur", 1.4)) + xf
	var band := float(p.get("band_hz", 2300.0))
	var out := make(dur)
	add(out, wobble(svf(noise(dur, WHITE), BP, [0.0, band], 0.8), 14.0, 0.7), 0.8)
	add(out, wobble(svf(noise(dur, PINK), BP, [0.0, 900.0], 1.2), 6.0, 0.5), 0.6)
	add(out, wobble(svf(noise(dur, BROWN), LP, [0.0, 300.0]), 3.0, 0.4), 0.45)
	add(out, svf(impulses(dur, [0.0, rr(60.0, 90.0)], 0.5), BP, [0.0, 1400.0], 3.0), 0.3)
	crackle(out, 0.0, dur - 0.02, int(p.get("pebbles", 55)), 1800.0, 5500.0, 0.004, 0.3)
	return finish_loop(out, xf)


func _r_roll(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.42))
	var out := make(dur)
	var gains := [0.9, 0.7, 0.55]
	for k in 3:
		add(out, thump(0.12, rr(110.0, 135.0), 70.0, 0.04, 0.035), gains[k], k * dur * 0.32 + rr(0.0, 0.03))
	var cloth := svf(noise(dur, PINK), BP, [0.0, 900.0, dur * 0.5, rr(1900.0, 2500.0), dur, 1200.0], 1.5)
	add(out, wobble(ar(cloth, 0.05, 0.1, dur - 0.16, 1.5), 22.0, 0.6), 0.7)
	crackle(out, 0.02, dur * 0.8, 4, 1500.0, 3200.0, 0.005, 0.15)
	return out


func _r_ledge_grab(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.36))
	var out := make(dur)
	add(out, perc(svf(noise(0.06, WHITE), BP, [0.0, rr(1900.0, 2600.0)], 0.9), 0.0005, 0.018), 1.0)
	add(out, perc(svf(noise(0.08, PINK), LP, [0.0, 1200.0]), 0.0008, 0.03), 0.6)
	add(out, thump(0.06, 230.0, 140.0, 0.02, 0.022), 0.6)
	var t := 0.04
	for k in int(p.get("pebbles", 5)):
		t += rr(0.02, 0.07)
		if t > dur - 0.03:
			break
		tick(out, t, rr(2500.0, 5500.0), rr(0.004, 0.008), 0.32 * pow(0.8, k))
	return out


func _r_climb(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.28))
	var out := make(dur)
	add(out, ar(svf(noise(dur, PINK), BP, [0.0, rr(900.0, 1300.0), dur, rr(1800.0, 2600.0)], 1.3), 0.06, 0.04, dur - 0.1, 1.6), 0.9)
	add(out, perc(svf(noise(0.06, PINK), LP, [0.0, 1500.0]), 0.002, 0.02), 0.5, rr(0.0, 0.03))
	add(out, ar(svf(noise(0.12, WHITE), BP, [0.0, 3000.0], 2.0), 0.02, 0.0, 0.08), 0.22, 0.1)
	add(out, thump(0.08, 110.0, 80.0, 0.04, 0.03), 0.3)
	return out


func _r_whoosh_small(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.17)) * rr(0.9, 1.1)
	return whoosh(dur, float(p.get("lo_hz", 500.0)) * rr(0.85, 1.15), float(p.get("hi_hz", 2200.0)) * rr(0.85, 1.15), 1.6, PINK, rr(0.4, 0.5))


func _r_whoosh_big(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.32)) * rr(0.9, 1.1)
	var lo := float(p.get("lo_hz", 260.0)) * rr(0.85, 1.15)
	var hi := float(p.get("hi_hz", 1300.0)) * rr(0.85, 1.15)
	var peak_at := rr(0.4, 0.5)
	var out := whoosh(dur, lo, hi, 1.3, PINK, peak_at)
	add(out, ar(svf(noise(dur, BROWN), LP, [0.0, lo * 1.5, dur * peak_at, hi, dur, lo]), dur * peak_at, 0.0, dur * (1.0 - peak_at), 1.8), 0.6)
	return out


# ---------------------------------------------------------------- recipes: melee

func _r_punch_swing(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.12)) * rr(0.9, 1.1)
	return whoosh(dur, float(p.get("lo_hz", 800.0)) * rr(0.85, 1.15), float(p.get("hi_hz", 3000.0)) * rr(0.85, 1.15), 2.0, WHITE, rr(0.3, 0.4))


func _r_punch_hit(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.2))
	var th := float(p.get("thump_hz", 170.0)) * rr(0.88, 1.12)
	var out := make(dur)
	add(out, click(0.004, 3000.0), 0.8)
	add(out, thump(dur, th * 1.6, th * 0.5, 0.03, 0.028), 0.8)
	add(out, perc(svf(noise(dur, PINK), BP, [0.0, rr(950.0, 1300.0), 0.05, 600.0], 1.0), 0.0005, 0.03), 0.9)
	add(out, perc(svf(noise(0.03, WHITE), HP, [0.0, 2500.0]), 0.0003, 0.008), 0.4)
	return drive(out, float(p.get("drive", 2.2)))


func _r_kick_hit(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.38))
	var th := float(p.get("thump_hz", 125.0)) * rr(0.9, 1.1)
	var out := make(dur)
	add(out, click(0.005, 2500.0), 0.8)
	add(out, thump(dur, th * 1.5, th * 0.35, 0.05, 0.055), 0.9)
	add(out, thump(dur, 62.0, 40.0, 0.1, 0.08), 0.5)
	add(out, perc(svf(noise(dur, BROWN), LP, [0.0, 2500.0, 0.1, 400.0]), 0.001, 0.07), 0.9)
	crackle(out, 0.0, 0.05, 6, 1500.0, 4000.0, 0.005, 0.35)
	return drive(out, float(p.get("drive", 3.0)))


func _r_kunai_slash(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.26))
	var out := make(dur)
	add(out, ar(svf(noise(0.16, WHITE), BP, [0.0, 2500.0, 0.06, rr(5500.0, 7000.0), 0.16, 3500.0], 2.5), 0.02, 0.0, 0.12, 2.0), 0.8)
	partials(out, rr(0.025, 0.04), rr(2800.0, 3400.0), [1.0, 1.51, 2.13, 2.79], [1.0, 0.6, 0.45, 0.3], [0.07, 0.05, 0.04, 0.03], 0.35)
	return out


func _r_ninja_poof(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.45))
	var out := make(dur)
	add(out, ar(svf(noise(dur, PINK), LP, [0.0, rr(3000.0, 4000.0), dur, 350.0], 0.7), 0.006, 0.02, dur - 0.03, 2.5), 1.0)
	add(out, thump(0.2, 140.0, 55.0, 0.08, 0.06), 0.6)
	add(out, ar(svf(noise(0.17, WHITE), HP, [0.0, 4000.0]), 0.01, 0.0, 0.15, 3.0), 0.2)
	return out


# ---------------------------------------------------------------- recipes: firearms

func _r_revolver_cock(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.24))
	var gap := float(p.get("gap", 0.11)) * rr(0.9, 1.1)
	var out := make(dur)
	add(out, perc(svf(noise(0.03, WHITE), BP, [0.0, rr(1600.0, 2000.0)], 3.0), 0.0, 0.012), 0.7)
	tick(out, 0.0, rr(2000.0, 2400.0), 0.01, 0.4)
	for k in 3:
		tick(out, 0.02 + k * rr(0.012, 0.016), rr(3000.0, 4000.0), 0.004, 0.18)
	add(out, perc(svf(noise(0.02, WHITE), HP, [0.0, 3000.0]), 0.0, 0.006), 1.0, gap)
	partials(out, gap, rr(2400.0, 2900.0), [1.0, 1.47, 2.31], [1.0, 0.7, 0.5], [0.03, 0.02, 0.015], 0.4)
	add(out, thump(0.04, 400.0, 250.0, 0.01, 0.012), 0.3, gap)
	return out


func _r_revolver_shot(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.95))
	var out := make(dur)
	add(out, perc(noise(0.02, WHITE), 0.0, 0.004), 1.0)
	var blast := perc(svf(noise(0.3, WHITE), LP, [0.0, 9000.0, 0.03, 2500.0, 0.15, 700.0], 0.7), 0.0005, 0.06)
	add(out, blast, 1.0)
	add(out, thump(0.3, rr(165.0, 195.0), 60.0, 0.04, 0.035), 0.55)
	drive(out, float(p.get("drive", 4.0)))
	normalize(out, 1.0)
	add(out, perc(svf(noise(dur, BROWN), LP, [0.0, 900.0, dur, 250.0], 0.7), 0.015, 0.3), 0.45)
	add(out, svf(blast, LP, [0.0, 1500.0]), 0.25, rr(0.1, 0.13))
	return out


func _r_rifle_shot(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.34))
	var out := make(dur)
	add(out, perc(noise(0.01, WHITE), 0.0, 0.003), 1.0)
	add(out, perc(svf(svf(noise(0.12, WHITE), HP, [0.0, 600.0]), LP, [0.0, 8000.0, 0.02, 2000.0]), 0.0005, 0.022), 1.0)
	add(out, thump(0.12, rr(205.0, 235.0), 85.0, 0.025, 0.022), 0.5)
	drive(out, float(p.get("drive", 3.5)))
	normalize(out, 1.0)
	add(out, perc(svf(noise(dur, BROWN), LP, [0.0, 700.0]), 0.01, 0.09), 0.35)
	tick(out, 0.05, rr(3200.0, 3800.0), 0.006, 0.15)
	return out


# Bullet: metallic ping and the falling whine of the deflected round. Arrow: the shaft knocks and
# the steel rings briefly. Blade: a bright clang and a short scrape.
func _r_ricochet(p: Dictionary, w: float, surface: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.42))
	var ring := float(p.get("ring_hz", 2600.0)) * rr(0.88, 1.12)
	var out := make(dur)
	add(out, click(0.003, 5500.0), 0.7)
	match surface:
		&"arrow":
			add(out, thump(0.08, rr(420.0, 520.0), 260.0, 0.012, 0.02, TRI), 0.7)
			partials(out, 0.002, ring * 0.62, [1.0, 2.76, 5.4], [1.0, 0.5, 0.3], [0.09, 0.05, 0.03], 0.5)
			add(out, perc(svf(noise(0.12, PINK), BP, [0.0, rr(2200.0, 2800.0)], 2.0), 0.0, 0.02), 0.4)
		&"blade":
			partials(out, 0.0, ring * 0.4, [1.0, 2.32, 3.98, 5.71], [1.0, 0.7, 0.45, 0.3], [0.22, 0.14, 0.09, 0.06], 0.75)
			var scrape := svf(noise(dur * 0.5, WHITE), BP, [0.0, 5200.0, dur * 0.5, 3000.0], 2.5)
			add(out, ar(scrape, 0.004, 0.02, dur * 0.3, 2.0), 0.35, 0.01)
		_:
			partials(out, 0.0, ring, [1.0, 1.73, 2.61], [1.0, 0.55, 0.35], [0.05, 0.035, 0.025], 0.6)
			var f0 := rr(4200.0, 5200.0)
			var f1 := f0 * rr(0.36, 0.5)
			var len := dur - 0.015
			var whine := wobble(osc(len, SINE, [0.0, f0, len, f1]), rr(28.0, 40.0), 0.25)
			add(out, ar(whine, 0.01, 0.03, len - 0.05, 1.6), 0.4 + 0.2 * w, 0.012)
			var air := svf(noise(len, WHITE), BP, [0.0, f0, len, f1], 6.0)
			add(out, ar(air, 0.01, 0.0, len - 0.03, 1.8), 0.25, 0.012)
	return out


func _r_casing_bounce(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.3))
	var out := make(dur)
	var t := 0.0
	var gap := rr(0.07, 0.1)
	var base := rr(3800.0, 4800.0)
	for k in 4:
		if t > dur - 0.05:
			break
		partials(out, t, base, [1.0, 1.58, 2.39, 3.12], [1.0, 0.7, 0.5, 0.3], [0.05, 0.035, 0.025, 0.02], 0.8 * pow(0.6, k))
		tick(out, t, 6000.0, 0.002, 0.15 * pow(0.6, k))
		t += gap
		gap *= rr(0.55, 0.75)
	return out


# ---------------------------------------------------------------- recipes: bow

func _r_bow_draw(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.65))
	var src := impulses(dur, [0.0, rr(70.0, 100.0), dur, rr(180.0, 240.0)], 0.3)
	var out := make(dur)
	add(out, svf(src.duplicate(), BP, [0.0, 700.0, dur, rr(1000.0, 1200.0)], 8.0), 1.0)
	add(out, svf(src, BP, [0.0, 1800.0], 6.0), 0.5)
	add(out, svf(noise(dur, BROWN), LP, [0.0, 300.0]), 0.15)
	return ar(out, 0.15, dur - 0.3, 0.15, 1.5)


func _r_bow_release(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.42))
	var out := make(dur)
	add(out, perc(svf(pluck(dur, float(p.get("string_hz", 98.0)) * rr(0.95, 1.05), 0.996), LP, [0.0, 2500.0]), 0.0, 0.12), 1.0)
	add(out, perc(svf(noise(0.03, WHITE), HP, [0.0, 2000.0]), 0.0, 0.006), 0.6)
	add(out, thump(0.08, 160.0, 90.0, 0.03, 0.025), 0.5)
	return out


func _r_arrow_whoosh(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.28)) * rr(0.9, 1.1)
	var n := ar(svf(noise(dur, WHITE), BP, [0.0, rr(3500.0, 4200.0), dur, rr(2400.0, 2800.0)], 4.0), 0.04, 0.02, dur - 0.07, 1.5)
	return am(n, rr(38.0, 52.0), 0.5)


func _r_arrow_hit(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.36))
	var out := make(dur)
	add(out, click(0.003, 3000.0), 0.6)
	add(out, thump(0.1, rr(280.0, 320.0), 170.0, 0.015, 0.03, TRI), 0.9)
	add(out, perc(svf(noise(0.2, PINK), BP, [0.0, rr(800.0, 1000.0)], 3.0), 0.0, 0.035), 0.7)
	add(out, perc(am(osc(dur - 0.01, SINE, [0.0, rr(175.0, 205.0)]), rr(24.0, 32.0), 0.8), 0.002, 0.09), 0.35, 0.01)
	return out


# ---------------------------------------------------------------- recipes: damage

func _r_hurt_hit(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.24))
	var th := float(p.get("thump_hz", 105.0)) * rr(0.9, 1.1)
	var out := make(dur)
	add(out, thump(dur, th * 1.4, th * 0.5, 0.035, 0.045), 0.9)
	add(out, perc(svf(noise(dur, BROWN), LP, [0.0, 1200.0, 0.08, 300.0]), 0.001, 0.05), 0.9)
	add(out, perc(svf(noise(0.12, PINK), BP, [0.0, 700.0], 1.0), 0.0005, 0.02), 0.5)
	return drive(out, 2.0)


func _r_bullet_hit_body(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.34))
	var out := make(dur)
	add(out, perc(svf(noise(0.02, WHITE), HP, [0.0, 1500.0]), 0.0, 0.004), 0.7)
	add(out, thump(0.2, rr(185.0, 215.0), 65.0, 0.03, 0.05), 0.9)
	add(out, ar(svf(noise(0.2, PINK), BP, [0.0, 500.0, 0.05, rr(1700.0, 2100.0), 0.18, 700.0], 3.5), 0.003, 0.02, 0.15, 1.8), 0.8)
	drive(out, 1.6)
	normalize(out, 1.0)
	for k in rng.randi_range(3, 4):
		var f0 := rr(450.0, 800.0)
		drop(out, rr(0.04, dur - 0.08), f0, f0 * rr(1.8, 2.4), 0.012, 0.3)
	return out


func _r_blood_splat(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.5))
	var out := make(dur)
	add(out, perc(svf(noise(0.06, PINK), BP, [0.0, 1200.0, 0.04, 600.0], 2.0), 0.001, 0.015), 0.6)
	var t := 0.0
	for k in int(p.get("drops", 6)):
		if t > dur - 0.06:
			break
		var f0 := rr(500.0, 850.0)
		drop(out, t, f0, f0 * rr(1.8, 2.5), rr(0.009, 0.014), 0.8 * pow(0.82, k))
		add(out, perc(svf(noise(0.02, PINK), BP, [0.0, 1500.0], 1.5), 0.0, 0.006), 0.3 * pow(0.82, k), t)
		t += rr(0.03, 0.1)
	return out


# ---------------------------------------------------------------- recipes: wall

func _r_wall_crack(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.5))
	var out := make(dur)
	var count := 14
	for k in count:
		var t := dur * 0.75 * (1.0 - pow(1.0 - float(k) / count, 1.6))
		var a := 1.0 if k == 0 else rr(0.3, 0.9)
		tick(out, t, rr(1200.0, 4000.0), rr(0.004, 0.012), a)
		add(out, perc(svf(noise(0.02, WHITE), BP, [0.0, 2500.0], 1.5), 0.0, 0.006), 0.5 * a, t)
	add(out, ar(svf(noise(dur, BROWN), LP, [0.0, 200.0]), 0.05, dur * 0.4, dur * 0.4), 0.4)
	add(out, thump(dur * 0.5, 90.0, 60.0, 0.2, 0.15), 0.3, 0.05)
	return out


func _r_wall_break(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 1.6))
	var out := make(dur)
	add(out, thump(0.8, rr(82.0, 98.0), 33.0, 0.15, 0.22), 1.0)
	add(out, perc(svf(noise(0.3, WHITE), LP, [0.0, 5000.0, 0.08, 1200.0]), 0.001, 0.06), 0.9)
	add(out, wobble(ar(svf(noise(dur, BROWN), LP, [0.0, 1500.0, dur, 200.0]), 0.01, 0.1, dur - 0.2, 1.4), 20.0, 0.6), 0.7)
	drive(out, float(p.get("drive", 2.0)))
	normalize(out, 1.0)
	for k in int(p.get("chunks", 46)):
		var t := 0.02 + dur * 0.85 * pow(rr(0.0, 1.0), 1.8)
		var a := rr(0.2, 0.6) * (1.0 - t / dur)
		tick(out, t, rr(700.0, 3200.0), rr(0.008, 0.03), a)
		if rng.randf() < 0.3:
			var f := rr(150.0, 260.0)
			add(out, thump(0.06, f, f * 0.6, 0.02, 0.018), a * 0.8, t)
	return out


func _r_debris_bounce(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.32))
	var out := make(dur)
	var t := 0.0
	var gap := rr(0.08, 0.12)
	for k in rng.randi_range(3, 4):
		if t > dur - 0.04:
			break
		var a := pow(0.7, k)
		add(out, click(0.003, 3000.0), 0.5 * a, t)
		add(out, perc(svf(noise(0.05, PINK), BP, [0.0, rr(1500.0, 2800.0)], 2.0), 0.0, 0.015), a, t)
		add(out, thump(0.04, 220.0, 160.0, 0.01, 0.012), 0.4 * a, t)
		t += gap
		gap *= 0.7
	return out


# ---------------------------------------------------------------- recipes: props

func _creak(dur: float, formant: float) -> PackedFloat32Array:
	var src := impulses(dur, [0.0, rr(90.0, 130.0), dur * 0.5, rr(180.0, 260.0), dur, rr(110.0, 150.0)], 0.25)
	var out := make(dur)
	add(out, svf(src.duplicate(), BP, [0.0, formant * rr(0.9, 1.1)], 10.0), 1.0)
	add(out, svf(src, BP, [0.0, formant * 1.9], 8.0), 0.5)
	return normalize(ar(out, 0.06, dur - 0.2, 0.14, 1.3), 1.0)


func _r_chair_creak(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	return _creak(float(p.get("dur", 0.5)) * rr(0.85, 1.15), float(p.get("formant_hz", 850.0)))


func _r_bed_creak(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.75)) * rr(0.9, 1.1)
	var out := _creak(dur, float(p.get("formant_hz", 520.0)))
	var f := rr(1400.0, 1800.0)
	add(out, ar(osc(0.6, SINE, [0.0, f, 0.3, f * 1.06, 0.6, f * 0.97]), 0.1, 0.2, 0.3), 0.12, 0.08)
	add(out, perc(svf(noise(0.4, BROWN), LP, [0.0, 300.0]), 0.01, 0.1), 0.4)
	return out


func _r_trap_snap(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.4))
	var out := make(dur)
	add(out, perc(svf(noise(0.02, WHITE), HP, [0.0, 2000.0]), 0.0, 0.003), 1.0)
	partials(out, 0.0, rr(850.0, 1000.0), [1.0, 1.71, 2.62, 3.9], [1.0, 0.8, 0.6, 0.4], [0.18, 0.12, 0.09, 0.06], 0.6)
	add(out, thump(0.12, 260.0, 110.0, 0.02, 0.04, TRI), 0.8)
	add(out, perc(svf(osc(0.2, SQUARE, [0.0, 70.0]), LP, [0.0, 900.0]), 0.002, 0.08), 0.25, 0.01)
	return drive(out, 1.5)


func _r_turret_shot(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.36))
	var out := make(dur)
	add(out, perc(svf(osc(0.15, SQUARE, [0.0, rr(480.0, 560.0), 0.07, 140.0]), LP, [0.0, 3000.0, 0.1, 800.0], 1.0), 0.0008, 0.06), 0.7)
	add(out, perc(svf(noise(0.06, WHITE), BP, [0.0, 2200.0], 1.2), 0.0, 0.025), 0.7)
	partials(out, 0.0, rr(1250.0, 1350.0), [1.0, 1.33, 2.08], [1.0, 0.7, 0.5], [0.08, 0.06, 0.04], 0.3)
	drive(out, float(p.get("drive", 2.0)))
	normalize(out, 1.0)
	tick(out, 0.09, 2800.0, 0.01, 0.35)
	add(out, thump(0.04, 350.0, 250.0, 0.01, 0.012), 0.35, 0.09)
	add(out, ar(svf(osc(0.2, SAW, [0.0, 180.0, 0.15, 240.0]), LP, [0.0, 900.0]), 0.02, 0.05, 0.12), 0.15, 0.12)
	return out


# ---------------------------------------------------------------- recipes: training props

func _r_scarecrow_hit(p: Dictionary, _w: float, surface: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.34))
	var slash := surface == &"slash"
	var out := make(dur)
	add(out, ar(svf(noise(0.2, WHITE), BP, [0.0, rr(3200.0, 4000.0), 0.2, 2200.0], 0.9), 0.002, 0.03, 0.15, 1.5), 0.7)
	crackle(out, 0.0, 0.16, 14, 2000.0, 6000.0, 0.003, 0.45)
	add(out, thump(0.16, rr(130.0, 150.0), 80.0, 0.03, 0.035 if slash else 0.045), 0.6 if slash else 0.9)
	add(out, perc(svf(noise(0.2, BROWN), LP, [0.0, 600.0]), 0.001, 0.04), 0.6)
	if slash:
		add(out, perc(svf(noise(0.05, WHITE), HP, [0.0, 3000.0]), 0.0, 0.015), 0.6)
	var wet := 0.75 if slash else 0.35
	add(out, ar(svf(noise(0.14, PINK), BP, [0.0, 600.0, 0.04, rr(1600.0, 2000.0), 0.12, 800.0], 3.0), 0.003, 0.01, 0.1, 1.8), wet, 0.015)
	for k in (3 if slash else 1):
		var f0 := rr(500.0, 800.0)
		drop(out, rr(0.05, dur - 0.08), f0, f0 * rr(1.8, 2.4), 0.011, wet * 0.45)
	return out


func _r_cup_hit(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.12))
	var out := make(dur)
	add(out, click(0.003, 3000.0), 0.6)
	partials(out, 0.0, rr(1500.0, 1900.0), [1.0, 2.3, 3.7], [1.0, 0.6, 0.35], [0.025, 0.018, 0.012], 0.8)
	add(out, perc(svf(noise(dur, WHITE), BP, [0.0, rr(2300.0, 2800.0)], 6.0), 0.0, 0.02), 0.5)
	return out


func _r_cup_fall(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.5)) * rr(0.6, 1.0)
	var out := make(dur)
	var base := rr(1300.0, 1700.0)
	var t := 0.0
	var gap := rr(0.06, 0.09)
	var k := 0
	while t < dur - 0.03:
		var a := pow(0.78, k)
		partials(out, t, base * rr(0.95, 1.05), [1.0, 2.2], [1.0, 0.5], [0.015, 0.01], a)
		tick(out, t, 4000.0, 0.002, 0.3 * a)
		t += gap
		gap = maxf(gap * rr(0.7, 0.85), 0.035)
		k += 1
	return out


func _r_button_press(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.16))
	var release := rr(0.05, 0.08)
	var out := make(dur)
	tick(out, 0.0, rr(2300.0, 2700.0), 0.006, 0.8)
	add(out, thump(0.04, 500.0, 300.0, 0.005, 0.006), 0.4)
	add(out, perc(svf(noise(0.02, WHITE), HP, [0.0, 2000.0]), 0.0, 0.003), 0.5)
	tick(out, release, rr(3200.0, 3700.0), 0.004, 0.5)
	add(out, perc(svf(noise(0.02, WHITE), HP, [0.0, 3000.0]), 0.0, 0.002), 0.3, release)
	return out


# ---------------------------------------------------------------- recipes: balloons and bow aim

func _r_balloon_pop(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.12))
	var out := make(dur)
	add(out, perc(svf(noise(0.03, WHITE), HP, [0.0, rr(1300.0, 1800.0)], 0.7), 0.0, 0.006), 1.0)
	add(out, perc(svf(noise(0.08, WHITE), BP, [0.0, rr(2500.0, 4000.0)], 1.5), 0.0, 0.015), 0.6)
	add(out, thump(0.05, rr(160.0, 200.0), 90.0, 0.01, 0.012), 0.3)
	tick(out, rr(0.008, 0.02), rr(1800.0, 2600.0), 0.004, 0.25)
	tick(out, rr(0.02, 0.035), rr(1500.0, 2200.0), 0.004, 0.15)
	return drive(out, 1.5)


func _r_balloon_release(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.45)) * rr(0.85, 1.15)
	var n := svf(noise(dur, PINK), BP, [0.0, rr(1100.0, 1400.0), dur * 0.35, 700.0, dur, 400.0], 2.0)
	return am(ar(n, 0.01, 0.05, dur - 0.08, 1.2), rr(25.0, 40.0), 0.6)


func _r_bow_aim(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var xf := 0.12
	var dur := float(p.get("dur", 1.0)) + xf
	var src := impulses(dur, [0.0, rr(150.0, 190.0)], 0.25)
	var out := make(dur)
	add(out, svf(src.duplicate(), BP, [0.0, 1000.0], 9.0), 1.0)
	add(out, svf(src, BP, [0.0, 1900.0], 7.0), 0.4)
	add(out, svf(osc(dur, TRI, [0.0, 110.0]), LP, [0.0, 400.0]), 0.08)
	return finish_loop(wobble(out, 3.0, 0.35), xf)


# ---------------------------------------------------------------- recipes: water

func _r_splash(p: Dictionary, w: float, _s: StringName) -> PackedFloat32Array:
	var dur := lerpf(float(p.get("dur_light", 0.3)), float(p.get("dur_heavy", 0.95)), w)
	var out := make(dur)
	add(out, perc(svf(noise(dur, WHITE), LP, [0.0, 6000.0, 0.1, 1500.0]), 0.001, lerpf(0.04, 0.1, w)), 1.0)
	add(out, thump(0.2, rr(110.0, 130.0), 60.0, 0.04, lerpf(0.02, 0.06, w)), 0.4 + 0.3 * w)
	add(out, ar(svf(noise(dur, PINK), HP, [0.0, 2000.0]), 0.003, 0.03, lerpf(0.1, 0.35, w), 1.5), 0.6)
	if w > 0.3:
		for k in int(4 + 14 * w):
			var f0 := rr(300.0, 900.0)
			drop(out, rr(0.08, dur - 0.06), f0, f0 * rr(1.4, 2.0), rr(0.006, 0.012), rr(0.12, 0.3))
	return out


func _r_splash_out(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.8))
	var out := make(dur)
	add(out, ar(svf(noise(0.25, PINK), BP, [0.0, 800.0, 0.1, rr(1800.0, 2200.0)], 1.2), 0.03, 0.05, 0.15), 0.8)
	add(out, wobble(ar(svf(noise(0.55, WHITE), BP, [0.0, 3000.0], 2.0), 0.05, 0.2, 0.3), 12.0, 0.6), 0.25, 0.1)
	var t := 0.15
	for k in rng.randi_range(5, 8):
		if t > dur - 0.06:
			break
		var f0 := rr(800.0, 1400.0)
		drop(out, t, f0, f0 * rr(1.5, 2.0), 0.008, 0.3 * pow(0.85, k))
		t += rr(0.05, 0.12)
	return out


func _r_swim_stroke(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.28)) * rr(0.9, 1.1)
	var out := make(dur)
	add(out, ar(svf(noise(dur, PINK), BP, [0.0, 700.0, 0.08, rr(1400.0, 1800.0), dur, 900.0], 1.5), 0.015, 0.03, dur - 0.05, 1.5), 1.0)
	add(out, perc(svf(noise(0.08, WHITE), HP, [0.0, 3000.0]), 0.002, 0.02), 0.35, 0.02)
	for k in 2:
		var f0 := rr(600.0, 1100.0)
		drop(out, rr(0.06, dur - 0.05), f0, f0 * 1.7, 0.007, 0.2)
	return out


func _r_swim_under(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.4)) * rr(0.9, 1.1)
	var out := make(dur)
	add(out, ar(svf(noise(dur, BROWN), LP, [0.0, 500.0, dur, 250.0]), 0.06, 0.05, dur - 0.12), 1.0)
	add(out, wobble(ar(svf(noise(dur, PINK), BP, [0.0, 400.0], 1.0), 0.05, 0.05, dur - 0.11), 8.0, 0.5), 0.4)
	for k in rng.randi_range(2, 3):
		var f0 := rr(200.0, 400.0)
		drop(out, rr(0.05, dur - 0.08), f0, f0 * 1.6, 0.012, 0.25)
	return out


func _r_bubble(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.1))
	var out := make(dur)
	var f0 := rr(350.0, 1100.0)
	drop(out, 0.0, f0, f0 * rr(1.4, 2.1), rr(0.006, 0.014), 1.0)
	if rng.randf() < 0.4:
		var f1 := f0 * rr(1.2, 1.6)
		drop(out, rr(0.02, 0.05), f1, f1 * 1.8, 0.006, 0.5)
	return out


func _r_underwater(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var xf := 0.25
	var dur := float(p.get("dur", 2.0)) + xf
	var out := make(dur)
	add(out, wobble(svf(noise(dur, BROWN), LP, [0.0, 250.0]), 0.8, 0.5), 1.0)
	add(out, wobble(svf(noise(dur, PINK), LP, [0.0, 500.0]), 2.0, 0.4), 0.3)
	add(out, osc(dur, SINE, [0.0, 55.0]), 0.12)
	for k in 8:
		var f0 := rr(200.0, 500.0)
		drop(out, rr(0.0, dur - 0.1), f0, f0 * 1.6, 0.012, rr(0.08, 0.15))
	return finish_loop(out, xf)


func _r_water_flow(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var xf := 0.15
	var dur := float(p.get("dur", 1.6)) + xf
	var out := make(dur)
	add(out, wobble(svf(noise(dur, WHITE), BP, [0.0, 1200.0], 0.7), 6.0, 0.4), 0.7)
	add(out, wobble(svf(noise(dur, PINK), HP, [0.0, 2500.0]), 11.0, 0.5), 0.4)
	add(out, wobble(svf(noise(dur, BROWN), LP, [0.0, 350.0]), 2.0, 0.4), 0.6)
	for k in int(p.get("gurgles", 26)):
		var f0 := rr(400.0, 1200.0)
		drop(out, rr(0.0, dur - 0.08), f0, f0 * rr(1.4, 2.0), 0.008, rr(0.1, 0.25))
	return finish_loop(out, xf)


func _r_dam_break(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 2.4))
	var give := rr(0.4, 0.5)
	var out := make(dur)
	for k in 10:
		var t := give * 0.9 * (1.0 - pow(1.0 - k / 10.0, 1.5))
		tick(out, t, rr(1000.0, 3500.0), rr(0.005, 0.014), 1.0 if k == 0 else rr(0.3, 0.8))
	add(out, ar(svf(noise(1.0, BROWN), LP, [0.0, 150.0]), 0.2, 0.3, 0.5), 0.5, 0.15)
	add(out, thump(1.0, rr(70.0, 80.0), 30.0, 0.2, 0.3), 1.0, give)
	add(out, perc(svf(noise(0.4, WHITE), LP, [0.0, 5000.0, 0.1, 1000.0]), 0.001, 0.08), 0.8, give)
	add(out, wobble(ar(svf(noise(dur - give, WHITE), BP, [0.0, 600.0, dur - give, 1500.0], 0.6), 0.3, 0.8, dur - give - 1.1, 1.3), 5.0, 0.4), 0.8, give + 0.05)
	drive(out, float(p.get("drive", 1.8)))
	normalize(out, 1.0)
	for k in int(p.get("chunks", 40)):
		var t := give + (dur * 0.7 - give) * pow(rr(0.0, 1.0), 1.6)
		tick(out, t, rr(700.0, 3000.0), rr(0.008, 0.025), rr(0.15, 0.5) * (1.0 - t / dur))
	return out


func _r_drown_hit(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.42))
	var out := make(dur)
	add(out, svf(thump(0.25, rr(100.0, 120.0), 50.0, 0.05, 0.06), LP, [0.0, 400.0]), 1.0)
	add(out, perc(svf(noise(0.25, BROWN), LP, [0.0, 500.0]), 0.002, 0.06), 0.7)
	for k in 5:
		var f0 := rr(250.0, 600.0)
		drop(out, rr(0.03, 0.3), f0, f0 * rr(1.5, 2.0), 0.01, rr(0.2, 0.4))
	return drive(out, 1.3)


func _r_oxygen_warning(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.22))
	var out := make(dur)
	add(out, perc(osc(0.08, TRI, [0.0, 880.0]), 0.002, 0.025), 0.8)
	add(out, perc(osc(0.08, TRI, [0.0, 886.0]), 0.002, 0.025), 0.4)
	add(out, perc(osc(0.1, TRI, [0.0, 740.0]), 0.002, 0.03), 0.7, 0.09)
	add(out, thump(0.1, 95.0, 80.0, 0.02, 0.03), 0.4)
	return out


# ---------------------------------------------------------------- recipes: ending sequence

func _r_quake_rumble(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var xf := 0.25
	var dur := float(p.get("dur", 2.2)) + xf
	var out := make(dur)
	add(out, wobble(svf(noise(dur, BROWN), LP, [0.0, 120.0]), 1.5, 0.5), 1.0)
	add(out, wobble(svf(noise(dur, BROWN), LP, [0.0, 400.0]), 4.0, 0.6), 0.5)
	add(out, osc(dur, SINE, [0.0, 38.0]), 0.2)
	crackle(out, 0.0, dur - 0.05, int(p.get("creaks", 34)), 600.0, 2500.0, 0.01, 0.35)
	return finish_loop(out, xf)


func _r_rock_fall(p: Dictionary, w: float, _s: StringName) -> PackedFloat32Array:
	var dur := lerpf(float(p.get("dur_light", 0.25)), float(p.get("dur_heavy", 0.7)), w) * rr(0.9, 1.1)
	var f := lerpf(260.0, 85.0, w) * rr(0.85, 1.15)
	var out := make(dur)
	add(out, click(0.004, 2500.0), 0.7)
	add(out, thump(dur, f, f * 0.55, 0.03, lerpf(0.02, 0.07, w)), 1.0)
	add(out, perc(svf(noise(dur, WHITE), LP, [0.0, lerpf(4000.0, 1800.0, w)]), 0.0008, lerpf(0.02, 0.06, w)), 0.8)
	var bounce := rr(0.08, 0.15)
	add(out, thump(0.12, f * 1.3, f * 0.8, 0.02, 0.02), 0.4, bounce)
	tick(out, bounce, rr(1200.0, 2500.0), 0.008, 0.3)
	crackle(out, 0.01, dur * 0.7, int(3 + 8 * w), 900.0, 3500.0, 0.008, 0.3)
	if w > 0.6:
		drive(out, 2.0)
	return out


func _r_cave_in(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 4.0))
	var out := make(dur)
	add(out, thump(1.5, rr(65.0, 75.0), 25.0, 0.3, 0.45), 1.0)
	add(out, thump(1.2, rr(55.0, 65.0), 28.0, 0.3, 0.4), 0.7, rr(0.2, 0.3))
	add(out, perc(svf(noise(0.6, WHITE), LP, [0.0, 5000.0, 0.15, 800.0]), 0.001, 0.12), 0.9)
	add(out, wobble(ar(svf(noise(dur, BROWN), LP, [0.0, 800.0, dur, 120.0]), 0.02, 0.5, 3.2, 1.6), 0.8, 0.4), 0.8)
	drive(out, float(p.get("drive", 2.0)))
	normalize(out, 1.0)
	add(out, wobble(ar(svf(noise(dur, WHITE), BP, [0.0, 2500.0, dur, 1800.0], 0.8), 0.3, 0.8, 2.4, 2.0, 0.4), 10.0, 0.7), 0.3)
	for k in int(p.get("gravel", 120)):
		var t := 0.3 + 3.3 * pow(rr(0.0, 1.0), 2.0)
		tick(out, t, rr(800.0, 4500.0), rr(0.004, 0.015), rr(0.1, 0.45) * (1.0 - t / dur))
	return out


# Warm strummed add9 chord: detuned saw pairs through a slow low-pass swell.
func _r_ending_sting(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 2.8))
	var out := make(dur)
	var notes := [130.81, 261.63, 329.63, 392.0, 587.33]
	var gains := [0.7, 0.8, 0.7, 0.65, 0.5]
	for k in notes.size():
		var at := k * 0.025
		var len := dur - at
		var f: float = notes[k]
		var v := osc(len, SAW, [0.0, f * 1.0035])
		add(v, osc(len, SAW, [0.0, f * 0.9965], rr(0.0, 1.0)), 1.0)
		svf(v, LP, [0.0, 800.0, 0.4, 2600.0, len, 900.0], 0.9)
		add(out, ar(v, 0.04, 0.6, len - 0.7, 1.6), gains[k], at)
	add(out, ar(osc(dur, SINE, [0.0, 65.41]), 0.08, 0.6, dur - 0.7, 1.6), 0.35)
	ping(out, 0.05, 1046.5, 0.5, 0.25)
	return out


# ---------------------------------------------------------------- recipes: motocross

# Phase (in cycles) at sample i of an n-sample loop: k whole cycles plus sinusoidal FM terms
# [depth_cycles, whole_cycles_per_loop, phase] that also close, so the loop seam is sample-exact.
func _engine_phase(i: int, n: int, k: float, fm: Array) -> float:
	var u := float(i) / n
	var ph := k * u
	for m: Array in fm:
		ph += float(m[0]) * sin(TAU * float(m[1]) * u + float(m[2]))
	return ph


# Two-stroke idle: the tonal layers are exactly periodic (no crossfade, which would swell coherent
# content); only the noise layers go through finish_loop.
func _r_moto_engine(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var xf := 0.12
	var n := int(float(p.get("dur", 1.2)) * sr)
	var x_n := int(xf * sr)
	var warm := int(0.25 * sr) # filter settling, cut off afterwards
	# Firing cycles per loop: even, so the half-rate pop also closes the loop.
	var k := float(maxi(2, roundi(float(p.get("hz", 46.0)) * n / sr * 0.5) * 2))
	var fm := []
	for m in [3, 5, 8]:
		fm.append([k * 0.012 / (TAU * m), m, rr(0.0, TAU)])
	var kick := PackedFloat32Array()
	kick.resize(int(k))
	for c in kick.size():
		kick[c] = rr(0.3, 0.5) if rng.randf() < 0.06 else rr(0.7, 1.0)
	var total := warm + n
	var saw := PackedFloat32Array()
	saw.resize(total)
	var pop := PackedFloat32Array()
	pop.resize(total)
	for i in total:
		var ph := _engine_phase(i - warm, n, k, fm)
		var cyc := floorf(ph)
		var fr := ph - cyc
		var pulse := kick[posmod(int(cyc), int(k))] * exp(-fr * 5.0)
		saw[i] = (2.0 * fr - 1.0) * (0.4 + 0.6 * pulse)
		var half := ph * 0.5
		pop[i] = (1.0 if half - floorf(half) < 0.5 else -1.0) * (0.5 + 0.5 * pulse)
	var bite := svf(saw.duplicate(), BP, [0.0, rr(1000.0, 1300.0)], 2.5).slice(warm, total)
	var body := svf(saw, LP, [0.0, rr(380.0, 480.0)], 1.3).slice(warm, total)
	var thud := svf(pop, LP, [0.0, 220.0], 0.9).slice(warm, total)
	# Exhaust / intake noise, gated by the same ignition pulses.
	var len := n + x_n
	var exhaust := svf(noise((len + 2) / sr, PINK), BP, [0.0, rr(650.0, 850.0)], 1.1)
	exhaust.resize(len)
	for i in len:
		var ph := _engine_phase(i, n, k, fm)
		var cyc := floorf(ph)
		exhaust[i] *= 0.25 + 0.75 * kick[posmod(int(cyc), int(k))] * exp(-(ph - cyc) * 5.0)
	var intake := svf(noise((len + 2) / sr, BROWN), LP, [0.0, 300.0])
	intake.resize(len)
	var air := PackedFloat32Array()
	air.resize(len)
	add(air, wobble(exhaust, 6.0, 0.3), 1.0)
	add(air, wobble(intake, 3.0, 0.4), 0.6)
	air = finish_loop(air, xf)
	var out := PackedFloat32Array()
	out.resize(n)
	add(out, body, 1.0)
	add(out, thud, 0.6)
	add(out, bite, 0.14)
	add(out, air, 0.3)
	drive(out, 1.6)
	var mean := 0.0
	for v in out:
		mean += v
	mean /= n
	for i in n:
		out[i] -= mean
	return normalize(out, Tuning.TARGET_PEAK)


func _r_moto_crash(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.9))
	var out := make(dur)
	# Rider and bike hitting the ground.
	add(out, thump(0.45, rr(95.0, 115.0), rr(38.0, 46.0), 0.07, rr(0.09, 0.13)), 1.0)
	add(out, perc(svf(noise(0.5, BROWN), LP, [0.0, rr(1400.0, 1900.0), 0.4, 250.0], 0.8), 0.001, 0.08), 0.8)
	add(out, perc(svf(noise(0.04, WHITE), HP, [0.0, 1500.0]), 0.0, 0.008), 0.5)
	# Metal and plastic scraping along the track, decaying.
	var slide := dur * rr(0.65, 0.8)
	var t0 := rr(0.03, 0.07)
	add(out, wobble(ar(svf(noise(slide, WHITE), BP, [0.0, rr(2600.0, 3400.0), slide, rr(1300.0, 1700.0)], 1.4),
		0.01, slide * 0.1, slide * 0.85, 1.8), rr(11.0, 17.0), 0.6), 0.55, t0)
	add(out, wobble(ar(svf(noise(slide, PINK), BP, [0.0, rr(800.0, 1100.0), slide, 500.0], 1.8),
		0.008, slide * 0.15, slide * 0.8, 1.6), rr(6.0, 10.0), 0.5), 0.5, t0)
	add(out, ar(svf(impulses(slide, [0.0, rr(70.0, 110.0), slide, rr(25.0, 40.0)], 0.6), BP, [0.0, rr(1500.0, 2100.0)], 4.0),
		0.005, 0.0, slide * 0.95, 1.5), 0.3, t0)
	crackle(out, t0, t0 + slide * 0.8, rng.randi_range(14, 22), 1200.0, 4500.0, 0.005, 0.3)
	drive(out, 1.7)
	normalize(out, 1.0)
	# Metallic clanks: frame, footpeg or handlebar.
	for c in rng.randi_range(1, 2):
		var at := rr(0.0, 0.03) if c == 0 else rr(0.18, 0.4)
		partials(out, at, rr(700.0, 1100.0), [1.0, 1.58, 2.37, 3.41, 4.6], [1.0, 0.7, 0.55, 0.4, 0.25],
			[0.16, 0.11, 0.08, 0.05, 0.035], 0.3 if c == 0 else 0.2)
		tick(out, at, rr(2500.0, 3800.0), 0.006, 0.3)
	return out


# ---------------------------------------------------------------- recipes: UI

func _r_prompt_pop(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.1))
	var out := make(dur)
	var f := rr(560.0, 640.0)
	add(out, perc(osc(dur, SINE, [0.0, f, 0.03, f * 1.8]), 0.004, 0.025), 1.0)
	add(out, perc(svf(noise(0.03, WHITE), BP, [0.0, 3000.0], 1.5), 0.0, 0.005), 0.1)
	return out


# Detuned saw pair through a moving low-pass: the shared "synth" timbre of the musical stings.
func saw_voice(len: float, f: float, lp_pts: Array) -> PackedFloat32Array:
	var v := osc(len, SAW, [0.0, f * 1.0035])
	add(v, osc(len, SAW, [0.0, f * 0.9965], rr(0.0, 1.0)), 1.0)
	return svf(v, LP, lp_pts, 0.9)


func _r_achievement(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 1.3))
	var step := float(p.get("step", 0.09))
	var out := make(dur)
	var notes := [523.25, 659.26, 783.99, 1046.5]
	for k in notes.size():
		var at := k * step
		var last := k == notes.size() - 1
		var len := dur - at if last else 0.3
		var v := saw_voice(len, notes[k], [0.0, 1500.0, 0.05, 5000.0, len, 1800.0])
		add(out, ar(v, 0.008, 0.25 if last else 0.06, len - (0.26 if last else 0.07), 1.6), 0.8, at)
	ping(out, 3 * step, 2093.0, 0.3, 0.2)
	return out


func _r_menu_move(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var out := make(float(p.get("dur", 0.05)))
	tick(out, 0.0, 2800.0, 0.004, 1.0)
	add(out, perc(osc(0.04, TRI, [0.0, 1800.0]), 0.001, 0.012), 0.3)
	return out


func _r_menu_select(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var out := make(float(p.get("dur", 0.18)))
	add(out, click(0.003, 2500.0), 0.4)
	add(out, perc(osc(0.1, TRI, [0.0, 660.0, 0.02, 990.0]), 0.002, 0.04), 1.0)
	add(out, perc(osc(0.14, TRI, [0.0, 1320.0]), 0.002, 0.05), 0.6, 0.03)
	add(out, thump(0.06, 300.0, 200.0, 0.02, 0.015), 0.3)
	return out


func _r_pause_open(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.16))
	var out := make(dur)
	add(out, ar(svf(osc(dur, TRI, [0.0, 180.0, 0.12, 520.0]), LP, [0.0, 1200.0]), 0.01, 0.03, dur - 0.05), 1.0)
	add(out, ar(svf(noise(dur, PINK), LP, [0.0, 300.0, 0.12, 1500.0]), 0.01, 0.03, dur - 0.05), 0.4)
	return out


func _r_pause_close(p: Dictionary, w: float, s: StringName) -> PackedFloat32Array:
	var out := _r_pause_open(p, w, s)
	out.reverse()
	return ar(out, 0.005, out.size() / sr - 0.035, 0.03)


func _r_weapon_switch(p: Dictionary, _w: float, _s: StringName) -> PackedFloat32Array:
	var dur := float(p.get("dur", 0.09))
	var out := make(dur)
	tick(out, 0.0, 3500.0, 0.005, 0.6)
	tick(out, 0.035, 2600.0, 0.006, 0.8)
	add(out, perc(osc(0.05, TRI, [0.0, 1250.0, 0.03, 1300.0]), 0.001, 0.02), 0.25, 0.01)
	return out
