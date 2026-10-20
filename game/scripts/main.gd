extends Node3D
## TDC demo: one battle above Mars. All rules run in the compiled DemoBattle; this script only draws and sends orders.
## The HUD follows the CIC flight-deck layout. Features that are not in the demo are drawn with a red X and do nothing.

const PATREON_URL := "https://www.patreon.com/c/BlackBody1"
const SPEED_NAMES := ["II", "½×", "1×", "2×", "5×", "10×", "CRZ"]
const SYS_NAMES := ["Drive", "Laser", "Gun", "Sensors", "Radiators", "Crew"]
const SYS_ABBR := ["DRV", "LSR", "GUN", "SNS", "RAD", "CRW"]
const PRESET_VERB := ["Disable", "Disarm", "Silence", "Blind", "Cook", "Kill"]
## Target select grid: [system, turret (-1 any), label, preset verb]
## One cell per kind of target, however many of it the enemy carries. Clicking a weapon kind again cycles through
## the individual mounts (any → 1 → 2 → 3 → any), so the grid never grows with the enemy's loadout.
const TARGETS := [[0, -1, "DRV", "Disable"], [1, -1, "LSR", "Disarm"], [2, -1, "GUN", "Silence"],
	[3, -1, "SNS", "Blind"], [4, -1, "RAD", "Cook"], [5, -1, "CRW", "Kill"]]
const MARS_R := 3389.5e3
const ALT := 650e3          # display orbit height, chosen so the planet's limb shows as an arc
const VP := Rect2(312, 72, 804, 684)

var battle: DemoBattle
var ship_class := 0
var state := "menu"
var ev_index := 0
var log_lines: Array = []   # [text, clock]

# 3D
var view_vp: SubViewport
var cam: Camera3D
var own_model: ShipModel
var foe_model: ShipModel
var eo_model: ShipModel          # the enemy again, in the sensor viewport's own world, so that feed casts no shadows
var planet: MeshInstance3D
var alerts: Control
var shot_vis: Array = []          # gun rounds in flight this frame: [world position, direction, colour], for the tracer
var popups: Array = []            # hit callouts over the ships: [ship 0/1, headline, detail, colour, real time made, battle time]
var sun: DirectionalLight3D
var fps_meter: FpsMeter
var _warm_vp: SubViewport
## Last tick's heading and roll, so the draw can move between the 10 Hz steps instead of jumping.
var _ex_h := [0.0, 0.0]
var _ex_roll := [0.0, 0.0]
var _ex_ready := false
var beam_vis: Array = []         # lasers firing this frame: [emitter world position, hot spot world position, colour]
var fc_lines := true             # B: show the fire-control lines (a HUD aid; the beams themselves are invisible)
var laser_beams := false         # L: also draw the beams. Off by default; a beam in vacuum is not visible from the side
var yaw := 0.9
var pitch := 0.42
var dist := 320.0
var dragging := false
var view_target := false
var chase := false
var armor_view := false
var roll_angle := 0.0
var hdg_angle := 0.0          # heading drawn this frame (between sim ticks), for the attitude ball
var foe_roll := 0.0

# EO sensor
var eo_vp: SubViewport
var eo_cam: Camera3D

# player-side UI state
var sel_burn := 1           # burn direction picked on the helm (1 close, 2 open, 3 left, 4 right, 5 match)
var preset_mode := false
var throttle := 1.0
var last_heat := 0.0
var last_time := 0.0
var heat_rate := 0.0
var dc_line_sys: Array = []

# Panels, the view frame and the menu are their own scripts. The host keeps the handles it still
# reads while the battle is moving: the panel root, the 3D view, and where a click landed.
const _BattleHud = preload("res://scripts/battle_hud.gd")
const _BattleMenu = preload("res://scripts/battle_menu.gd")
var hud_ui
var menu_ui
var hud: Control
var menu: Control
var end_screen: Control
var scope_rect := Rect2()
var bracket_pos := Vector2(-999, -999)
var pick_points: Array = []   # enemy components on screen this frame: [position in the view, system, turret, label]
var sfx: Sfx
var was_lasing := false

# capture mode: --shot path --at seconds [--class n] [--target] [--armor] [--menu] [--hold] [--preset]
var shot_path := ""
var shot_at := 0.0
var shot_frames := 0
var S0: Dictionary = {}        # this frame's view of our ship, the enemy and the rounds in flight (see _snap)
var S1: Dictionary = {}
var SHOTS: Array = []
var snap_time := -1.0
var snap_dirty := true
var own_name_s := "Dagger"
var foe_name_s := ""
const SCEN_NAMES := ["Random", "Head-on", "Crossing", "Stern chase"]
## How the enemy captain fought, for the end screen (Personality order: brawler, kiter, broadsider).
const STYLE_NAMES := ["a brawler: closed to knife range and slugged it out",
	"a kiter: held the range and backed off when you pressed",
	"a broadsider: turned side-on to bring every turret to bear, rolling to spread the damage"]
var scenario_pick := -1          # menu choice for the next battle; -1 random
var resumable := false          # a battle the player left with Esc, unfinished and waiting
var read_calls := {}             # crew observations of the enemy's manoeuvres already made this battle (see _read_enemy)
var tplot: TacticalPlot          # V / PLOT: top-down engagement plot over the 3D view
var aar: AAR                     # after-action recorder for the battle in progress
var aar_view: AARView
var settings_panel: SettingsPanel
var briefing: Briefing
var _brief_paused := false
var hud_dirty := true
var alerts_shown := true
var bench_frames := 0          # --bench N: frames to measure after a 60-frame warm-up
var bench_n := 0
var bench_sum := {}
var bench_times: Array[float] = []   # frame times (ms) over the measured window, for stutter
var shot_clicks: Array = []   # --click x,y (repeatable): synthetic clicks for checking the HUD wiring headless

