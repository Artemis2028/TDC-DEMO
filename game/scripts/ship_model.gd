class_name ShipModel
extends Node3D
## A ship as the game draws it: the hull is a model built in Blender (art/build_ships.py, exported to
## models/earth.glb and models/mars.glb); this script finds the named parts in it and brings them to life:
## turrets turn toward the target, radiators fold and glow with heat, OMS jets and the drive plume show the burn,
## knocked-out turrets go dark, and the armour view tints each hull section by its condition.
## The nose points along -Z, +X is the ship's right and +Y its top.

var length := 160.0
var mars := false
var view_mode := 0                    # 0 real colour, 1 armour condition
var sec_parts: Array = [[], [], []]   # per section (nose, body, aft): [material, base colour]
var radiators: Array = []             # [material, base colour] of radiator surfaces that glow with heat
var rad_pivots: Array = []            # radiator roots: scaling local X folds a wing against the hull
var turrets: Array = []               # [head (emitter along its -Z), muzzle, lens, dome material, dome colour, base, base rest basis, head rest basis, last azimuth]
var pods: Array = []                  # OMS nozzles: [radial node, axial node, outward dir, station "F"/"A", radial jet, axial jet]
var plume: MeshInstance3D
var plume_mat: ShaderMaterial
const PLUME_SHADER := preload("res://shaders/plume.gdshader")
## Exhaust display (artistic, after the Dagger v4 concept): the drive plume runs 18 m at the lowest throttle to
## 140 m at full, brightening as it lengthens; OMS jets are short soft glows.
const DRIVE_PLUME_MIN := 18.0
const DRIVE_PLUME_MAX := 140.0
const OMS_PLUME_LENGTH := 5.0
var sys_nodes: Array = []
var _rad_open := 1.0
var _rad_shown := -1.0                # what the materials and pivots last showed, so they are written only on change
var _glow_shown := -1.0
var _rad_dead_shown := false
var _sec_shown: Array = [Color(-2, 0, 0), Color(-2, 0, 0), Color(-2, 0, 0)]
var gun_breech: Node3D                # barrel ends of the spinal gun (markers from the Blender scripts)
var gun_muzzle: Node3D
var _shots: Array = []               # firing effects in progress: [age s, wave ring, barrel glow, muzzle flash, jet, light]
## Gun firing effect timing (real seconds, not battle time, so it reads the same at any time speed).
const GUN_WAVE_TIME := 0.16           # the light running up the coils, breech to muzzle
const GUN_FADE_TIME := 0.9            # barrel afterglow and muzzle flash fading out

const OMS_FWD := 0.10      # OMS stations (fractions of the length from the nose); kept in step with build_ships.py
const OMS_AFT := 0.765

