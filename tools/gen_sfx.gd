extends SceneTree
## Synthesizes every sound effect and the music loop. No external audio is used.
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/gen_sfx.gd
## Output: assets/audio/*.wav (22050 Hz, mono, 16-bit).

const RATE: int = 22050
const OUT_DIR: String = "res://assets/audio/"

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.seed = 7
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_write("swing_light", _swing(0.18, 1800.0, 5200.0, 0.55))
	_write("swing_heavy", _swing(0.32, 600.0, 2600.0, 0.9))
	_write("hit_light", _hit(0.16, 190.0, 90.0, 0.7))
	_write("hit_heavy", _hit(0.30, 130.0, 45.0, 1.0))
	_write("hurt", _hurt())
	_write("dodge", _dodge())
	_write("pickup", _blips([660.0, 990.0], 0.09, 0.22))
	_write("equip", _blips([440.0, 554.4, 659.3, 880.0], 0.08, 0.45))
	_write("heal", _heal())
	_write("enemy_swing_windup", _windup())
	_write("enemy_death", _death())
	_write("wave_start", _fanfare())
	_write("music_loop", _music())
	_write("teleport", _teleport())  # last: shares the seeded RNG, so earlier sounds stay byte-identical
	_write("boss_slam", _boss_slam())
	_write("boss_charge", _boss_charge())
	_write("boss_leap", _boss_leap())
	_write("boss_roar", _boss_roar())
	_write("boss_fire", _boss_fire())
	_write("mission_complete", _blips([392.0, 494.0, 587.3, 784.0, 988.0], 0.14, 1.0))
	_write("ui_click", _blips([880.0, 1320.0], 0.035, 0.09))
	_write("footstep", _footstep())
	_write("ambience_loop", _ambience())
	_write("radio_static", _radio_static())
	_write("radio_beep", _blips([1500.0], 0.09, 0.1))
	# Milestone 7 region ambience and one-shots: appended last so every earlier sound keeps its exact bytes.
	_write("ambience_coast", _ambience_coast())
	_write("ambience_jungle", _ambience_jungle())
	_write("ambience_facility", _ambience_facility())
	_write("bird_flush", _bird_flush())
	_write("metal_creak", _metal_creak())
	# Opening: cinematic menu background sounds, appended last so every earlier sound keeps its exact bytes.
	_write("menu_thunder", _menu_thunder())
	_write("menu_wind", _menu_wind())
	_write("menu_waves", _menu_waves())
	quit()


# --- building blocks -------------------------------------------------------

func _samples(duration: float) -> int:
	return int(duration * RATE)


func _noise(duration: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_samples(duration))
	for i in out.size():
		out[i] = _rng.randf_range(-1.0, 1.0)
	return out