func _ready() -> void:
	RenderingServer.set_default_clear_color(W.BG)
	# Saved settings: volume, window mode, frame cap, vsync, fire-control lines, briefing. Unlimited is
	# vsync off and no cap. A numeric cap below the display refresh also turns vsync off so frames are not dropped.
	Settings.load_and_apply()
	fc_lines = Settings.fc_lines
	laser_beams = Settings.laser_beams
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	fps_meter = FpsMeter.new()
	fps_meter.visible = Settings.show_fps
	layer.add_child(fps_meter)
	if OS.get_cmdline_user_args().has("--beams"): laser_beams = true
	DisplayServer.window_set_title("TDC Demo " + Version.text())
	sfx = Sfx.new()
	add_child(sfx)
	if OS.get_cmdline_user_args().has("--dump-sfx"):
		var dir: String = OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--dump-sfx") + 1]
		sfx.dump(dir)
		get_tree().quit()
		return
	_build_world()
	hud_ui = _BattleHud.new()
	hud_ui.name = "BattleHud"
	hud_ui.host = self
	add_child(hud_ui)
	hud_ui.build()
	menu_ui = _BattleMenu.new()
	menu_ui.name = "BattleMenu"
	menu_ui.host = self
	add_child(menu_ui)
	menu_ui.build()
	menu_ui.build_end()
	settings_panel = SettingsPanel.create(self)
	briefing = Briefing.create(self)
	settings_panel.briefing = briefing
	settings_panel.sfx = sfx
	settings_panel.extra_provider = _log_extras
	briefing.closed.connect(func():
		if _brief_paused and battle != null:
			_brief_paused = false
			battle.set_speed(2))
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		match args[i]:
			"--shot": shot_path = args[i + 1]
			"--at": shot_at = float(args[i + 1])
			"--class": ship_class = int(args[i + 1])
			"--target": view_target = true
			"--armor": armor_view = true
			"--dist": dist = float(args[i + 1])
			"--yaw": yaw = float(args[i + 1])
			"--pitch": pitch = float(args[i + 1])
			"--click":
				var xy: PackedStringArray = args[i + 1].split(",")
				shot_clicks.append(Vector2(float(xy[0]), float(xy[1])))
	if args.has("--bench"):                # headless profiling: play N frames of a live battle, print the costs, quit
		bench_frames = int(args[args.find("--bench") + 1])
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		scenario_pick = _arg_int(args, "--scenario", 0)
		_start(ship_class)
		battle.set_speed(int(args[args.find("--speed") + 1]) if args.has("--speed") else 2)
		return
	if shot_path != "" and not args.has("--menu"):
		_start(ship_class)
		if args.has("--hold"): battle.set_weapons_free(false)
		if args.has("--preset"): _set_mode(1)
		if args.has("--broadside"): battle.set_facing(1)
		if args.has("--roll"): battle.set_roll(1)
		if args.has("--plot"): _toggle_plot()
		if args.has("--marks"):            # screenshots: show a degraded and a killed mark
			battle.set_mark(0, -1, 1)
			battle.set_mark(3, -1, 2)
		if args.has("--burn"):
			throttle = float(args[args.find("--throttle") + 1]) if args.has("--throttle") else 1.0
			battle.set_burn(int(args[args.find("--burn") + 1]), throttle)
		if args.has("--oms"):
			battle.set_oms_strafe(int(args[args.find("--oms") + 1]))
		if args.has("--rad"):
			battle.set_radiators(int(args[args.find("--rad") + 1]) != 0)
		while battle.get_time() < shot_at and battle.get_winner() < 0:
			battle.advance(1.0)
			_track_heat()
			if args.has("--aar"):        # feed the after-action recorder as a live battle would
				_snap()
				_drain_events()
		battle.set_speed(0)
		# _start snapped the ships before these orders. A paused still never moves the clock, so without
		# this the first frame would still show the pre-order radiators, burn and strafe.
		snap_dirty = true
		_drain_events()
	else:
		menu_ui.show()

# ------------------------------------------------------------------ world

func _build_world() -> void:
	var env := Environment.new()
	# A star sky around the whole scene: the background, and something for glowing exhaust to add onto
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var skymat := PanoramaSkyMaterial.new()
	skymat.panorama = _star_panorama()
	sky.sky_material = skymat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.33, 0.4)
	env.ambient_light_energy = 0.32
	# Metal hull reflects the sky (stars, black) rather than a flat grey, so it reads as polished plate.
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX     # same view transform as the Blender renders
	# Ambient occlusion: darkens creases where housings, rings and pods meet the hull (radius in metres).
	env.ssao_enabled = true
	env.ssao_radius = 3.0
	env.ssao_intensity = 2.5
	env.ssao_power = 1.6
	env.ssao_detail = 0.5
	# Bloom on anything brighter than white: drive plume, laser hot spots, hot radiators, lit muzzles.
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.6
	env.glow_intensity = 0.5
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for lv in 7: env.set_glow_level(lv, lv in [2, 3, 4])
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_energy = 2.2
	sun.light_color = Color(1, 0.95, 0.88)
	# Hard sunlight casts real shadows: radiator wings across the spine, housings on the hull.
	# Performance: hard edges (angular distance 0) skip the soft-shadow blocker search on every lit pixel, and the
	# cascades don't blend (each pixel samples one map, not two). From Mars orbit the Sun is only 0.35 deg across,
	# so its shadows are nearly hard anyway. Four cascades stay: with two, the thin radiator wings leak light
	# through their seams at close range (checked side by side).
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = false
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.light_angular_distance = 0.0
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, Vector3(-0.8, -0.25, 0.6), Vector3.UP)
	planet = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = MARS_R
	sm.height = MARS_R * 2
	sm.radial_segments = 192
	sm.rings = 96
	planet.mesh = sm
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.46, 0.2, 0.09)
	mm.roughness = 1.0
	planet.material_override = mm
	planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # it never shades the ships in view
	planet.layers = 4          # the fill light below skips the planet so its night side stays dark
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.25
	fill.light_color = Color(0.75, 0.82, 0.95)
	fill.light_cull_mask = 1 | 2
	add_child(fill)
	fill.look_at_from_position(Vector3.ZERO, Vector3(0.6, -0.5, -0.7), Vector3.UP)
	# Mars-shine: the sunlit planet below lights the belly a faint rust colour.
	var shine := DirectionalLight3D.new()
	shine.light_energy = 0.35
	shine.light_color = Color(0.85, 0.45, 0.25)
	shine.light_cull_mask = 1 | 2
	add_child(shine)
	shine.look_at_from_position(Vector3.ZERO, Vector3(0.15, 1.0, 0.1), Vector3.FORWARD)
	add_child(planet)
	# EO sensor: its own world and camera, rendered small and blown up, so poor quality shows as big pixels.
	# Sharing the battle world made every refresh draw the sun's four shadow cascades again. On a fast machine
	# that hitch landed 15 times a second; drawing it every frame removed the hitch by making every frame pay
	# for two shadow passes. This feed is a second, unshadowed copy of the enemy instead.
	eo_vp = SubViewport.new()
	eo_vp.size = Vector2i(64, 64)
	eo_vp.own_world_3d = true
	eo_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	eo_vp.positional_shadow_atlas_size = 0
	for lit in [[2.2, Color(1, 0.95, 0.88), Vector3(-0.8, -0.25, 0.6)],
			[0.25, Color(0.75, 0.82, 0.95), Vector3(0.6, -0.5, -0.7)],
			[0.35, Color(0.85, 0.45, 0.25), Vector3(0.15, 1.0, 0.1)]]:
		var lamp := DirectionalLight3D.new()
		lamp.light_energy = lit[0]
		lamp.light_color = lit[1]
		lamp.shadow_enabled = false
		eo_vp.add_child(lamp)
		lamp.look_at_from_position(Vector3.ZERO, lit[2], Vector3.UP if absf(lit[2].y) < 0.9 else Vector3.FORWARD)
	eo_cam = Camera3D.new()
	eo_cam.fov = 4.0
	eo_cam.near = 10.0
	eo_cam.far = 9.0e6
	# The EO view renders as small as 12 x 12 pixels. Bloom and ambient occlusion build chains of smaller and smaller
	# images that cannot fit that, and on some GPUs (AMD Radeon 8060S) that crashed the game. The sensor view gets the
	# same sky and tone mapping without them.
	var eo_env: Environment = env.duplicate()
	eo_env.glow_enabled = false
	eo_env.ssao_enabled = false
	eo_cam.environment = eo_env
	eo_vp.add_child(eo_cam)
	add_child(eo_vp)
	_warm_pipelines(env)