## Build the ship. gun_kind: 0 none, 1 railgun, 2 coilgun.
func build(is_mars: bool, gun_kind: int) -> void:
	mars = is_mars
	length = 130.0 if mars else 193.6
	var root: Node3D = (load("res://models/mars.glb" if mars else "res://models/earth.glb") as PackedScene).instantiate()
	add_child(root)
	var grid := _grid_texture()
	# Materials: this ship gets its own copies so tinting one ship never touches the other. One copy per source
	# material and role (section, radiator panel), shared by every surface that uses it: far fewer materials to
	# update and to switch between when drawing. Turret domes keep one each, since a dead turret's dome is scorched.
	var copies := {}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var sec := -1
		var n := String(mi.name)
		if n.begins_with("N_"): sec = 0
		elif n.begins_with("B_"): sec = 1
		elif n.begins_with("A_"): sec = 2
		var radiator := _under_rad_pivot(mi)
		for si in mi.mesh.get_surface_count():
			var src := mi.get_active_material(si) as StandardMaterial3D
			if src == null: continue
			var rad_panel := radiator and n.begins_with("Rad") and n.length() < 14
			var key := "%d/%d/%s/%s" % [src.get_instance_id(), sec, radiator, n if n.begins_with("B_dome") else ("P" if rad_panel else "")]
			if copies.has(key):
				mi.set_surface_override_material(si, copies[key])
				continue
			var m := src.duplicate() as StandardMaterial3D
			copies[key] = m
			if radiator:
				if n.begins_with("Rad") and n.length() < 14:
					m.albedo_texture = grid           # generated panels carry no texture of their own
					m.uv1_scale = Vector3(3, 2, 1)
				# fins (dark surfaces) glow with heat; frames and brackets don't
				if m.albedo_color.get_luminance() < 0.25 or n.begins_with("Rad") and n.length() < 14:
					m.emission_enabled = true
					m.emission = Color(0.55, 0.12, 0.03)
					m.emission_energy_multiplier = 0.0
					radiators.append([m, m.albedo_color])
			elif sec >= 0 and not m.emission_enabled:
				# Emission stays switched on (black in the normal view): toggling it would compile a new shader
				# variant, a hitch, the first time the armour view opens.
				m.emission_enabled = true
				m.emission = Color.BLACK
				sec_parts[sec].append([m, m.albedo_color])
			mi.set_surface_override_material(si, m)
	for p: Node3D in root.find_children("RadPivot*", "Node3D", true, false):
		rad_pivots.append(p)
	# turrets
	for k in 3:
		var piv := root.find_child("Turret%d" % k, true, false) as Node3D
		var lens := root.find_child("Lens%d" % k, true, false) as MeshInstance3D
		var dome := root.find_child("B_dome%d" % k, true, false) as MeshInstance3D
		var dm := dome.get_surface_override_material(0) as StandardMaterial3D
		var base := root.find_child("TurretBase%d" % k, true, false) as Node3D
		turrets.append([piv, root.find_child("Muzzle%d" % k, true, false), lens, dm, dm.albedo_color, base, base.basis, piv.basis, 0.0])
	# guns: both kinds are in the model; show the one this ship carries
	# (the other one is freed, not just hidden, so it costs nothing to cull or shadow)
	var coil := root.find_child("Gun_Coil", true, false) as Node3D
	var rail := root.find_child("Gun_Rail", true, false) as Node3D
	for g: Node3D in [coil, rail]:
		if g != (coil if gun_kind == 2 else rail if gun_kind == 1 else null):
			g.get_parent().remove_child(g)
			g.free()
	gun_breech = root.find_child("Gun_Breech", true, false) as Node3D
	gun_muzzle = root.find_child("Gun_Muzzle", true, false) as Node3D
	for i in 6:
		sys_nodes.append(root.find_child("Sys%d" % i, true, false))
	# OMS nozzles and their jets
	var r := 0.026 * length
	for tag in ["F", "A"]:
		for k in 4:
			var rn := root.find_child("OMS_%s%d" % [tag, k], true, false) as Node3D
			var an := root.find_child("OMSAX_%s%d" % [tag, k], true, false) as Node3D
			var out := Vector3(rn.position.x, rn.position.y, 0).normalized()
			pods.append([rn, an, out, tag, _jet(r), _jet(r)])
	# drive plume from the nozzle: a glowing plasma volume whose length and brightness follow the throttle
	var nozzle := root.find_child("Nozzle", true, false) as Node3D
	plume = MeshInstance3D.new()
	plume.mesh = _plume_mesh([[0.0, 4.6], [0.06, 3.2], [0.22, 2.0], [0.5, 2.5], [0.8, 5.0], [1.0, 6.8]], 48)
	plume.position = nozzle.position
	plume_mat = ShaderMaterial.new()
	plume_mat.shader = PLUME_SHADER
	plume_mat.set_shader_parameter("tint", Color(0.24, 0.40, 1.0) if not mars else Color(1.0, 0.5, 0.25))
	plume.material_override = plume_mat
	plume.visible = false
	add_child(plume)

