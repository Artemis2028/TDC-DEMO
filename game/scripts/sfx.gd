class_name Sfx
extends Node
## Sound effects, all synthesised here at start-up: no sound files, so nothing to license.
## Space carries no sound, so everything is what the crew would hear through the hull: the coilgun's thump and
## ring, the laser's hum, rounds striking the hull, the enemy beam sizzling on the armour, alarms, the drive.

const RATE := 22050

var _clips := {}            # name -> AudioStreamWAV
var _loops := {}            # name -> AudioStreamPlayer
var _pool: Array = []       # one-shot players
var _last := {}             # name -> time last played (ms), to keep fast time from machine-gunning a sound
var muted := false

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2300          # same sounds every run
	_clips["coil"] = _wav(_fade(_coilgun(rng)))
	_clips["hit"] = _wav(_fade(_hull_hit(rng)))
	_clips["charge"] = _wav(_charge())
	_clips["alarm"] = _wav(_alarm())
	_clips["klaxon"] = _wav(_klaxon())
	for n in ["laser", "sizzle", "drive", "oms"]:
		var data: PackedFloat32Array
		match n:
			"laser": data = _laser_loop(rng)
			"sizzle": data = _sizzle_loop(rng)
			"drive": data = _drive_loop(rng)
			"oms": data = _oms_loop(rng)
		data = _seamless(data)
		var w := _wav(data)
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size()
		var p := AudioStreamPlayer.new()
		p.stream = w
		p.volume_db = -80
		add_child(p)
		_loops[n] = p
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)

## Play a one-shot. Pitch varies a little each time so repeats don't sound copied.
func play(name: String, volume_db := 0.0, pitch_spread := 0.08) -> void:
	if muted or not _clips.has(name): return
	var now := Time.get_ticks_msec()
	if now - int(_last.get(name, -1000)) < 120: return
	_last[name] = now
	for p: AudioStreamPlayer in _pool:
		if not p.playing:
			p.stream = _clips[name]
			p.volume_db = volume_db
			p.pitch_scale = 1.0 + randf_range(-pitch_spread, pitch_spread)
			p.play()
			return

## Keep a loop running at a level (0 = off), fading so it never clicks on or off.
func loop(name: String, level: float, delta: float) -> void:
	var p: AudioStreamPlayer = _loops[name]
	var target := -80.0 if muted or level <= 0.001 else linear_to_db(level)
	if target > -79 and not p.playing: p.play()
	p.volume_db = move_toward(p.volume_db, target, delta * 120.0)
	if p.volume_db <= -79.5 and p.playing: p.stop()

## Write every sound to WAV files (for listening outside the game).
func dump(dir: String) -> void:
	for n in _clips: (_clips[n] as AudioStreamWAV).save_to_wav(dir.path_join(n + ".wav"))
	for n in _loops: ((_loops[n] as AudioStreamPlayer).stream as AudioStreamWAV).save_to_wav(dir.path_join(n + "_loop.wav"))

func stop_loops() -> void:
	for p: AudioStreamPlayer in _loops.values():
		p.volume_db = -80
		p.stop()

# ------------------------------------------------------------------ synthesis

## Fade the last 0.2 s of a one-shot to silence.
func _fade(data: PackedFloat32Array) -> PackedFloat32Array:
	var n := int(0.2 * RATE)
	for i in n:
		data[data.size() - 1 - i] *= float(i) / n
	return data

## Loops are synthesised 1.2 s long; the first 0.2 s is cross-faded with the last 0.2 s so the 1 s loop has no seam.
func _seamless(data: PackedFloat32Array) -> PackedFloat32Array:
	var n := int(0.2 * RATE)
	var loop_len := data.size() - n
	var out := data.slice(0, loop_len)
	for i in n:
		var k := float(i) / n
		out[i] = data[i] * k + data[loop_len + i] * (1.0 - k)
	return out