## Draw the effect materials once before the player can fire or ignite, so that first use does not compile a
## shader in the middle of the fight. Same 4x MSAA, glow and ambient occlusion as the battle view.
func _warm_pipelines(env: Environment) -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--shot") or args.has("--bench"): return
	# Large enough for the glow mip chain (levels 2–4) and SSAO. A 16 px view cannot build those and, on some
	# GPUs, used to crash. One frame here compiles the battle's materials before the first shot or burn.
	var vp := SubViewport.new()
	vp.name = "ShaderWarm"
	vp.size = Vector2i(256, 256)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var light := DirectionalLight3D.new()
	light.shadow_enabled = true
	vp.add_child(light)
	var warm_cam := Camera3D.new()
	warm_cam.environment = env
	vp.add_child(warm_cam)
	# Dagger, Lance, Mars: whichever the player flies, the first frame of a fight is not a compile hitch.
	for spec in [[false, 0], [false, 2], [true, 1]]:
		var ship := ShipModel.new()
		ship.build(spec[0], spec[1])
		vp.add_child(ship)
		ship.expose_for_warmup()
	warm_cam.position = Vector3(0, 40, 220)
	warm_cam.look_at(Vector3.ZERO)
	add_child(vp)
	_warm_vp = vp

## Equirectangular star field: a few thousand faint points, a handful bright, slightly warm or cool. Same every run.
static func _star_panorama() -> ImageTexture:
	var w := 4096
	var h := 2048
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.006, 0.008, 0.013))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2300
	for i in 6000:
		var x := rng.randi_range(0, w - 1)
		# uniform over the sphere: pick the row by the sine of latitude
		var y := int((acos(rng.randf_range(-1.0, 1.0)) / PI) * (h - 1))
		var b := pow(rng.randf(), 6.0) * 0.9 + 0.08
		var tint := Color(1.0, 0.92, 0.82) if rng.randf() < 0.3 else (Color(0.82, 0.9, 1.0) if rng.randf() < 0.5 else Color.WHITE)
		img.set_pixel(x, y, tint * b)
		if b > 0.5:                                  # the brightest few get a small halo
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q := Vector2i(x, y) + d
				if q.x >= 0 and q.x < w and q.y >= 0 and q.y < h:
					img.set_pixel(q.x, q.y, tint * b * 0.35)
	# A small sun in the directional light's direction. The panorama is what metal reflects, and a
	# starfield alone leaves the copper mirrors black. Peak is 1.0, under the bloom threshold.
	var sun := Vector3(0.776, 0.242, -0.582).normalized()
	var sun_u := atan2(sun.x, -sun.z)
	if sun_u < 0.0: sun_u += TAU
	sun_u /= TAU
	var sun_v := acos(clampf(sun.y, -1.0, 1.0)) / PI
	var sun_px := Vector2(sun_u * (w - 1), sun_v * (h - 1))
	var rad := 70.0
	for y in range(int(sun_px.y) - int(rad), int(sun_px.y) + int(rad) + 1):
		if y < 0 or y >= h: continue
		for x in range(int(sun_px.x) - int(rad), int(sun_px.x) + int(rad) + 1):
			if x < 0 or x >= w: continue
			var d := Vector2(x, y).distance_to(sun_px) / rad
			if d >= 1.0: continue
			var g := pow(1.0 - d, 2.0)
			var warm := Color(1.0, 0.93, 0.78) * g
			var had := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(maxf(had.r, warm.r), maxf(had.g, warm.g), maxf(had.b, warm.b)))
	return ImageTexture.create_from_image(img)

func _spawn_models() -> void:
	for m in [own_model, foe_model]:
		if m: m.queue_free()
	var own: Dictionary = battle.get_ship(0)
	var foe: Dictionary = battle.get_ship(1)
	own_model = ShipModel.new()
	own_model.build(false, int(own["gun"]))
	add_child(own_model)
	foe_model = ShipModel.new()
	foe_model.build(true, int(foe["gun"]))
	add_child(foe_model)
	if eo_model: eo_model.queue_free()
	eo_model = ShipModel.new()
	eo_model.build(true, int(foe["gun"]))
	eo_vp.add_child(eo_model)
	_ex_ready = false

# ------------------------------------------------------------------ battle flow

## The integer after a command-line flag, or fallback when the flag or its value is missing.
static func _arg_int(args: PackedStringArray, flag: String, fallback: int) -> int:
	var i := args.find(flag)
	return int(args[i + 1]) if i >= 0 and i + 1 < args.size() else fallback

func _start(cls: int, brief := true) -> void:
	ship_class = cls
	resumable = false                # a new battle replaces any one left waiting
	menu_ui.resume_btn.visible = false
	battle = DemoBattle.new()
	# Screenshots use a fixed seed and today's head-on brawler unless --scenario / --personality say otherwise.
	var sargs := OS.get_cmdline_user_args()
	var scen := scenario_pick if shot_path == "" else _arg_int(sargs, "--scenario", 0)
	var pers := -1 if shot_path == "" else _arg_int(sargs, "--personality", 0)
	battle.start(int(Time.get_unix_time_from_system()) if shot_path == "" else 7, cls, scen, pers)
	read_calls.clear()
	battle.set_speed(2)
	ev_index = 0
	log_lines.clear()
	# first teletype line: where the contact is (fits the 24-character line)
	log_lines.append([["Contact dead ahead", "Contact crossing bow", "Contact dead astern"][battle.get_scenario()], _clock(0), false, 0.0])
	preset_mode = false
	sel_burn = 1
	throttle = 1.0
	last_heat = 0.0
	last_time = 0.0
	heat_rate = 0.0
	_spawn_models()
	snap_dirty = true
	_snap()
	# The coilgun Earth's displayed name. The sim still calls that class Lance; Dagger and Mars keep their names.
	own_name_s = "UEN Second Opinion" if cls == 1 else "ESF " + str(S0["name"])
	hud_ui.plate_hull = -1
	foe_name_s = "MRS " + str(S1["name"]).to_upper().replace("MARS ", "")
	state = "battle"
	menu.visible = false
	end_screen.visible = false
	hud.visible = true
	tplot.reset()
	aar = AAR.new()
	fc_lines = Settings.fc_lines
	laser_beams = Settings.laser_beams or OS.get_cmdline_user_args().has("--beams")
	if brief and shot_path == "" and bench_frames == 0 and Briefing.wanted():
		battle.set_speed(0)          # the first battle waits while the briefing is up
		_brief_paused = true
		briefing.open()