## A surface of revolution along +Z for exhaust: profile [[t, radius m], ...] with t 0 at the nozzle, 1 at the end
## (scale the node's Z to set the length). UV.y carries t for the shader's fade.
static func _plume_mesh(profile: Array, seg: int, axis_y := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(profile.size() - 1):
		var t0: float = profile[i][0]
		var t1: float = profile[i + 1][0]
		var r0: float = profile[i][1]
		var r1: float = profile[i + 1][1]
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var q := [[a0, r0, t0], [a0, r1, t1], [a1, r1, t1], [a0, r0, t0], [a1, r1, t1], [a1, r0, t0]]
			for v in q:
				var a: float = v[0]
				var rr: float = v[1]
				var t: float = v[2]
				var n := Vector3(cos(a), sin(a), 0)
				var p := Vector3(cos(a) * rr, sin(a) * rr, t)
				if axis_y:
					n = Vector3(n.x, 0, n.y)
					p = Vector3(p.x, p.z, p.y)
				st.set_normal(n)
				st.set_uv(Vector2(float(k) / seg, t))
				st.add_vertex(p)
	return st.commit()

func _under_rad_pivot(n: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != self:
		if String(p.name).begins_with("RadPivot"): return true
		p = p.get_parent()
	return false

## A thruster jet: a short soft glow widening out of the nozzle along local +Y, hidden until used.
func _jet(_r: float) -> MeshInstance3D:
	var j := MeshInstance3D.new()
	var L := OMS_PLUME_LENGTH
	j.mesh = _plume_mesh([[0.0, 0.5], [0.12, 0.55], [0.4, 0.55 + 0.18 * L], [0.8, 0.55 + 0.3 * L], [1.0, 0.55 + 0.38 * L]], 24, true)
	j.scale = Vector3(1, L, 1)
	var m := ShaderMaterial.new()
	m.shader = PLUME_SHADER
	m.set_shader_parameter("tint", Color(0.52, 0.64, 1.0))
	m.set_shader_parameter("strength", 1.6)
	j.material_override = m
	j.visible = false
	add_child(j)
	return j

## A rotation that points local +Y along dir.
static func _basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.FORWARD) if absf(y.dot(Vector3.FORWARD)) < 0.9 else y.cross(Vector3.RIGHT)
	x = x.normalized()
	return Basis(x, y, x.cross(y))

## Show the OMS jets for a burn: exhaust (local, ship axes) is opposite to the push. Sideways: the nozzle facing the
## exhaust direction at each station. Forward exhaust (slowing): the forward pods; aft exhaust: the aft pods.
func _show_oms(exhaust: Vector3) -> void:
	var r := 0.026 * length
	var radial := Vector3(exhaust.x, exhaust.y, 0)
	var best := {}
	for k in pods.size():
		var tag: String = pods[k][3]
		var d: float = (pods[k][2] as Vector3).dot(radial.normalized()) if radial.length() > 0.2 else 0.0
		if d > 0.3 and d > float(best.get(tag, [0.0, -1])[0]): best[tag] = [d, k]
	for k in pods.size():
		var tag: String = pods[k][3]
		var rj: MeshInstance3D = pods[k][4]
		rj.visible = best.has(tag) and int(best[tag][1]) == k
		if rj.visible:
			var dir := radial.normalized()
			var sc := clampf(radial.length(), 0.4, 1.0)
			var p := (pods[k][0] as Node3D).position
			rj.transform = Transform3D(_basis_y(dir), p).scaled_local(Vector3(sc, OMS_PLUME_LENGTH * sc, sc))
		var aj: MeshInstance3D = pods[k][5]
		aj.visible = (exhaust.z < -0.2 and tag == "F") or (exhaust.z > 0.2 and tag == "A")
		if aj.visible:
			var dz := Vector3(0, 0, signf(exhaust.z))
			var sc := clampf(absf(exhaust.z), 0.4, 1.0)
			var p := (pods[k][1] as Node3D).position
			# A pod with its own axial nozzle fires straight along the hull; a pod with one outward bell (the Dagger)
			# fires all four bells of the station canted toward the exhaust side, their sideways pushes cancelling.
			var d := dz
			if p.distance_to((pods[k][0] as Node3D).position) < 0.01:
				d = ((pods[k][2] as Vector3) + dz * 0.4).normalized()
			aj.transform = Transform3D(_basis_y(d), p).scaled_local(Vector3(sc, OMS_PLUME_LENGTH * sc, sc))

## Point each turret where the battle rules say it points. aims: per turret, a unit vector in ship axes
## (x along the nose, y to the right, z to the top), already limited by the rules to the 30 deg/s slew.
## Each turret is a two-axis gimbal: the base (fork or cradle) turns about the mount axis (its local Z, since its
## emitter rests along -Z, straight out of the hull), and the head tilts on the trunnions (its local Y).
## Base rotation by az then head tilt by el sends the emitter to (-sin el cos az, -sin el sin az, -cos el) in the
## base's rest frame; this solves that for az and el. (az, el) and (az + 180, -el) point the same way: the one
## nearer the last azimuth is used, and near straight-out the azimuth is held, so the base never spins round.
func aim(aims: Array) -> void:
	if not is_inside_tree(): return
	for k in mini(turrets.size(), aims.size()):
		var t: Array = turrets[k]
		var head: Node3D = t[0]
		var base: Node3D = t[5]
		var a: Vector3 = aims[k]
		var world: Vector3 = global_transform.basis * Vector3(a.y, a.z, -a.x)          # ship axes to this node's
		var rest: Basis = (base.get_parent() as Node3D).global_transform.basis.orthonormalized() * Basis(t[6]).orthonormalized()
		var d: Vector3 = (rest.inverse() * world).normalized()
		var az: float = t[8]
		var off := sqrt(d.x * d.x + d.y * d.y)               # sin of the angle off straight out
		if off > 0.03:
			var az0 := atan2(-d.y, -d.x)
			az = az0 + PI * roundf((az - az0) / PI)             # the equivalent solution nearest the last one
		var el := atan2(-(d.x * cos(az) + d.y * sin(az)), -d.z)
		t[8] = az
		base.basis = Basis(t[6]) * Basis(Vector3(0, 0, 1), az)
		head.basis = Basis(t[7]) * Basis(Vector3(0, 1, 0), el)

## The spinal gun fires: the coils dump one after another, so a ring of light runs up the barrel from the breech to the
## muzzle, the barrel glows behind it and cools; at the muzzle a flash and a short plasma jet (the armature's
## vaporised trailing edge), and a brief light that catches the hull. The round itself is drawn by main.gd.
func fire_gun() -> void:
	if gun_breech == null or gun_muzzle == null: return
	var colour := Color(1.0, 0.55, 0.25) if mars else Color(0.55, 0.8, 1.0)
	var wave := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.6
	wave.mesh = tm
	wave.material_override = _glow_mat(colour * 6.0)
	var glow := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.15
	cm.bottom_radius = 1.15
	cm.height = 1.0
	glow.mesh = cm
	glow.material_override = _glow_mat(colour * 2.5)
	var flash := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	flash.mesh = sm
	flash.material_override = _glow_mat(Color(1, 0.95, 0.85) * 3.0)
	var jet := MeshInstance3D.new()
	var jm := CylinderMesh.new()
	jm.top_radius = 0.2
	jm.bottom_radius = 2.2
	jm.height = 1.0
	jet.mesh = jm
	jet.material_override = _glow_mat(colour * 4.0)
	var light := OmniLight3D.new()
	light.light_color = colour.lerp(Color.WHITE, 0.5)
	light.omni_range = 70.0
	light.shadow_enabled = false
	for n in [wave, glow, flash, jet]:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(n)
	add_child(light)
	_shots.append([0.0, wave, glow, flash, jet, light])

func _glow_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.albedo_color = c
	return m

## Advance the firing effects (real time).
func _process(delta: float) -> void:
	if _shots.is_empty(): return
	var a := to_local(gun_breech.global_position)
	var b := to_local(gun_muzzle.global_position)
	var axis := (b - a).normalized()
	var barrel := a.distance_to(b)
	var basis_y := Basis(Quaternion(Vector3.UP, axis))     # cylinder and torus meshes run along their local Y
	var done: Array = []
	for sh in _shots:
		sh[0] += delta
		var t: float = sh[0]
		var run := clampf(t / GUN_WAVE_TIME, 0.0, 1.0)              # how far the wave has got up the barrel
		var fade := clampf((t - GUN_WAVE_TIME) / GUN_FADE_TIME, 0.0, 1.0)
		var wave: MeshInstance3D = sh[1]
		wave.visible = run < 1.0
		wave.transform = Transform3D(basis_y, a + axis * barrel * run)
		var glow: MeshInstance3D = sh[2]
		var lit := maxf(0.02, barrel * run)                           # the barrel glows where the wave has passed
		glow.transform = Transform3D(basis_y * Basis.from_scale(Vector3(1, lit, 1)), a + axis * lit * 0.5)
		_set_alpha(glow, 0.55 * (1.0 - fade))
		var flash: MeshInstance3D = sh[3]
		var ft := clampf((t - GUN_WAVE_TIME) / 0.35, 0.0, 1.0)        # flash: grows fast, fades
		flash.visible = t >= GUN_WAVE_TIME
		flash.transform = Transform3D(Basis.from_scale(Vector3.ONE * (1.0 + 3.0 * sqrt(ft))), b)
		_set_alpha(flash, 1.0 - ft)
		var jet: MeshInstance3D = sh[4]
		var jl := 3.0 + 18.0 * sqrt(ft)                               # plasma jet streams forward and thins out
		jet.visible = t >= GUN_WAVE_TIME
		jet.transform = Transform3D(basis_y * Basis.from_scale(Vector3(1.0 + ft, jl, 1.0 + ft)), b + axis * jl * 0.5)
		_set_alpha(jet, 0.8 * (1.0 - ft))
		var light: OmniLight3D = sh[5]
		light.position = b
		light.light_energy = (6.0 * (1.0 - ft) if t >= GUN_WAVE_TIME else 2.0 * run)
		if t > GUN_WAVE_TIME + GUN_FADE_TIME:
			done.append(sh)
	for sh in done:
		for i in range(1, 6): (sh[i] as Node).queue_free()
		_shots.erase(sh)

func _set_alpha(mi: MeshInstance3D, alpha: float) -> void:
	var m := mi.material_override as StandardMaterial3D
	m.albedo_color.a = clampf(alpha, 0.0, 1.0)

func muzzle_position(k: int) -> Vector3:
	return (turrets[k][1] as Node3D).global_position

## Where a system sits, in world space (Drive, Laser, Gun, Sensors, Radiators, Crew), for HUD callouts.
func sys_position(sys: int) -> Vector3:
	return (sys_nodes[sys] as Node3D).global_position

## Where turret k sits, in world space.
func turret_position(k: int) -> Vector3:
	return (turrets[k][0] as Node3D).global_position

## Radiator panel texture: pale cells with dark seams, tinted by each panel's colour.
func _grid_texture() -> ImageTexture:
	var w := 64
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var seam := (y % 16) < 1 or x < 1 or x >= w - 1 or (x % 32) < 1
			var v := 0.55 if seam else 0.95 - 0.04 * ((y / 16) % 2)
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)

