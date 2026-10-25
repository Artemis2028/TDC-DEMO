class_name Settings
## Player settings, kept in user://settings.cfg and applied as they change.
## All state is static: call load_and_apply() once at start-up, then change a value through its set_* function,
## which applies it at once and (unless told otherwise) saves the file.
## Nothing here touches the simulation; it only sets the sound level, the window and the frame-rate cap.

const PATH := "user://settings.cfg"
const WINDOW_NAMES := ["Windowed", "Fullscreen", "Borderless"]
## 0 means unlimited: vsync off and no cap, so the rate can pass the display.
const FPS_CAPS := [60, 120, 144, 0]

static var volume := 100                 # Master bus, 0-100 %; 0 is mute
static var window_mode := 0              # index into WINDOW_NAMES
static var fps_cap := 120                # one of FPS_CAPS
static var vsync := true                 # tear-free when a cap can share the display. Unlimited ignores this.
static var fc_lines := true              # fire-control lines shown at the start of a battle
static var laser_beams := false          # draw the laser beams. Off: a beam in vacuum is not visible from the side
static var show_briefing := true         # the how-to-play pages before the first battle of a session
static var show_fps := false             # frame time in the corner. Off: it is a diagnostic, not part of the deck.

## Read the file (missing keys keep their defaults) and apply everything. Call once, from _ready.
static func load_and_apply() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		volume = clampi(int(cf.get_value("audio", "volume", volume)), 0, 100)
		window_mode = clampi(int(cf.get_value("display", "window_mode", window_mode)), 0, WINDOW_NAMES.size() - 1)
		var cap := int(cf.get_value("display", "fps_cap", fps_cap))
		fps_cap = cap if FPS_CAPS.has(cap) else 120
		vsync = bool(cf.get_value("display", "vsync", vsync))
		fc_lines = bool(cf.get_value("game", "fc_lines", fc_lines))
		laser_beams = bool(cf.get_value("game", "laser_beams", laser_beams))
		show_briefing = bool(cf.get_value("game", "show_briefing", show_briefing))
		show_fps = bool(cf.get_value("game", "show_fps", show_fps))
	apply_volume()
	# Screenshot and benchmark runs keep their own window and frame rate.
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if not (args.has("--shot") or args.has("--bench")):
		apply_window()
		apply_fps()

static func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "volume", volume)
	cf.set_value("display", "window_mode", window_mode)
	cf.set_value("display", "fps_cap", fps_cap)
	cf.set_value("display", "vsync", vsync)
	cf.set_value("game", "fc_lines", fc_lines)
	cf.set_value("game", "laser_beams", laser_beams)
	cf.set_value("game", "show_briefing", show_briefing)
	cf.set_value("game", "show_fps", show_fps)
	var err := cf.save(PATH)
	if err != OK:
		push_warning("Settings: could not write %s (error %d)" % [PATH, err])

## Master bus level. 0 % is a true mute (the bus is muted, not just very quiet). The M key in a battle is separate:
## it stops the sound effects (Sfx.muted) and leaves this level alone, so M never loses the player's volume.
static func apply_volume() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0: return
	AudioServer.set_bus_mute(bus, volume <= 0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(volume / 100.0) if volume > 0 else -80.0)

static func apply_window() -> void:
	match window_mode:
		0:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		2:
			# Godot's plain FULLSCREEN is a borderless window the size of the desktop: alt-tab stays instant.
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

static func apply_fps() -> void:
	# Unlimited is vsync off and no cap. Engine.max_fps = 0 does not turn vsync off, and the project default is
	# vsync on, so a 60 Hz display stayed at 60 with Unlimited selected. A numeric cap below the refresh cannot
	# share vsync slots without skipping, so that cap paces the frames and vsync stays off.
	var refresh := DisplayServer.screen_get_refresh_rate()
	var use_vsync := vsync and fps_cap != 0
	if use_vsync and refresh > 1.0 and fps_cap < int(refresh) - 1:
		use_vsync = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if use_vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0 if use_vsync or fps_cap == 0 else fps_cap

static func set_volume(v: int, persist := true) -> void:
	volume = clampi(v, 0, 100)
	apply_volume()
	if persist: save()

static func set_window_mode(m: int) -> void:
	window_mode = clampi(m, 0, WINDOW_NAMES.size() - 1)
	apply_window()
	save()

static func set_fps_cap(c: int) -> void:
	fps_cap = c if FPS_CAPS.has(c) else 120
	apply_fps()
	save()

static func set_vsync(on: bool) -> void:
	vsync = on
	apply_fps()
	save()

static func set_fc_lines(on: bool) -> void:
	fc_lines = on
	save()

static func set_laser_beams(on: bool) -> void:
	laser_beams = on
	save()

static func set_show_briefing(on: bool) -> void:
	show_briefing = on
	save()

static func set_show_fps(on: bool) -> void:
	show_fps = on
	save()

## The current settings as text, for the log export.
static func describe() -> String:
	var cap := "unlimited" if fps_cap == 0 else str(fps_cap)
	return "volume: %d%%\nwindow mode: %s\nframe-rate cap: %s\nvsync: %s\nframe-time counter: %s\nfire-control lines at start: %s\nvisible laser beams at start: %s\nshow briefing at start-up: %s" % [
		volume, WINDOW_NAMES[window_mode], cap, "on" if vsync else "off", "on" if show_fps else "off", "on" if fc_lines else "off", "on" if laser_beams else "off", "on" if show_briefing else "off"]