func _drain_events() -> void:
	var evs: Array = battle.get_events(ev_index)
	if aar and not aar.done:
		aar.record(S0, S1, battle.get_time(), battle.get_range_km(), evs)
	for e in evs:
		_event_sound(e)
		_popup(e)
		if str(e["kind"]) == "fire":          # gun fired: coils and muzzle light up on whichever ship fired
			var m: ShipModel = own_model if int(e["ship"]) == 0 else foe_model
			if m: m.fire_gun()
		var kind := str(e["kind"])
		var ship := int(e["ship"])
		if kind == "assess" and ship == 0:
			# our crew's call on the enemy: only ever "probable", and sometimes wrong
			log_lines.append([str(e["text"]), _clock(float(e["time"])), true, float(e["time"])])
		elif kind == "out" or (ship == 0 and ["hit", "burn-through", "disabled", "overheat"].has(kind)):
			log_lines.append([str(e["text"]), _clock(float(e["time"])), false, float(e["time"])])
	_read_enemy()
	ev_index = battle.event_count()
	while log_lines.size() > 6:
		log_lines.pop_front()

## The enemy captain's style for the end screen; a broadsider that never got to show it is described as such.
func _style_text() -> String:
	var p: int = battle.get_personality()
	if p == 2 and not read_calls.has("broadside"):
		return "a broadsider, though the fight ended before it turned side-on"
	return STYLE_NAMES[clampi(p, 0, STYLE_NAMES.size() - 1)]

## The crew calls out what the enemy frigate does, once each, as plain teletype lines: the player works out its
## captain's style from these and from watching it. Nothing here comes from the AI's settings, only from its motion.
func _read_enemy() -> void:
	if S1.is_empty() or state != "battle": return
	var t: float = battle.get_time()
	var r: float = battle.get_range_km()
	var calls := []
	# (side-on just to kill sideways drift in a crossing isn't a broadside: its drive is pointed across, not its guns)
	if int(S1["facing"]) == 1 and not bool(S1.get("ai_lateral", false)): calls.append(["broadside", "Enemy turning broadside"])
	if int(S1["roll_dir"]) != 0: calls.append(["roll", "Enemy rolling"])
	# the frigate's own motion away from us, not the range rate (which our own burn changes too)
	var los := (Vector2(S1["pos"]) - Vector2(S0["pos"])).normalized()
	if Vector2(S1["vel"]).dot(los) > 15.0 and int(S1["burn"]) != 0 and r < 80.0:
		calls.append(["opening", "Enemy opening the range"])
	if r < 25.0: calls.append(["close", "Enemy inside 25 km"])
	for c in calls:
		if not read_calls.has(c[0]):
			read_calls[c[0]] = t
			log_lines.append([c[1], _clock(t), false, t])

## What the crew hears: our own gun firing, enemy rounds striking our hull, alarms for our losses and overheating.
func _event_sound(e: Dictionary) -> void:
	if sfx == null or state != "battle" or battle.get_speed() == 0: return
	var mine := int(e["ship"]) == 0
	match str(e["kind"]):
		"fire": if mine: sfx.play("coil", 0.0)
		"hit": if mine: sfx.play("hit", -2.0, 0.15)
		"disabled": if mine: sfx.play("alarm", -4.0, 0.0)
		"overheat": if mine: sfx.play("klaxon", -4.0, 0.0)

func _loop_sounds(delta: float) -> void:
	if sfx == null: return
	if state != "battle" or battle.get_speed() == 0 or battle.get_winner() >= 0:
		sfx.stop_loops()
		was_lasing = false
		return
	var own: Dictionary = S0
	var foe: Dictionary = S1
	var n := 0
	for f in own["turret_firing"]:
		if f: n += 1
	if n > 0 and not was_lasing: sfx.play("charge", -6.0, 0.03)
	was_lasing = n > 0
	sfx.loop("laser", 0.18 * n, delta)
	sfx.loop("sizzle", 0.5 if foe["laser_firing"] else 0.0, delta)
	sfx.loop("drive", 0.6 if own["burning"] else 0.0, delta)
	sfx.loop("oms", 0.35 if (own["oms"] as Vector2).length() > 0.01 else 0.0, delta)

func _track_heat() -> void:
	var t: float = battle.get_time()
	if t - last_time >= 1.0:
		var h: float = S0["heat"]
		heat_rate = lerpf(heat_rate, (h - last_heat) / (t - last_time), 0.5)
		last_heat = h
		last_time = t

## Read the two ships and the rounds in flight from the battle once a frame. Building these Dictionaries is the
## costly part of the bridge, so everything drawn this frame (HUD, overlays, sounds) reads the copies.
## Click handlers that change orders still ask the battle directly, since they need the state after the order.
## While paused nothing changes unless an order is given, so the copies are kept until the clock moves or input arrives.
func _snap() -> void:
	var t: float = battle.get_time()
	if t == snap_time and not snap_dirty and not S0.is_empty(): return
	if _ex_ready and not S0.is_empty():
		_ex_h[0] = float(S0["heading"])
		_ex_h[1] = float(S1["heading"])
		_ex_roll[0] = float(S0["roll"])
		_ex_roll[1] = float(S1["roll"])
	snap_time = t
	snap_dirty = false
	S0 = battle.get_ship(0)
	S1 = battle.get_ship(1)
	SHOTS = battle.get_shots()
	if not _ex_ready:
		_ex_h[0] = float(S0["heading"])
		_ex_h[1] = float(S1["heading"])
		_ex_roll[0] = float(S0["roll"])
		_ex_roll[1] = float(S1["roll"])
		_ex_ready = true

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec() if bench_frames > 0 else 0
	if state == "battle" and battle:
		battle.advance(delta)
	var ta := Time.get_ticks_usec()
	if battle:
		_snap()
	var tb := Time.get_ticks_usec()
	if state == "battle" and battle:
		_drain_events()
		_track_heat()
		_loop_sounds(delta)
		if battle.get_winner() >= 0 and not end_screen.visible:
			if aar and not aar.done: aar.finish(battle)
			menu_ui.show_end()
	var tc := Time.get_ticks_usec()
	if battle:
		_update_world(delta)
		if state == "battle": tplot.update_from(S0, S1, battle.get_time(), battle.get_sensor_quality(), battle.get_closing())
	var td := Time.get_ticks_usec()
	if battle and hud.visible:
		hud_ui.update(delta)
	var te := Time.get_ticks_usec()
	if bench_frames > 0 and bench_n > 60:     # --bench: time per part of the frame
		for kv in [["adv", ta - t0], ["snap", tb - ta], ["events_snd", tc - tb], ["world", td - tc], ["hud", te - td]]:
			bench_sum[kv[0]] = bench_sum.get(kv[0], 0.0) + kv[1] / 1000.0
	if bench_frames > 0:
		_bench_step(delta, Time.get_ticks_usec() - t0)
	if _warm_vp != null:
		_warm_vp.queue_free()
		_warm_vp = null
	if fps_meter and fps_meter.visible != Settings.show_fps:
		fps_meter.visible = Settings.show_fps
	if shot_path != "":
		shot_frames += 1
		if shot_frames == 10:
			for p in shot_clicks:
				for down in [true, false]:
					var ev := InputEventMouseButton.new()
					ev.button_index = MOUSE_BUTTON_LEFT
					ev.pressed = down
					ev.position = p
					ev.global_position = p
					Input.parse_input_event(ev)
		if shot_frames == 38 and OS.get_cmdline_user_args().has("--fx"):   # freeze the gun effect t seconds in
			var args := OS.get_cmdline_user_args()
			var m: ShipModel = foe_model if view_target else own_model
			m.fire_gun()
			m._process(float(args[args.find("--fx") + 1]))
		if shot_frames == 20 and OS.get_cmdline_user_args().has("--aar") and end_screen.visible: _open_aar()
		if shot_frames == 20 and OS.get_cmdline_user_args().has("--settings"): settings_panel.open()
		if shot_frames == 20 and OS.get_cmdline_user_args().has("--brief"): briefing.open()
		if OS.get_cmdline_user_args().has("--esc"):   # screenshots: press Esc n times (20, 26, ...) through the real input path
			var n := _arg_int(OS.get_cmdline_user_args(), "--esc", 1)
			if shot_frames >= 20 and shot_frames < 20 + 6 * n and (shot_frames - 20) % 6 == 0:
				var k := InputEventKey.new()
				k.keycode = KEY_ESCAPE
				k.pressed = true
				Input.parse_input_event(k)
		if shot_frames == 40:
			var img := get_viewport().get_texture().get_image()
			img.save_png(shot_path)
			get_tree().quit()