# ------------------------------------------------------------------ state

## Colour and animate from the sim's view of the ship.
func show_state(s: Dictionary, delta: float) -> void:
	var armor: PackedFloat64Array = s["armor_worst"]   # tint by the thinnest panel, so a breach shows red
	var armor_max: PackedFloat64Array = s["armor_max"]
	var st: PackedFloat64Array = s["structure"]
	var st_max: PackedFloat64Array = s["structure_max"]
	for k in 3:
		var c := Color.WHITE
		if view_mode == 1:
			var af: float = armor[k] / max(1.0, armor_max[k])
			var sf: float = st[k] / max(1.0, st_max[k])
			if af > 0.0:
				c = Color(0.25, 0.75, 0.55).lerp(Color(0.95, 0.65, 0.2), 1.0 - af)
			else:
				c = Color(0.95, 0.45, 0.15).lerp(Color(0.85, 0.1, 0.08), 1.0 - sf)
		# Material writes only when the tint changes (each write re-uploads the material's parameters).
		var key := c if view_mode == 1 else Color(-1, -1, -1)
		if key == _sec_shown[k]: continue
		_sec_shown[k] = key
		for part in sec_parts[k]:
			var m: StandardMaterial3D = part[0]
			if view_mode == 1:
				m.albedo_color = c
				m.emission = c * 0.35
			else:
				m.albedo_color = part[1]
				m.emission = Color.BLACK
	# radiators fold flat against the hull when stowed, and glow as heat climbs
	var target := 1.0 if s["radiators_extended"] else 0.0
	_rad_open = move_toward(_rad_open, target, delta * 0.8)
	var health: PackedFloat64Array = s["health"]
	var glow: float = clamp((float(s["heat"]) - 30.0) / 70.0, 0.0, 1.0) * 1.5
	if _rad_open != _rad_shown:
		_rad_shown = _rad_open
		for p: Node3D in rad_pivots:
			p.scale = Vector3(max(0.04, _rad_open), 1, 1)
	var rad_dead: bool = health[4] <= 0
	if absf(glow - _glow_shown) > 0.004 or rad_dead != _rad_dead_shown:
		_glow_shown = glow
		_rad_dead_shown = rad_dead
		for rd in radiators:
			var m: StandardMaterial3D = rd[0]
			m.emission_energy_multiplier = glow
			m.albedo_color = rd[1] if not rad_dead else Color(0.3, 0.06, 0.04)
	plume.visible = s["burning"]
	if plume.visible:
		var th: float = clampf(float(s["throttle"]), 0.0, 1.0)
		plume.scale = Vector3(1, 1, lerpf(DRIVE_PLUME_MIN, DRIVE_PLUME_MAX, th))
		plume_mat.set_shader_parameter("strength", lerpf(0.9, 3.2, th) * (0.94 + 0.06 * sin(Time.get_ticks_msec() * 0.03)))
	# OMS: the push in the battle plane, from (forward, left) in ship axes, turned into this model's own axes
	var oms: Vector2 = s["oms"]
	var h: float = s["heading"]
	var push_sim := Vector2(cos(h), sin(h)) * oms.x + Vector2(-sin(h), cos(h)) * oms.y
	var push_world := Vector3(push_sim.x, 0, -push_sim.y)
	_show_oms(global_transform.basis.inverse() * (-push_world) if oms.length() > 0.01 and is_inside_tree() else Vector3.ZERO)
	# knocked-out turrets: lens gone, dome scorched
	var thp: PackedFloat64Array = s["turret_hp"]
	for k in turrets.size():
		var dead := thp[k] <= 0
		(turrets[k][2] as MeshInstance3D).visible = not dead
		var dm: StandardMaterial3D = turrets[k][3]
		if view_mode == 0:
			var dc: Color = Color(0.22, 0.08, 0.05) if dead else turrets[k][4]
			if dm.albedo_color != dc: dm.albedo_color = dc
