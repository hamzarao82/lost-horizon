extends SceneTree
## Numeric sanity for the generated opening-arc sounds and the four loops that were shortened. Nobody has
## listened to these; this only proves they are not clipped, not silent, have no DC offset, loop without a jump,
## last as long as intended and carry their energy in the intended band.
## godot --headless --path . -s tests/sound_sanity_check.gd

const RATE: float = 22050.0
const FFT_N: int = 4096

## name -> [loop, min_seconds, max_seconds, centroid_min_hz, centroid_max_hz, rms_min, rms_max]
const SPECS: Dictionary = {
	"boat_engine": [true, 1.9, 2.1, 80.0, 900.0, 0.05, 0.35],
	"rain_loop": [true, 1.9, 2.1, 1500.0, 6500.0, 0.05, 0.35],
	"storm_impact": [false, 0.7, 1.0, 50.0, 2500.0, 0.04, 0.5],
	"machinery_hum": [true, 1.9, 2.1, 60.0, 1500.0, 0.05, 0.35],
	"fence_rattle": [false, 0.6, 0.8, 1500.0, 7500.0, 0.03, 0.4],
	"guard_murmur": [false, 1.3, 1.5, 300.0, 2600.0, 0.03, 0.4],
	"ranged_windup": [false, 0.2, 0.25, 500.0, 2800.0, 0.03, 0.5],
	"ambience_trail": [true, 2.9, 3.1, 1500.0, 5500.0, 0.03, 0.35],
	"ambience_coast": [true, 3.9, 4.1, 100.0, 5000.0, 0.03, 0.35],
	"ambience_jungle": [true, 3.9, 4.1, 100.0, 5000.0, 0.03, 0.35],
	"menu_wind": [true, 3.9, 4.1, 100.0, 3000.0, 0.03, 0.35],
	"menu_waves": [true, 3.9, 4.1, 100.0, 4500.0, 0.03, 0.4],  # foam layer is bright by design (4.8 kHz cutoff)
}

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _samples(sound: String) -> PackedFloat32Array:
	var bytes := FileAccess.get_file_as_bytes("res://assets/audio/%s.wav" % sound)
	var count := (bytes.size() - 44) / 2
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		out[i] = bytes.decode_s16(44 + i * 2) / 32768.0
	return out


func _centroid(samples: PackedFloat32Array) -> float:
	var n := FFT_N
	if samples.size() < n:
		n = 1024
	var start := maxi(0, (samples.size() - n) / 2)
	var re: Array[float] = []
	var im: Array[float] = []
	re.resize(n)
	im.resize(n)
	for i in n:
		var w := 0.5 - 0.5 * cos(TAU * i / (n - 1))
		re[i] = samples[start + i] * w
		im[i] = 0.0
	var j := 0
	for i in range(1, n):
		var bit := n >> 1
		while j & bit:
			j ^= bit
			bit >>= 1
		j ^= bit
		if i < j:
			var tr := re[i]
			re[i] = re[j]
			re[j] = tr
	var length := 2
	while length <= n:
		var ang := -TAU / length
		for i in range(0, n, length):
			for k in length / 2:
				var wr := cos(ang * k)
				var wi := sin(ang * k)
				var a := i + k
				var b := i + k + length / 2
				var xr := re[b] * wr - im[b] * wi
				var xi := re[b] * wi + im[b] * wr
				re[b] = re[a] - xr
				im[b] = im[a] - xi
				re[a] += xr
				im[a] += xi
		length <<= 1
	var weighted := 0.0
	var total := 0.0
	for k in range(1, n / 2):
		var mag := sqrt(re[k] * re[k] + im[k] * im[k])
		weighted += mag * k * RATE / n
		total += mag
	return weighted / maxf(total, 0.000001)


func _run() -> void:
	for sound: String in SPECS:
		var spec: Array = SPECS[sound]
		var s := _samples(sound)
		var seconds := float(s.size()) / RATE
		var peak := 0.0
		var sum := 0.0
		var sq := 0.0
		var step := 0.0
		for i in s.size():
			peak = maxf(peak, absf(s[i]))
			sum += s[i]
			sq += s[i] * s[i]
			if i > 0:
				step += absf(s[i] - s[i - 1])
		var rms := sqrt(sq / maxf(s.size(), 1))
		var dc := absf(sum / maxf(s.size(), 1))
		var mean_step := step / maxf(s.size() - 1, 1)
		var seam := absf(s[s.size() - 1] - s[0])
		var centroid := _centroid(s)
		print("%s: %.2f s peak %.3f rms %.3f dc %.4f seam %.3f (mean step %.3f) centroid %.0f Hz" % [sound, seconds, peak, rms, dc, seam, mean_step, centroid])
		_check(seconds >= float(spec[1]) and seconds <= float(spec[2]), "%s lasts %.2f s (%.1f to %.1f)" % [sound, seconds, spec[1], spec[2]])
		_check(peak < 0.99 and peak > 0.2, "%s is not clipped and not quiet (peak %.3f)" % [sound, peak])
		_check(rms >= float(spec[5]) and rms <= float(spec[6]), "%s has a sane level (rms %.3f)" % [sound, rms])
		_check(dc < 0.02, "%s has no DC offset (%.4f)" % [sound, dc])
		_check(centroid >= float(spec[3]) and centroid <= float(spec[4]), "%s sits in its intended band (centroid %.0f Hz)" % [sound, centroid])
		if bool(spec[0]):
			_check(seam < 0.05, "%s loop seam below 0.05 (first and last samples differ by %.3f)" % [sound, seam])
	print("sound_sanity_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