func _sim_to_world(p: Vector2, origin: Vector2) -> Vector3:
	# Sim plane (km) to world (m): sim x -> X, sim y -> -Z, around a floating origin.
	var d := (p - origin) * 1000.0
	return Vector3(d.x, 0, -d.y)

func _ahead(ship: Dictionary, alpha: float) -> Vector2:
	# pos is km, vel is m/s. alpha is the fraction of the 0.1 s tick still to come.
	return (ship["pos"] as Vector2) + (ship["vel"] as Vector2) * (alpha * 0.1 / 1000.0)

func _ahead_angle(cur: float, prev: float, alpha: float) -> float:
	return cur + wrapf(cur - prev, -PI, PI) * alpha

func _update_world(delta: float) -> void:
	var own: Dictionary = S0
	var foe: Dictionary = S1
	# The sim moves in 0.1 s steps. Drawing only the last step makes the hull, the enemy and the rounds jump
	# ten times a second however high the frame rate is. Extrapolate with the velocity the tick just set.
	var alpha := float(battle.get_fraction()) if shot_path == "" else 0.0
	var own_p := _ahead(own, alpha)
	var foe_p := _ahead(foe, alpha)
	var focus: Vector2 = foe_p if view_target else own_p
	own_model.position = _sim_to_world(own_p, focus)
	foe_model.position = _sim_to_world(foe_p, focus)
	roll_angle = _ahead_angle(float(own["roll"]), _ex_roll[0], alpha)
	foe_roll = _ahead_angle(float(foe["roll"]), _ex_roll[1], alpha)
	hdg_angle = _ahead_angle(float(own["heading"]), _ex_h[0], alpha)
	own_model.rotation = Vector3(0, hdg_angle - PI / 2, roll_angle)
	foe_model.rotation = Vector3(0, _ahead_angle(float(foe["heading"]), _ex_h[1], alpha) - PI / 2, foe_roll)
	own_model.view_mode = 1 if armor_view else 0
	foe_model.view_mode = 1 if armor_view and view_target and battle.get_sensor_quality() > 0.5 else 0
	# A still has to show the pose the sim is already in. The wing fold takes about a second in play;
	# the capture finishes it so a stowed ship is not photographed half-open.
	var pose_delta := delta if shot_path == "" else maxf(delta, 2.0)
	own_model.show_state(own, pose_delta)
	foe_model.show_state(foe, pose_delta)
	own_model.aim(own["turret_aim"], delta if shot_path == "" else -1.0)
	foe_model.aim(foe["turret_aim"], delta if shot_path == "" else -1.0)
	own_model.beam_fx = laser_beams
	foe_model.beam_fx = laser_beams
	own_model.aim_sensor(foe_model.global_position)
	foe_model.aim_sensor(own_model.global_position)
	planet.position = Vector3(0, -(MARS_R + ALT), 0)
	# Camera: orbit (or chase) the ship in view; the view is rolled a little so the planet's limb runs across the lower left.
	var target_node: Node3D = foe_model if view_target else own_model
	var off: Vector3
	if chase and not view_target:
		var back := own_model.global_transform.basis.z.normalized()
		off = back * dist * 0.9 + Vector3.UP * dist * 0.25
	else:
		off = Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)) * dist
	cam.position = target_node.position + off
	# Shadow map covers just the ship in view, so its resolution goes on the ship, not empty space.
	if absf(sun.directional_shadow_max_distance - (dist + 260.0)) > 1.0: sun.directional_shadow_max_distance = dist + 260.0
	var fwd := (target_node.position - cam.position).normalized()
	cam.look_at(target_node.position, Vector3.UP.rotated(fwd, -0.38))
	# Lasers: a hot spot where the beam lands, a faint glow at each firing emitter, and fire-control lines on the
	# overlay. The beam itself is drawn only when the player asks for it (L, or Settings).
	var dtb := delta * battle_speed() if shot_path == "" else 0.1    # screenshots: let the spot heat up while posing
	var own_fire: Array = own["turret_firing"]
	var foe_fire: Array = foe["turret_firing"]
	own_model.show_emitters(own_fire)
	foe_model.show_emitters(foe_fire)
	foe_model.update_spot(own_fire.count(true), int(own["target_sys"]), int(own["target_turret"]), own_model.position, dtb)
	own_model.update_spot(foe_fire.count(true), int(foe["target_sys"]), int(foe["target_turret"]), foe_model.position, dtb)
	beam_vis.clear()
	for k in 3:
		if own_fire[k]: beam_vis.append([own_model.muzzle_position(k), foe_model.spot_position(), Color(0.55, 0.85, 1.0, 0.8)])
		if foe_fire[k]: beam_vis.append([foe_model.muzzle_position(k), own_model.spot_position(), Color(1.0, 0.5, 0.3, 0.8)])
	# A spot on the far side of the hull from the camera is hidden. The glow is wider than the hull's curve, so it
	# still shows when its side is turned up to about 20 deg away (and an end cap seen edge-on).
	for m: ShipModel in [own_model, foe_model]:
		var face := m.spot_normal.dot((cam.position - m.spot_position()).normalized()) > -0.35
		m.spot.visible = m.spot.visible and face
		m.spot_halo.visible = m.spot.visible
	shot_vis.clear()
	for s in SHOTS:
		var sp: Vector2 = s["pos"]
		if s.has("vel"): sp += (s["vel"] as Vector2) * (alpha * 0.1 / 1000.0)
		var p := _sim_to_world(sp, focus)
		var dir := (foe_model.position - own_model.position).normalized() if int(s["shooter"]) == 0 else (own_model.position - foe_model.position).normalized()
		var tc := Color(0.6, 0.85, 1.0) if int(s["shooter"]) == 0 else Color(1.0, 0.6, 0.25)
		shot_vis.append([p, dir, tc])
	# EO camera: a long lens is a camera placed close along the same line of sight, framed by the target's apparent size.
	var q: float = battle.get_sensor_quality()
	# Size snapped to 4 px steps and set only on change: a new size reallocates the render target. That new
	# target is uninitialised until this viewport draws into it. A real GPU shows that leftover memory as
	# coloured noise; resizing while updates are off is what filled the scope during the tactical plot.
	var res := int(clamp(12 + 180 * q * q, 12, 192)) / 4 * 4
	# The plot stops the main 3D view only. This feed stays live in every battle view, including the plot.
	# It is a small unshadowed copy of the enemy, so it does not bring the main view's cost back.
	var eo_live := hud.visible or shot_path != ""
	if eo_live and eo_vp.size.x != res: eo_vp.size = Vector2i(res, res)
	var eo_mode := SubViewport.UPDATE_WHEN_VISIBLE if eo_live else SubViewport.UPDATE_DISABLED
	if eo_vp.render_target_update_mode != eo_mode: eo_vp.render_target_update_mode = eo_mode
	if eo_mode == SubViewport.UPDATE_WHEN_VISIBLE and eo_model:
		eo_model.position = foe_model.position
		eo_model.rotation = foe_model.rotation
		eo_model.view_mode = foe_model.view_mode
		eo_model.beam_fx = laser_beams
		eo_model.show_state(foe, pose_delta)
		eo_model.aim(foe["turret_aim"], delta if shot_path == "" else -1.0)
		eo_model.show_emitters(foe_fire)
		eo_model.update_spot(own_fire.count(true), int(own["target_sys"]), int(own["target_turret"]), own_model.position, dtb)
		eo_model.aim_sensor(own_model.position, false)
	var los := (foe_model.position - own_model.position).normalized()
	var axis := -foe_model.global_transform.basis.z.normalized()
	var across: float = foe_model.length * sqrt(max(0.0, 1.0 - pow(los.dot(axis), 2))) + foe_model.length * 0.25
	var half: float = max(12.0, across * 0.65)
	eo_cam.position = foe_model.position - los * (half / tan(deg_to_rad(2.0)))
	eo_cam.look_at(foe_model.position, Vector3.UP)
	if eo_mode == SubViewport.UPDATE_WHEN_VISIBLE and eo_model:
		var eo_face := eo_model.spot_normal.dot((eo_cam.position - eo_model.spot_position()).normalized()) > -0.35
		eo_model.spot.visible = eo_model.spot.visible and eo_face
		eo_model.spot_halo.visible = eo_model.spot.visible