## One-pole low-pass whose cutoff moves linearly from f0 to f1 over the buffer.
func _lowpass(buf: PackedFloat32Array, f0: float, f1: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(buf.size())
	var y := 0.0
	for i in buf.size():
		var fc := lerpf(f0, f1, float(i) / maxf(buf.size() - 1, 1))
		var a := clampf(TAU * fc / RATE, 0.0, 1.0)
		y += a * (buf[i] - y)
		out[i] = y
	return out


func _highpass(buf: PackedFloat32Array, fc: float) -> PackedFloat32Array:
	var low := _lowpass(buf, fc, fc)
	var out := PackedFloat32Array()
	out.resize(buf.size())
	for i in buf.size():
		out[i] = buf[i] - low[i]
	return out


## attack/decay envelope: linear attack (seconds), exponential decay rate (1/s).
func _env(buf: PackedFloat32Array, attack: float, decay: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(buf.size())
	for i in buf.size():
		var t := float(i) / RATE
		var a := minf(t / maxf(attack, 0.0001), 1.0)
		out[i] = buf[i] * a * exp(-t * decay)
	return out


## Smooth rise and fall (sin^2) — good for whooshes.
func _bell(buf: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(buf.size())
	for i in buf.size():
		var s := sin(PI * float(i) / maxf(buf.size() - 1, 1))
		out[i] = buf[i] * s * s
	return out


## Sine sweep from f0 to f1 with optional vibrato.
func _sweep(duration: float, f0: float, f1: float, vib_hz: float = 0.0, vib_depth: float = 0.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_samples(duration))
	var phase := 0.0
	for i in out.size():
		var p := float(i) / maxf(out.size() - 1, 1)
		var f := lerpf(f0, f1, p)
		f *= 1.0 + vib_depth * sin(TAU * vib_hz * float(i) / RATE)
		phase += TAU * f / RATE
		out[i] = sin(phase)
	return out


func _saw(duration: float, f0: float, f1: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_samples(duration))
	var phase := 0.0
	for i in out.size():
		var f := lerpf(f0, f1, float(i) / maxf(out.size() - 1, 1))
		phase = fmod(phase + f / RATE, 1.0)
		out[i] = phase * 2.0 - 1.0
	return out


func _mix(a: PackedFloat32Array, b: PackedFloat32Array, gain_b: float = 1.0, offset_sec: float = 0.0) -> PackedFloat32Array:
	var offset := _samples(offset_sec)
	var out := PackedFloat32Array()
	out.resize(maxi(a.size(), b.size() + offset))
	for i in a.size():
		out[i] = a[i]
	for i in b.size():
		out[i + offset] += b[i] * gain_b
	return out


func _normalize(buf: PackedFloat32Array, peak: float = 0.8) -> PackedFloat32Array:
	var biggest := 0.0001
	for s in buf:
		biggest = maxf(biggest, absf(s))
	var out := PackedFloat32Array()
	out.resize(buf.size())
	for i in buf.size():
		out[i] = buf[i] / biggest * peak
	return out


# --- sounds ----------------------------------------------------------------

func _swing(duration: float, cutoff_from: float, cutoff_to: float, gain: float) -> PackedFloat32Array:
	var n := _highpass(_noise(duration), 300.0)
	n = _bell(_lowpass(n, cutoff_from, cutoff_to))
	return _scaled(_normalize(n), gain)


func _scaled(buf: PackedFloat32Array, gain: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(buf.size())
	for i in buf.size():
		out[i] = buf[i] * gain
	return out


func _hit(duration: float, f0: float, f1: float, gain: float) -> PackedFloat32Array:
	var thump := _env(_sweep(duration, f0, f1), 0.002, 14.0)
	var crack := _env(_lowpass(_noise(duration), 5000.0, 900.0), 0.001, 30.0)
	return _scaled(_normalize(_mix(thump, crack, 0.7)), gain)


func _hurt() -> PackedFloat32Array:
	var tone := _env(_saw(0.28, 320.0, 110.0), 0.003, 9.0)
	var grit := _env(_lowpass(_noise(0.28), 2500.0, 600.0), 0.002, 12.0)
	return _normalize(_mix(_lowpass(tone, 1800.0, 700.0), grit, 0.6))


func _dodge() -> PackedFloat32Array:
	var n := _highpass(_noise(0.26), 900.0)
	n = _bell(_lowpass(n, 3000.0, 9000.0))
	return _normalize(n, 0.6)


## Rising whoosh into a falling shimmer: depart, then arrive.
func _teleport() -> PackedFloat32Array:
	var up := _env(_sweep(0.22, 300.0, 1800.0, 18.0, 0.04), 0.01, 7.0)
	var down := _env(_sweep(0.30, 2200.0, 500.0, 11.0, 0.05), 0.01, 6.0)
	var shimmer := _bell(_highpass(_noise(0.5), 3500.0))
	var buf := _mix(up, down, 0.9, 0.18)
	buf = _mix(buf, shimmer, 0.45, 0.1)
	return _normalize(buf, 0.75)


func _blips(freqs: Array, note: float, total: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_samples(total))
	for i in freqs.size():
		var tone := _env(_sweep(note * 2.2, freqs[i], freqs[i]), 0.003, 16.0)
		out = _mix(out, tone, 1.0, i * note)
	return _normalize(out, 0.7)


func _heal() -> PackedFloat32Array:
	var rise := _sweep(0.5, 380.0, 820.0, 7.0, 0.015)
	rise = _bell(rise)
	var shimmer := _env(_sweep(0.5, 1640.0, 1640.0), 0.05, 5.0)
	return _normalize(_mix(rise, shimmer, 0.25), 0.7)


func _windup() -> PackedFloat32Array:
	var tone := _lowpass(_saw(0.35, 180.0, 460.0), 900.0, 1600.0)
	return _normalize(_bell(tone), 0.5)


func _death() -> PackedFloat32Array:
	var body := _env(_lowpass(_saw(0.55, 240.0, 55.0), 1500.0, 250.0), 0.004, 4.5)
	var puff := _env(_lowpass(_noise(0.55), 3000.0, 300.0), 0.002, 7.0)
	return _normalize(_mix(body, puff, 0.5), 0.8)


func _fanfare() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var notes := [392.0, 523.3, 659.3]
	for i in notes.size():
		var tone := _env(_lowpass(_saw(0.4, notes[i], notes[i]), 2400.0, 2400.0), 0.01, 5.0)
		out = _mix(out, tone, 0.8, i * 0.14)
	for f in [392.0, 523.3, 659.3, 784.0]:
		var chord := _env(_lowpass(_saw(0.5, f, f), 2000.0, 2000.0), 0.02, 3.5)
		out = _mix(out, chord, 0.35, 0.42)
	return _normalize(out, 0.7)


## 12 s seamless loop: every drone frequency completes a whole number of cycles in 12 s.
func _music() -> PackedFloat32Array:
	var seconds := 12.0
	var n := _samples(seconds)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var swell := 0.7 + 0.3 * sin(TAU * t / seconds * 2.0)
		var drone := sin(TAU * 55.0 * t) * 0.5 + sin(TAU * 82.5 * t) * 0.3 \
				+ sin(TAU * 110.0 * t) * 0.25 + sin(TAU * 165.0 * t + 1.3) * 0.08 * swell
		out[i] = drone * swell
	# Soft pulse every 1.5 s (fully decayed before the loop point).
	for beat in 8:
		var thump := _env(_sweep(1.2, 62.0, 40.0), 0.01, 3.2)
		out = _mix(out, thump, 0.55, beat * 1.5)
		out.resize(n)
	return _normalize(out, 0.7)


# --- output ----------------------------------------------------------------

func _write(sfx_name: String, buf: PackedFloat32Array) -> void:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, clampi(roundi(buf[i] * 32767.0), -32768, 32767))

	var header := PackedByteArray()
	header.resize(44)
	header.encode_u32(0, 0x46464952)  # "RIFF"
	header.encode_u32(4, 36 + data.size())
	header.encode_u32(8, 0x45564157)  # "WAVE"
	header.encode_u32(12, 0x20746D66)  # "fmt "
	header.encode_u32(16, 16)
	header.encode_u16(20, 1)  # PCM
	header.encode_u16(22, 1)  # mono
	header.encode_u32(24, RATE)
	header.encode_u32(28, RATE * 2)
	header.encode_u16(32, 2)
	header.encode_u16(34, 16)
	header.encode_u32(36, 0x61746164)  # "data"
	header.encode_u32(40, data.size())

	var file := FileAccess.open(OUT_DIR + sfx_name + ".wav", FileAccess.WRITE)
	if file == null:
		push_error("cannot write %s (error %d)" % [sfx_name, FileAccess.get_open_error()])
		return
	file.store_buffer(header + data)
	file.close()
	print("wrote %s.wav  %.2f s  %d KB" % [sfx_name, float(buf.size()) / RATE, (data.size() + 44) / 1024])


func _boss_slam() -> PackedFloat32Array:
	var thud := _env(_sweep(0.45, 90.0, 38.0, 6.0, 0.02), 0.004, 7.0)
	var crack := _bell(_lowpass(_noise(0.3), 2500.0, 6000.0))
	return _normalize(_mix(thud, crack, 0.5, 0.0), 0.85)


func _boss_charge() -> PackedFloat32Array:
	var rush := _lowpass(_saw(0.6, 70.0, 220.0), 700.0, 1400.0)
	return _normalize(_bell(rush), 0.7)


func _boss_leap() -> PackedFloat32Array:
	var up := _env(_sweep(0.5, 150.0, 700.0, 10.0, 0.03), 0.01, 5.0)
	return _normalize(_mix(up, _bell(_highpass(_noise(0.4), 1500.0)), 0.3, 0.1), 0.7)


func _boss_roar() -> PackedFloat32Array:
	var low := _lowpass(_saw(1.4, 85.0, 60.0), 500.0, 900.0)
	var grit := _lowpass(_noise(1.4), 1200.0, 2200.0)
	return _normalize(_bell(_mix(low, grit, 0.5, 0.0)), 0.8)


func _boss_fire() -> PackedFloat32Array:
	var hiss := _bell(_lowpass(_highpass(_noise(0.9), 800.0), 4500.0, 7000.0))
	return _normalize(hiss, 0.55)


## Dull boot-on-ground tap: low thump plus a short scuff of filtered noise.
func _footstep() -> PackedFloat32Array:
	var thump := _env(_sweep(0.12, 130.0, 60.0, 6.0, 0.01), 0.002, 14.0)
	var scuff := _env(_lowpass(_noise(0.1), 1800.0, 600.0), 0.002, 22.0)
	return _normalize(_mix(thump, scuff, 0.6, 0.0), 0.5)


## Short band-limited hiss burst, like a radio opening its channel.
func _radio_static() -> PackedFloat32Array:
	var hiss := _lowpass(_highpass(_noise(0.22), 1200.0), 4200.0, 3000.0)
	return _normalize(_env(hiss, 0.005, 6.0), 0.5)


## 5 s wind and surf bed. The head is cross-faded with extra noise past the end so the loop point is seamless;
## the tonal hum frequencies complete whole cycles in 5 s.
func _ambience() -> PackedFloat32Array:
	var seconds := 5.0
	var n := _samples(seconds)
	var fade := _samples(0.5)
	var bed := _lowpass(_noise(seconds + 0.5), 700.0, 500.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = bed[i]
	for i in fade:
		var w := float(i) / fade
		out[i] = bed[i] * w + bed[n + i] * (1.0 - w)
	for i in n:
		var t := float(i) / RATE
		var swell := 0.6 + 0.4 * sin(TAU * t / seconds * 2.0)
		out[i] = out[i] * swell + sin(TAU * 44.0 * t) * 0.04 + sin(TAU * 73.0 * t) * 0.03
	return _normalize(out, 0.5)


## Folds the `fade` samples after the loop end into the head, so the loop point has no seam.
func _loop_fold(buf: PackedFloat32Array, n: int, fade: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = buf[i]
	for i in fade:
		var w := float(i) / fade
		out[i] = buf[i] * w + buf[n + i] * (1.0 - w)
	return out


func _gull(duration: float, f0: float, f1: float) -> PackedFloat32Array:
	return _bell(_sweep(duration, f0, f1, 18.0, 0.05))


## 8 s surf, wind and two distant gulls. Swell and gust periods divide the loop length; the gulls sit
## fully inside it, so the loop is seamless.
func _ambience_coast() -> PackedFloat32Array:
	var seconds := 8.0
	var n := _samples(seconds)
	var fade := _samples(0.6)
	var surf := _loop_fold(_lowpass(_noise(seconds + 0.6), 900.0, 700.0), n, fade)
	var foam := _loop_fold(_lowpass(_highpass(_noise(seconds + 0.6), 2500.0), 5200.0, 4200.0), n, fade)
	var wind := _loop_fold(_lowpass(_noise(seconds + 0.6), 380.0, 300.0), n, fade)
	var bed := PackedFloat32Array()
	bed.resize(n)
	for i in n:
		var t := float(i) / RATE
		var swell := pow(0.5 + 0.5 * sin(TAU * t / 4.0 - 1.2), 2.0)
		var gust := 0.6 + 0.4 * sin(TAU * t / 8.0 + 0.7)
		bed[i] = surf[i] * (0.25 + 0.9 * swell) + foam[i] * 0.35 * swell + wind[i] * 0.5 * gust
	var out := _normalize(bed, 0.5)
	out = _mix(out, _gull(0.4, 1500.0, 950.0), 0.15, 2.3)
	out = _mix(out, _gull(0.32, 1300.0, 1000.0), 0.11, 5.6)
	return _normalize(out, 0.5)


func _jungle_call(duration: float, f0: float, f1: float) -> PackedFloat32Array:
	return _lowpass(_bell(_sweep(duration, f0, f1, 6.0, 0.03)), 2600.0, 2600.0)


## 8 s rustle bed, two insect trills and a low drone, with distant calls. Every tone frequency is a whole
## number of Hz, so it completes whole cycles per loop.
func _ambience_jungle() -> PackedFloat32Array:
	var seconds := 8.0
	var n := _samples(seconds)
	var fade := _samples(0.6)
	var rustle := _loop_fold(_lowpass(_noise(seconds + 0.6), 1300.0, 900.0), n, fade)
	var bed := PackedFloat32Array()
	bed.resize(n)
	for i in n:
		var t := float(i) / RATE
		var gate_a := maxf(0.0, sin(TAU * 22.0 * t)) * (0.5 + 0.5 * sin(TAU * 0.5 * t + 1.0))
		var gate_b := maxf(0.0, sin(TAU * 17.0 * t)) * (0.5 + 0.5 * sin(TAU * 0.25 * t + 2.5))
		var insects := sin(TAU * 3600.0 * t) * gate_a * 0.10 + sin(TAU * 4300.0 * t) * gate_b * 0.07
		var swell := 0.5 + 0.5 * (0.5 + 0.5 * sin(TAU * t / 4.0 + 0.3))
		bed[i] = rustle[i] * swell + insects + sin(TAU * 55.0 * t) * 0.03
	var out := _normalize(bed, 0.5)
	out = _mix(out, _jungle_call(0.5, 900.0, 1500.0), 0.16, 1.4)
	out = _mix(out, _jungle_call(0.6, 700.0, 450.0), 0.12, 4.1)
	out = _mix(out, _jungle_call(0.45, 1100.0, 1700.0), 0.14, 6.4)
	return _normalize(out, 0.5)


## 6 s mains hum with harmonics, a vent bed and two relay ticks. 50 Hz and 0.5 Hz divide the loop length.
func _ambience_facility() -> PackedFloat32Array:
	var seconds := 6.0
	var n := _samples(seconds)
	var fade := _samples(0.5)
	var vent := _loop_fold(_lowpass(_highpass(_noise(seconds + 0.5), 180.0), 900.0, 700.0), n, fade)
	var bed := PackedFloat32Array()
	bed.resize(n)
	for i in n:
		var t := float(i) / RATE
		var hum := sin(TAU * 50.0 * t) * 0.5 + sin(TAU * 100.0 * t) * 0.25 + sin(TAU * 150.0 * t) * 0.12 + sin(TAU * 250.0 * t) * 0.05
		hum *= 0.85 + 0.15 * sin(TAU * 0.5 * t)
		var swell := 0.5 + 0.5 * (0.5 + 0.5 * sin(TAU * t / 3.0))
		bed[i] = hum * 0.5 + vent[i] * swell * 0.9
	var out := _normalize(bed, 0.5)
	var tick := _env(_sweep(0.03, 2200.0, 1800.0), 0.001, 90.0)
	out = _mix(out, tick, 0.15, 2.2)
	out = _mix(out, tick, 0.12, 4.7)
	return _normalize(out, 0.5)


## Wing flutter and three chirps: birds bursting out of cover (Blackwood ambush warning cue).
func _bird_flush() -> PackedFloat32Array:
	var flutter := _lowpass(_highpass(_noise(0.9), 600.0), 4500.0, 2500.0)
	for i in flutter.size():
		var t := float(i) / RATE
		flutter[i] *= (0.5 + 0.5 * sin(TAU * 14.0 * t)) * exp(-t * 2.8) * minf(t / 0.03, 1.0)
	var out := _normalize(flutter, 0.5)
	for chirp_at in [0.05, 0.28, 0.5]:
		out = _mix(out, _env(_sweep(0.09, 2400.0, 3400.0, 30.0, 0.02), 0.005, 25.0), 0.35, chirp_at)
	return _normalize(out, 0.6)


## Slow pitch-dropping groan with a scrape: stressed metal.
func _metal_creak() -> PackedFloat32Array:
	var tone := _bell(_lowpass(_saw(1.4, 95.0, 58.0), 700.0, 450.0))
	for i in tone.size():
		tone[i] *= 0.75 + 0.25 * sin(TAU * 9.0 * float(i) / RATE)
	var scrape := _env(_lowpass(_highpass(_noise(1.4), 900.0), 3200.0, 1800.0), 0.1, 2.0)
	return _normalize(_mix(_normalize(tone, 0.6), _normalize(scrape, 0.3), 0.6), 0.6)


## 2.6 s of distant thunder: a short crack, then a low rolling rumble that fades slowly.
func _menu_thunder() -> PackedFloat32Array:
	var seconds := 2.6
	var rumble := _lowpass(_noise(seconds), 260.0, 80.0)
	var shaped := PackedFloat32Array()
	shaped.resize(rumble.size())
	for i in rumble.size():
		var t := float(i) / RATE
		var roll := 0.55 + 0.45 * sin(TAU * t * 5.5 + 0.8)
		shaped[i] = rumble[i] * roll * exp(-t * 1.15) * minf(t * 25.0, 1.0)
	var crack := _env(_highpass(_noise(0.18), 900.0), 0.003, 22.0)
	return _normalize(_mix(shaped, crack, 0.45, 0.0), 0.7)


## 8 s loop: a low wind bed with slow gusts (seamless: the tail is folded into the head).
func _menu_wind() -> PackedFloat32Array:
	var seconds := 8.0
	var n := _samples(seconds)
	var fade := _samples(0.6)
	var low := _loop_fold(_lowpass(_noise(seconds + 0.6), 320.0, 260.0), n, fade)
	var hiss := _loop_fold(_lowpass(_highpass(_noise(seconds + 0.6), 700.0), 1800.0, 1400.0), n, fade)
	var bed := PackedFloat32Array()
	bed.resize(n)
	for i in n:
		var t := float(i) / RATE
		var gust := 0.55 + 0.45 * sin(TAU * t / 8.0 + 0.4)
		var gust2 := 0.5 + 0.5 * sin(TAU * t / 4.0 + 1.7)
		bed[i] = low[i] * (0.5 + 0.7 * gust) + hiss[i] * 0.35 * gust2
	return _normalize(bed, 0.5)


## 8 s loop of a heavy swell: two big surges per loop with foam on the crest.
func _menu_waves() -> PackedFloat32Array:
	var seconds := 8.0
	var n := _samples(seconds)
	var fade := _samples(0.6)
	var surf := _loop_fold(_lowpass(_noise(seconds + 0.6), 700.0, 520.0), n, fade)
	var foam := _loop_fold(_lowpass(_highpass(_noise(seconds + 0.6), 2200.0), 4800.0, 3800.0), n, fade)
	var bed := PackedFloat32Array()
	bed.resize(n)
	for i in n:
		var t := float(i) / RATE
		var swell := pow(0.5 + 0.5 * sin(TAU * t / 4.0 - 1.0), 2.4)
		bed[i] = surf[i] * (0.2 + 1.0 * swell) + foam[i] * 0.4 * swell
	return _normalize(bed, 0.55)