func _wav(data: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0
	for v in data: peak = maxf(peak, absf(v))
	if peak > 0.89:                    # keep headroom: never clip
		for i in data.size(): data[i] *= 0.89 / peak
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w

func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b

## Coilgun shot heard from inside: a click as the coils dump, a deep falling thump, a metallic ring in the frame.
func _coilgun(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(1.4)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 32.0 + 60.0 * exp(-t / 0.08)
		ph += TAU * f / RATE
		var thump := sin(ph) * exp(-t / 0.28) * 0.9
		var click := (rng.randf() * 2 - 1) * exp(-t / 0.006) * 0.8
		var ring := (sin(TAU * 311 * t) + 0.7 * sin(TAU * 523 * t) + 0.5 * sin(TAU * 887 * t)) * exp(-t / 0.4) * 0.12
		var stages := 0.0
		for k in 6:                         # the coil stages firing one after another
			var tk := t - k * 0.004
			if tk > 0: stages += sin(TAU * 1800 * tk) * exp(-tk / 0.003) * 0.15
		b[i] = thump + click + ring + stages
	return b

## A round striking the hull: a hard noisy bang, a low knock and the plating ringing on.
func _hull_hit(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(1.6)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += ((rng.randf() * 2 - 1) - lp) * 0.25          # one-pole low-pass on the noise
		var bang := lp * exp(-t / 0.12) * 1.6
		var knock := sin(TAU * 52 * t) * exp(-t / 0.3) * 0.7
		var ring := (sin(TAU * 183 * t) + 0.8 * sin(TAU * 412 * t) + 0.6 * sin(TAU * 691 * t) + 0.3 * sin(TAU * 1307 * t)) * exp(-t / 0.55) * 0.13
		b[i] = bang + knock + ring
	return b

## Laser coming up to power: a short, low rising swell (capacitors charging), not a whine.
func _charge() -> PackedFloat32Array:
	var b := _buf(0.35)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += TAU * (60.0 + 160.0 * t / 0.35) / RATE
		b[i] = (sin(ph) + 0.3 * sin(2 * ph)) * 0.3 * minf(1.0, t / 0.05) * (1.0 - t / 0.35)
	return b

## The laser firing, felt through the frame rather than heard: a deep power-plant thrum (55 and 56 Hz beating
## once a second) with soft overtones, and the coolant rushing (low-passed noise) swelling with a slow pulse.
## No high tones: an earlier version with a 3 kHz whine sounded like a dentist's drill.
func _laser_loop(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(1.2)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		# 110 and 165 Hz carry the thrum on laptop speakers, which can't reproduce 55 Hz
		var thrum := sin(TAU * 55 * t) * 0.35 + sin(TAU * 56 * t) * 0.25 + sin(TAU * 110 * t) * 0.25 + sin(TAU * 165 * t) * 0.12 + sin(TAU * 220 * t) * 0.04
		var pulse := 0.8 + 0.2 * sin(TAU * 4 * t)
		lp += ((rng.randf() * 2 - 1) - lp) * 0.03
		lp2 += (lp - lp2) * 0.08
		b[i] = (thrum * pulse + lp2 * 3.0) * 0.6
	return b

## The enemy beam on our armour: crackle and sizzle.
func _sizzle_loop(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(1.2)
	var hp := 0.0
	var prev := 0.0
	for i in b.size():
		var n := rng.randf() * 2 - 1
		hp = 0.7 * (hp + n - prev)            # high-pass: hiss
		prev = n
		var crack := (rng.randf() * 2 - 1) * (1.0 if rng.randf() < 0.004 else 0.0) * 3.0
		b[i] = hp * 0.18 + crack * 0.3
	return b

## Main drive: a deep rumble through the frame.
func _drive_loop(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(1.2)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += ((rng.randf() * 2 - 1) - lp) * 0.02
		lp2 += (lp - lp2) * 0.05
		b[i] = lp2 * 6.0 + sin(TAU * 41 * t) * 0.25
	return b

## OMS thrusters: a soft pulsing hiss.
func _oms_loop(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(1.2)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += ((rng.randf() * 2 - 1) - lp) * 0.3
		b[i] = lp * 0.35 * (0.75 + 0.25 * sin(TAU * 12 * t))
	return b

## System knocked out: two falling tones, twice.
func _alarm() -> PackedFloat32Array:
	var b := _buf(0.8)
	for i in b.size():
		var t := float(i) / RATE
		var slot := int(t / 0.2)
		var f := 880.0 if slot % 2 == 0 else 660.0
		var local := fmod(t, 0.2)
		var env := minf(1.0, local / 0.01) * minf(1.0, (0.2 - local) / 0.02)
		b[i] = (sin(TAU * f * t) + 0.3 * sin(TAU * f * 3 * t)) * 0.22 * env
	return b

## Overheat klaxon: a buzzing rising tone.
func _klaxon() -> PackedFloat32Array:
	var b := _buf(0.9)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += TAU * (380.0 + 120.0 * t) / RATE
		var saw := fmod(ph / TAU, 1.0) * 2 - 1
		var env := minf(1.0, t / 0.03) * minf(1.0, (0.9 - t) / 0.1)
		b[i] = saw * 0.18 * env
	return b