func battle_speed() -> float:
	return [0.0, 0.5, 1.0, 2.0, 5.0, 10.0, 50.0][battle.get_speed()]

static func _clock(t: float) -> String:
	return "%02d:%02d" % [int(t) / 60, int(t) % 60]

static func _sd(n: float) -> float:
	var x := sin(n * 12.9898 + 78.233) * 43758.5453
	return x - floor(x)

# ------------------------------------------------------------------ HUD build


# ------------------------------------------------------------------ orders

func _set_mode(mi: int) -> void:
	var own: Dictionary = battle.get_ship(0)
	preset_mode = mi == 1
	battle.set_fire_mode(0 if mi == 2 else 1, int(own["target_sys"]))
	if mi == 2: battle.set_target_turret(-1)

func _pick_target(si: int) -> void:
	# Picking a target in auto switches to manual, as on the prototype. Picking the lasers again steps through the
	# enemy's turrets that still work: any (fire control picks the exposed one) → 1 → 2 → 3 → any.
	var own: Dictionary = battle.get_ship(0)
	var again := int(own["fire_mode"]) == 1 and int(own["target_sys"]) == si
	if int(own["fire_mode"]) == 0:
		preset_mode = false
	battle.set_fire_mode(1, si)
	var next := -1
	if si == 1 and again:
		var tmk: PackedInt32Array = own["turret_mark"]   # our crew's marks: skip turrets we judge knocked out
		var cur: int = own["target_turret"]
		for step in range(1, 5):
			var cand := (cur + 1 + step) % 4 - 1        # cycles -1, 0, 1, 2
			if cand < 0 or tmk[cand] != 2:
				next = cand
				break
	battle.set_target_turret(next)

## Right-click on a target button: the crew's mark steps unmarked -> degraded -> killed -> unmarked. On the lasers it
## marks the turret being shown (after cycling to one), else the laser system as a whole. AUTO fire control skips
## anything marked killed, right or wrong.
func _cycle_mark(si: int) -> void:
	var own: Dictionary = battle.get_ship(0)
	var tt: int = own["target_turret"] if int(own["target_sys"]) == 1 else -1
	var cur: int
	if si == 1 and tt >= 0:
		cur = (own["turret_mark"] as PackedInt32Array)[tt]
		battle.set_mark(1, tt, (cur + 1) % 3)
	elif si == 1:
		# the laser as a whole: mark all three turrets together
		var tm: PackedInt32Array = own["turret_mark"]
		cur = tm[0] if tm[0] == tm[1] and tm[1] == tm[2] else 0
		for k in 3: battle.set_mark(1, k, (cur + 1) % 3)
	else:
		cur = (own["mark"] as PackedInt32Array)[si]
		battle.set_mark(si, -1, (cur + 1) % 3)

func _toggle_free() -> void:
	battle.set_weapons_free(not bool(battle.get_ship(0)["weapons_free"]))

func _set_throttle(v: float) -> void:
	throttle = v
	var b := int(battle.get_ship(0)["burn"])
	if b != 0:
		battle.set_burn(b, throttle)

func _toggle_ignite() -> void:
	if int(battle.get_ship(0)["burn"]) != 0:
		battle.set_burn(0, throttle)
		battle.set_oms_strafe(0)
	else:
		battle.set_burn(sel_burn, throttle)

func _helm(act) -> void:
	if act is String:
		var me: Dictionary = battle.get_ship(0)
		match act:
			"roll-": battle.set_roll(0 if int(me["roll_dir"]) == -1 else -1)
			"roll+": battle.set_roll(0 if int(me["roll_dir"]) == 1 else 1)
			"side": battle.set_facing(0 if int(me["facing"]) == 1 else 1)
	else:
		var burning := int(battle.get_ship(0)["burn"])
		# A closing burn is the main drive. Left and right are the pods: they stack on that burn instead of
		# cutting it. Any other helm pick is a single order, as before, and clears a stacked strafe.
		if (int(act) == 3 or int(act) == 4) and burning == 1:
			var want := 1 if int(act) == 3 else -1
			var cur := int(battle.get_ship(0)["oms_strafe"])
			battle.set_oms_strafe(0 if cur == want else want)
			hud_dirty = true
			return
		battle.set_oms_strafe(0)
		sel_burn = int(act)
		if burning != 0:
			battle.set_burn(sel_burn, throttle)

func _view(v: String) -> void:
	match v:
		"own":
			view_target = false
			if tplot.visible: _toggle_plot()
		"enemy":
			view_target = true
			if tplot.visible: _toggle_plot()
		"chase": chase = not chase
		"plot": _toggle_plot()
		"real": armor_view = false
		"armor": armor_view = true

