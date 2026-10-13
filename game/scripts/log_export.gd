class_name LogExport
## Collects what a bug report needs into one folder on the player's own PC. Nothing is uploaded or sent anywhere.
## Godot writes its log to user://logs/ (project setting debug/file_logging/enable_file_logging); this copies those
## files, adds a short description of the machine and the settings, and adds whatever text the game passes in.

const FOLDER := "TDC Demo logs"

## Set by the last export: what happened, in words the panel can show (e.g. that Documents was not writable and the
## user:// folder was used instead). "" after a plain success into Documents.
static var last_note := ""
## Tests only: candidate parent folders to try, in order, instead of Documents then user://.
static var root_override: Array = []

## Make <Documents>/TDC Demo logs/<YYYY-MM-DD_HH-MM-SS>/ and fill it. extra maps a file name to its text, e.g.
## {"battle_events.txt": "...", "after_action.txt": "..."}. Every text file is scrubbed of the player's home folder and
## user name. If Documents cannot be written (Controlled Folder Access, OneDrive, no such folder) the user:// folder is
## tried; a folder counts only if every file in it was written. Returns the folder's path, or "" if nothing was saved.
static func export_logs(extra: Dictionary, open_folder := true) -> String:
	var files := {}                      # file name -> PackedByteArray, already scrubbed
	var notes := PackedStringArray()
	var logs := "user://logs"
	if DirAccess.dir_exists_absolute(logs):
		for f in DirAccess.get_files_at(logs):
			var bytes := FileAccess.get_file_as_bytes(logs.path_join(f))
			if bytes.is_empty() and FileAccess.get_open_error() != OK:
				notes.append("could not read %s (error %d)" % [f, FileAccess.get_open_error()])
				continue
			files[f] = scrub(bytes.get_string_from_utf8()).to_utf8_buffer()
	else:
		notes.append("no user://logs folder (file logging was off for this run)")
	for name in extra:
		var fname := String(name).get_file()            # a bare file name only, never a path
		if fname != "": files[fname] = scrub(str(extra[name])).to_utf8_buffer()
	files["system.txt"] = scrub(_system_text(notes)).to_utf8_buffer()
	var dir := _write_folder(files)
	if dir != "" and open_folder:
		_reveal(dir)
	return dir

## Write one text file (scrubbed) into a new timestamped folder in the same place as export_logs. Returns the full
## path of the file, or "" if it could not be saved anywhere.
static func save_text(name: String, text: String) -> String:
	var fname := name.get_file()
	if fname == "": return ""
	var dir := _write_folder({fname: scrub(text).to_utf8_buffer()})
	return dir.path_join(fname) if dir != "" else ""

## Replace the player's home folder (both slash styles) with <home> and their user name with <user>.
static func scrub(text: String) -> String:
	var homes: Array = []
	for v in ["USERPROFILE", "HOME"]:
		var h := OS.get_environment(v).strip_edges()
		if h.length() < 3: continue                      # "/" or "" would wreck the text
		for form in [h, h.replace("\\", "/"), h.replace("/", "\\")]:
			var t: String = form.rstrip("/\\")
			if t.length() >= 3 and not homes.has(t): homes.append(t)
	homes.sort_custom(func(a, b): return a.length() > b.length())    # longest first
	for h in homes: text = text.replace(h, "<home>")
	for v in ["USERNAME", "USER"]:
		var u := OS.get_environment(v).strip_edges()
		if u.length() >= 3: text = text.replace(u, "<user>")
	return text

## Try each candidate parent in turn: make the stamped folder and write every file. Sets last_note.
static func _write_folder(files: Dictionary) -> String:
	last_note = ""
	var stamp := _stamp()
	var roots := _roots()
	for i in roots.size():
		var d: String = String(roots[i]).path_join(stamp)
		var ok := DirAccess.make_dir_recursive_absolute(d) == OK
		var failed := PackedStringArray()
		if ok:
			for name in files:
				var f := FileAccess.open(d.path_join(name), FileAccess.WRITE)
				if f == null:
					failed.append(name)
					continue
				f.store_buffer(files[name])
				var err := f.get_error()
				f.close()
				if err != OK: failed.append(name)
		if ok and failed.is_empty():
			if i > 0:
				last_note = "The Documents folder could not be written, so the files went to the game's own folder instead."
			return d
		push_warning("LogExport: could not write to %s (%s)" % [d, "folder" if not ok else ", ".join(failed)])
	last_note = "Nothing could be saved: no folder could be written."
	return ""

static func _roots() -> Array:
	if not root_override.is_empty(): return root_override
	var roots: Array = []
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if docs != "" and DirAccess.dir_exists_absolute(docs):
		roots.append(docs.path_join(FOLDER))
	roots.append(ProjectSettings.globalize_path("user://").path_join(FOLDER))
	return roots

static func _stamp() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d_%02d-%02d-%02d" % [t["year"], t["month"], t["day"], t["hour"], t["minute"], t["second"]]

## Where the log folder goes (first candidate whose folder can be made). Kept for callers that only need a folder.
static func _make_folder() -> String:
	for root in _roots():
		var d: String = String(root).path_join(_stamp())
		if DirAccess.make_dir_recursive_absolute(d) == OK:
			return d
	return ""

## Show the folder in Explorer / Finder (handles spaces); plain shell_open if that fails.
static func _reveal(dir: String) -> void:
	if OS.shell_show_in_file_manager(dir, true) != OK:
		OS.shell_open(dir)

static func _system_text(notes: PackedStringArray) -> String:
	var s := PackedStringArray()
	s.append("TDC Demo " + Version.text())
	s.append("exported: " + Time.get_datetime_string_from_system(false, true))
	s.append("")
	s.append("OS: %s %s (%s)" % [OS.get_name(), OS.get_version(), OS.get_distribution_name()])
	s.append("CPU: %s (%d threads)" % [OS.get_processor_name(), OS.get_processor_count()])
	var mem := OS.get_memory_info()
	if mem.has("physical") and int(mem["physical"]) > 0:
		s.append("memory: %d MB" % (int(mem["physical"]) / 1048576))
	s.append("video adapter: %s" % RenderingServer.get_video_adapter_name())
	s.append("video vendor: %s" % RenderingServer.get_video_adapter_vendor())
	s.append("graphics API: %s" % RenderingServer.get_video_adapter_api_version())
	s.append("renderer: %s" % str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")))
	s.append("screen: %s   window: %s" % [DisplayServer.screen_get_size(), DisplayServer.window_get_size()])
	s.append("Godot: %s" % Engine.get_version_info()["string"])
	s.append("locale: %s" % OS.get_locale())
	s.append("")
	s.append("settings:")
	s.append(Settings.describe())
	if not notes.is_empty():
		s.append("")
		s.append("notes:")
		s.append("\n".join(notes))
	return "\n".join(s) + "\n"