## The tactical plot replaces the 3D view while it's up, and the 3D view stops rendering underneath it.
func _toggle_plot() -> void:
	tplot.visible = not tplot.visible
	view_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED if tplot.visible else SubViewport.UPDATE_WHEN_VISIBLE
	hud_dirty = true

func _on_dc_line(i: int) -> void:
	if i < dc_line_sys.size() and int(dc_line_sys[i]) >= 0:
		battle.order_repair(int(dc_line_sys[i]))

# ------------------------------------------------------------------ HUD update

func _own_name() -> String:
	if battle == null: return "Dagger"
	return own_name_s

## Name shown for a ship. The coilgun Earth class is stored as Lance and labelled UEN Second Opinion.
func _shown_ship_name(ship: Dictionary) -> String:
	var n := str(ship["name"])
	return "UEN Second Opinion" if n == "Lance" else n

func _own_class() -> String:
	if battle == null: return ""
	return ["LASER CRUISER", "COIL GUN FRIGATE", "FRIGATE"][ship_class] + " · EARTH"

func _foe_name() -> String:
	return foe_name_s




func _open_aar() -> void:
	if aar == null or not aar.done: return
	if aar_view == null:
		var dim := ColorRect.new()           # covers the end screen's own text while the report is up
		dim.color = Color(W.BG, 0.94)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		end_screen.add_child(dim)
		aar_view = AARView.new()
		end_screen.add_child(aar_view)
		aar_view.closed.connect(func(): dim.visible = false)
		aar_view.visibility_changed.connect(func(): dim.visible = aar_view.visible)
	aar_view.position = (get_viewport().get_visible_rect().size - aar_view.size) * 0.5
	aar_view.show_report(aar)

## Extra files for the log export: this battle's events and, once it's over, the after-action report.
func _log_extras() -> Dictionary:
	var out := {}
	if battle != null:
		var lines := PackedStringArray()
		for e in battle.get_events(0):
			lines.append("%s  [%s] %s" % [_clock(float(e["time"])), str(e["kind"]), str(e["text"])])
		out["battle_events.txt"] = "\n".join(lines)
	if aar and aar.done: out["after_action.txt"] = aar.as_text()
	return out

func _watch_ai() -> void:
	_start(1, false)                 # no briefing for a battle the player only watches
	battle.set_player_ai(true)

func _open_patreon() -> void:
	if PATREON_URL != "":
		OS.shell_open(PATREON_URL)

# ------------------------------------------------------------------ input

## Click an enemy component in the enemy view or on the EO scope to target it; click the target bracket to look at it.
func _click_target(p: Vector2) -> bool:
	if battle == null or state != "battle": return false
	if VP.has_point(p) and tplot.visible: return false     # the plot covers the view: no hidden 3D picks
	if VP.has_point(p):
		var local := p - VP.position
		if not view_target:
			if bracket_pos.distance_to(local) < 40: view_target = true; return true
			return false
		return _pick_near(local, pick_points)
	if scope_rect.has_point(p) and battle.get_sensor_quality() > 0.3:
		var res := float(eo_vp.size.x)
		var pts: Array = []
		for pp in _foe_components():
			if eo_cam.is_position_behind(pp[0]): continue
			pts.append([eo_cam.unproject_position(pp[0]) * (240.0 / res), pp[1], pp[2], pp[3]])
		return _pick_near(p - scope_rect.position, pts)
	return false

func _pick_near(p: Vector2, pts: Array) -> bool:
	var best: Array = []
	var bd := 45.0
	for pp in pts:
		var d: float = (pp[0] as Vector2).distance_to(p)
		if d < bd: bd = d; best = pp
	if best.is_empty(): return false
	_pick_target(best[1])
	return true

## The enemy's targetable parts in world space: [position, system, turret, label]
func _foe_components() -> Array:
	var out: Array = []
	for i in TARGETS.size():
		var si: int = TARGETS[i][0]
		var tk: int = TARGETS[i][1]
		if si == 2 and int(S1["gun"]) == 0: continue
		var pos: Vector3 = foe_model.sys_position(si)
		var lab: String = TARGETS[i][2]
		if si == 1:
			# one marker for the lasers, on the picked turret, or the one fire control would hit (faces us), or any live one
			var foe: Dictionary = S1
			var tmk: PackedInt32Array = S0["turret_mark"]   # our marks, not the truth
			var want: int = S0["target_turret"]
			if want < 0:
				var bears: Array = foe["turret_bears"]
				for k in 3:
					if tmk[k] != 2 and bears[k]: want = k; break
				if want < 0:
					for k in 3:
						if tmk[k] != 2: want = k; break
			if want >= 0:
				pos = foe_model.turret_position(want)
				lab = "LSR %d" % (want + 1) if int(S0["target_turret"]) >= 0 else "LSR"
		out.append([pos, si, tk, lab])
	return out

func _input(e: InputEvent) -> void:
	if e is InputEventMouseButton or e is InputEventKey:   # show the result of a click at once
		hud_dirty = true
		snap_dirty = true

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _click_target(e.position):
		return
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_RIGHT or e.button_index == MOUSE_BUTTON_MIDDLE: dragging = e.pressed
		if e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP: dist = max(60.0, dist * 0.88)
		if e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN: dist = min(5000.0, dist / 0.88)
	elif e is InputEventMouseMotion and dragging:
		yaw -= e.relative.x * 0.006
		pitch = clamp(pitch + e.relative.y * 0.006, -1.4, 1.4)
	elif e is InputEventKey and e.pressed and not e.echo and state == "battle":
		match e.keycode:
			KEY_SPACE: _toggle_free()
			KEY_P: battle.set_speed(0 if battle.get_speed() != 0 else 2)
			KEY_PERIOD: battle.set_speed(mini(battle.get_speed() + 1, SPEED_NAMES.size() - 2))   # cruise is locked in the demo
			KEY_COMMA: battle.set_speed(max(1, battle.get_speed() - 1))
			KEY_TAB:
				view_target = not view_target
				if tplot.visible: _toggle_plot()
			KEY_C: chase = not chase
			KEY_B: fc_lines = not fc_lines
			KEY_L: laser_beams = not laser_beams
			KEY_F4:
				Settings.set_show_fps(not Settings.show_fps)
				if fps_meter: fps_meter.visible = Settings.show_fps
			KEY_V: _toggle_plot()
			KEY_Q: _helm("roll-")
			KEY_E: _helm("roll+")
			KEY_T: _helm("side")
			KEY_W: _helm(1)
			KEY_S: _helm(2)
			KEY_A: _helm(3)
			KEY_D: _helm(4)
			KEY_X: _helm(5)
			KEY_I, KEY_ENTER: _toggle_ignite()
			KEY_F1: _set_mode(0)
			KEY_F2: _set_mode(1)
			KEY_F3: _set_mode(2)
			KEY_ESCAPE:
				if aar_view != null and aar_view.visible: aar_view.visible = false   # close the report first
				else: menu_ui.show()
			KEY_M: sfx.muted = not sfx.muted
	elif e is InputEventKey and e.pressed and not e.echo and state == "menu" and e.keycode == KEY_ESCAPE and resumable:
		menu_ui.resume()



## Alerts over the 3D view: a pulsing red LASER WARNING right above our ship while an enemy beam is on us, and callouts
## for major hits on our ship (round strikes, armour burn-through, systems knocked out).
## Whether the alerts layer has anything to show (or to clear from last frame); it is redrawn only then.
func lasing_or_popups() -> bool:
	var busy := not popups.is_empty()
	for f in (S1["turret_firing"] as Array): busy = busy or bool(f)
	var need := busy or alerts_shown
	alerts_shown = busy
	return need

func _draw_alerts(c: Control) -> void:
	if battle == null or state != "battle" or cam == null: return
	var own: Dictionary = S0
	var foe: Dictionary = S1
	var now := Time.get_ticks_msec() / 1000.0
	# own view: over our ship; enemy view (our ship is off screen): top centre of the view
	var own_anchor := Vector2(402, 150) if view_target else _anchor(own_model, Vector2(402, 150))
	var foe_anchor := _anchor(foe_model, bracket_pos if bracket_pos.x > -900.0 else Vector2(402, 150))
	var lasing := false
	for f in (foe["turret_firing"] as Array): lasing = lasing or bool(f)
	var y := own_anchor.y
	var ship_y := own_anchor.y
	if lasing:
		# vertically halfway between the time controls (bottom at y 42 in the view) and the top of our ship, but never
		# over the view's title and its hint line (which ends near y 56)
		y = maxf(108.0, (42.0 + ship_y) / 2.0 + 11.0)      # the box is centred 11 px above y; its top is y - 44
		var pulse := 0.65 + 0.35 * sin(now * TAU * 2.5)
		var txt := "LASER WARNING"
		var w := W.FH.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		var box := Rect2(Vector2(own_anchor.x - w / 2 - 14, y - 44), Vector2(w + 28, 66))
		c.draw_rect(box, Color(0.12, 0.0, 0.0, 0.7 * pulse))
		c.draw_rect(box, Color(W.HOT, pulse), false, 2.0)
		W.text_c(c, W.FH, txt, Vector2(own_anchor.x, y - 16), 30, Color(1.0, 0.25, 0.2, pulse))
		W.text_c(c, W.FM, "ENEMY BEAM ON THE HULL", Vector2(own_anchor.x, y + 10), 11, Color(1.0, 0.6, 0.55, pulse))
	# hit callouts: rise and fade over three seconds, newest nearest the ship
	var stack := [0, 0]
	for i in range(popups.size() - 1, -1, -1):
		var pu: Array = popups[i]
		var age := now - float(pu[4])
		if shot_path != "":                          # screenshots: rendering is slow; show the last 20 battle seconds as fresh
			age = 0.5 if battle.get_time() - float(pu[5]) < 20.0 else 99.0
		if age > 3.0: continue
		var who: int = pu[0]
		if stack[who] >= 2: continue                 # at most two per ship (fast time can bring many at once)
		var a := 1.0 if age < 2.0 else 3.0 - age
		var base := foe_anchor + Vector2(0, -100)
		if who == 0:
			# own view: just above our ship; enemy view (our ship off screen): under the laser warning
			base = Vector2(own_anchor.x, 250.0 + stack[0] * 88) if view_target else Vector2(own_anchor.x, ship_y)
		var p := base + Vector2(0, -stack[who] * 44 - age * 8)
		stack[who] += 1
		W.text_c(c, W.FH, pu[1], p, 22, Color(pu[3], a))
		W.text_c(c, W.FM, pu[2], p + Vector2(0, 16), 11, Color(W.TEXT, a * 0.9))
	while popups.size() > 0 and now - float(popups[0][4]) > 3.0 and shot_path == "":
		popups.pop_front()

## Screen point just above a ship (clamped inside the view), or the fallback when it is behind the camera.
func _anchor(m: ShipModel, fallback: Vector2) -> Vector2:
	if m == null: return fallback
	var top := m.global_position + Vector3.UP * m.length * 0.45
	if cam.is_position_behind(top): return fallback
	var p := cam.unproject_position(top)
	return Vector2(clampf(p.x, 160, 804 - 160), clampf(p.y, 120, 684 - 60))

## A major hit for the callouts: what happened and to which ship.
func _popup(e: Dictionary) -> void:
	var kind := str(e["kind"])
	var who := int(e["ship"])
	if who != 0: return            # only our own damage: what happened to the enemy is for the crew to judge
	var head := ""
	match kind:
		"hit": head = "HIT"
		"burn-through": head = "ARMOUR BREACHED"
		"disabled": head = "SYSTEM DOWN"
		_: return
	var col: Color = W.HOT if who == 0 else W.PRI
	var detail := str(e["text"]).to_upper()
	if detail.length() > 46: detail = detail.substr(0, 45) + "…"
	popups.append([who, head, detail, col, Time.get_ticks_msec() / 1000.0, float(e["time"])])


## A crew call in teletype shorthand, so it fits the 24-character line: system codes as on the target buttons and
## PROB DSBL / PROB DSTR, e.g. "Enemy laser turret 2: probable destroy" -> "ENEMY LSR 2 · PROB DSTR".
static func _teletype(t: String) -> String:
	var u := t.to_upper()
	u = u.replace(": PROBABLE DISABLE", " · PROB DSBL").replace(": PROBABLE DESTROY", " · PROB DSTR")
	u = u.replace("LASER TURRET ", "LSR ")
	for i in SYS_NAMES.size():
		u = u.replace("ENEMY " + str(SYS_NAMES[i]).to_upper() + " ", "ENEMY " + str(SYS_ABBR[i]) + " ")
	return u


## --bench: average costs per frame over bench_frames frames of a live battle (after 60 warm-up frames), then quit.
## Script time is the whole _process tree; frame time includes rendering. Draw calls and objects are per frame.
func _bench_step(delta: float, script_us: int) -> void:
	bench_n += 1
	if bench_n <= 60: return
	var m := {
		"frame_ms": delta * 1000.0,
		"script_ms": script_us / 1000.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"canvas_draws": get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
	}
	for k in m: bench_sum[k] = bench_sum.get(k, 0.0) + m[k]
	bench_times.append(m["frame_ms"])
	if bench_n == 60 + bench_frames:
		var out := "BENCH"
		for k in bench_sum: out += "  %s=%.3f" % [k, bench_sum[k] / bench_frames]
		bench_times.sort()
		var n := bench_times.size()
		var mean: float = float(bench_sum["frame_ms"]) / float(n)
		var varsum := 0.0
		for t in bench_times: varsum += (t - mean) * (t - mean)
		var sd := sqrt(varsum / n)
		var p95 := bench_times[mini(n - 1, int(n * 0.95))]
		var p99 := bench_times[mini(n - 1, int(n * 0.99))]
		out += "  frame_sd=%.3f  frame_min=%.3f  frame_p95=%.3f  frame_p99=%.3f  frame_max=%.3f" % [sd, bench_times[0], p95, p99, bench_times[n - 1]]
		print(out)
		get_tree().quit()
