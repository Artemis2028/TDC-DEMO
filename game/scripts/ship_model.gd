class_name ShipModel
extends Node3D
## A ship as the game draws it. Mars and the lasers-only Dagger come from models/mars.glb and models/earth.glb
## (art/build_ships.py, art/import_dagger.py). The Lance, the Earth ship that carries the coilgun, is the Arbiter
## TDC v8 hull (models/arbiter.glb): same axis convention, its own mesh, and the clips exported with it.
## This script finds the named parts and brings them to life: turrets turn toward the target, radiators fold and
## glow with heat, OMS jets and the drive plume show the burn, knocked-out turrets go dark, and the armour view
## tints each hull section by its condition.
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
## Laser light. A beam in vacuum is invisible from the side (nothing scatters it), so what shows is what it does: a
## spot on the target's hull heating from dull red to white the longer the beam dwells, and a faint glow at each
## firing emitter. The line between them is a HUD fire-control line drawn by main.gd, not light.
var hull_r := 5.0                     # rough hull radius and nose/tail extent along Z (local), from the hull parts
var hull_z := Vector2(-80, 80)
var spot: MeshInstance3D              # hot spot where beams land on this ship: core and halo, kept facing the camera
var spot_halo: MeshInstance3D
var spot_heat := 0.0                  # 0 cold .. 1 white hot
var spot_key := Vector2i(-9, -9)      # what is being burnt (system, turret): a new aim point starts cold
var spot_normal := Vector3.UP         # outward hull normal at the spot (world), to hide it on the far side
var emitters: Array = []              # glow at each turret's emitter while it fires
static var _glow_tex: GradientTexture2D
var gun_breech: Node3D                # barrel ends of the spinal gun (markers from the Blender scripts)
var gun_muzzle: Node3D
var _shots: Array = []               # firing effects in progress: [age s, wave ring, barrel glow, muzzle flash, jet, light]
## Lance only. The Arbiter is a different hull from the Dagger, so it keeps its own rig and the glTF clips.
var arbiter := false
var _arbiter_rig: Array = []         # per sim turret: [yaw, pitch, rest yaw, rest pitch, beam dir in yaw space, head materials, alpha, beta]
var _rad_player: AnimationPlayer
var _drive_player: AnimationPlayer
var _gun_player: AnimationPlayer
var _drive_node: Node3D
var _drive_clip := ""
var _oms_jets: Array = []            # [node, exhaust direction in ship space, station "F"/"A"]
var _gun_fx: Array = []              # coil glows and muzzle flash, hidden until a shot
var _gun_fx_left := 0.0
## Armoured nose tip to the drive throat in the authored file. Scaled up to the Earth length both classes share.
const ARBITER_NATIVE_LENGTH := 161.36
## Sim turret 0, 1, 2 (mounts at 45, 135, 315 deg) -> the visual head whose mount is nearest: dorsal, port, starboard.
const ARBITER_TURRET_VISUAL := [2, 1, 3]
## Gun firing effect timing (real seconds, not battle time, so it reads the same at any time speed).
const GUN_WAVE_TIME := 0.16           # the light running up the coils, breech to muzzle
const GUN_FADE_TIME := 0.9            # barrel afterglow and muzzle flash fading out

const OMS_FWD := 0.10      # OMS stations (fractions of the length from the nose); kept in step with build_ships.py
const OMS_AFT := 0.765

## Build the ship. gun_kind: 0 none, 1 railgun, 2 coilgun.
## Earth has two hulls: the Dagger (lasers only) keeps models/earth.glb; the Lance (coilgun) is the Arbiter.
func build(is_mars: bool, gun_kind: int) -> void:
	mars = is_mars
	length = 130.0 if mars else 193.6
	if not mars and gun_kind == 2:
		_build_arbiter()
		return
	var root: Node3D = (load("res://models/mars.glb" if mars else "res://models/earth.glb") as PackedScene).instantiate()
	add_child(root)
	_bind_hull_materials(root, _grid_texture())
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
	# Hull size, for where a beam lands on the skin: the box around the section hull parts (not radiators or turrets)
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in root.get_children().filter(func(n): return n is MeshInstance3D):
		var nm := String(mi.name)
		if not (nm.begins_with("N_") or nm.begins_with("B_") or nm.begins_with("A_")): continue
		var bb: AABB = mi.transform * mi.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	hull_r = 0.5 * minf(box.size.x, box.size.y)
	hull_z = Vector2(box.position.z, box.end.z)
	_build_beam_glows()
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
	if arbiter:
		_aim_arbiter(aims)
		return
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
	if arbiter:
		_fire_arbiter_gun()
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
	if arbiter and _gun_fx_left > 0.0:
		_gun_fx_left -= delta
		if _gun_fx_left <= 0.0:
			for n: Node3D in _gun_fx:
				n.visible = false
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

# ------------------------------------------------------------------ laser glows

## A soft round glow texture (white centre fading to clear), shared by every glow.
static func _glow_texture() -> GradientTexture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.25, Color(1, 1, 1, 0.75))
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 64
		_glow_tex.height = 64
	return _glow_tex

## A camera-facing additive glow quad. Drawn without the depth test so the hull doesn't cut it in half; the spot is
## hidden instead when its side of the hull faces away from the camera (main.gd, hot_spot_faces).
func _glow_quad(size: float) -> MeshInstance3D:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	q.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true        # the node's scale sets the glow's size
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.albedo_texture = _glow_texture()
	q.material_override = m
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.visible = false
	return q

func _build_beam_glows() -> void:
	spot = _glow_quad(1.0)
	spot_halo = _glow_quad(1.0)
	add_child(spot_halo)
	add_child(spot)
	for t in turrets:
		var e := _glow_quad(1.6)
		(e.material_override as StandardMaterial3D).albedo_color = (Color(1.0, 0.7, 0.45) if mars else Color(0.7, 0.85, 1.0)) * 1.4
		(t[1] as Node3D).add_child(e)
		emitters.append(e)

## Emitter glows: on while that turret fires.
func show_emitters(firing: Array) -> void:
	for k in mini(emitters.size(), firing.size()):
		(emitters[k] as MeshInstance3D).visible = bool(firing[k])

## Where a beam aimed at system sys (turret k for the lasers) lands on this hull, seen from the shooter: on the
## skin beside the system, on the side facing the shooter (or the end cap when the shooter is nearly on the axis).
## Returns [local position, local outward normal].
func beam_landing(sys: int, k: int, shooter: Vector3) -> Array:
	var d := (global_transform.basis.inverse() * (shooter - global_position)).normalized()
	if sys == 1 and k >= 0 and k < turrets.size():
		var tp: Vector3 = to_local(turret_position(k))
		var tn := Vector3(tp.x, tp.y, 0)
		return [tp, tn.normalized() if tn.length() > 0.01 else Vector3.UP]
	var p: Vector3 = to_local(sys_position(sys))
	var radial := Vector3(d.x, d.y, 0)
	if radial.length() < 0.174:           # within 10 deg of nose- or tail-on: the end cap (as the sim's centre panel)
		var zc := hull_z.x if d.z < 0 else hull_z.y
		return [Vector3(0, 0, zc), Vector3(0, 0, signf(d.z))]
	radial = radial.normalized()
	return [Vector3(0, 0, p.z) + radial * hull_r, radial]

## The hot spot on this ship. beams: how many enemy beams are on it; sys, k: what they aim at; shooter: their
## world position; dt: battle seconds this frame (0 when paused, so the glow holds). Heat climbs toward white over a
## couple of seconds of dwell and cools in about one and a half once the beams stop.
func update_spot(beams: int, sys: int, k: int, shooter: Vector3, dt: float) -> void:
	if beams > 0:
		var key := Vector2i(sys, k)
		if key != spot_key:
			spot_key = key
			spot_heat = 0.0
		var land := beam_landing(sys, k, shooter)
		spot.position = land[0] + (land[1] as Vector3) * 0.6
		spot_halo.position = spot.position
		spot_normal = global_transform.basis * (land[1] as Vector3)
		spot_heat = minf(1.0, spot_heat + dt * (1.0 - spot_heat) * (0.25 + 0.35 * beams))
	else:
		spot_heat = maxf(0.0, spot_heat - dt * maxf(spot_heat, 0.05) / 1.5)
	var on := spot_heat > 0.02
	spot.visible = on
	spot_halo.visible = on
	if not on: return
	var h := spot_heat
	# dull red to orange to near-white as the plate heats (roughly a blackbody's colours)
	var c := Color(0.9, 0.12, 0.02).lerp(Color(1.0, 0.45, 0.08), clampf(h / 0.6, 0.0, 1.0))
	c = c.lerp(Color(1.0, 0.92, 0.75), clampf((h - 0.6) / 0.4, 0.0, 1.0))
	var flick := 0.92 + 0.08 * sin(Time.get_ticks_msec() * 0.05)
	var core := (0.8 + 1.6 * h) * flick                  # a burn a metre or two across, metres of glow around it
	spot.scale = Vector3.ONE * core
	spot_halo.scale = Vector3.ONE * core * 2.4
	(spot.material_override as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, 1.0) * (1.1 + 1.6 * h)
	var hc := c * (0.5 + 0.6 * h)
	hc.a = 0.2 + 0.15 * h
	(spot_halo.material_override as StandardMaterial3D).albedo_color = hc

## World position of the hot spot (for the fire-control lines).
func spot_position() -> Vector3:
	return spot.global_position

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
	if arbiter:
		_show_arbiter(s, glow)
	else:
		if _rad_open != _rad_shown:
			_rad_shown = _rad_open
			for p: Node3D in rad_pivots:
				p.scale = Vector3(max(0.04, _rad_open), 1, 1)
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
	var rad_dead: bool = health[4] <= 0
	if absf(glow - _glow_shown) > 0.004 or rad_dead != _rad_dead_shown:
		_glow_shown = glow
		_rad_dead_shown = rad_dead
		for rd in radiators:
			var rm: StandardMaterial3D = rd[0]
			rm.emission_energy_multiplier = glow
			rm.albedo_color = rd[1] if not rad_dead else Color(0.3, 0.06, 0.04)
	# knocked-out turrets: lens gone, dome scorched
	var thp: PackedFloat64Array = s["turret_hp"]
	for k in turrets.size():
		var dead := thp[k] <= 0
		(turrets[k][2] as MeshInstance3D).visible = not dead
		var dm: StandardMaterial3D = turrets[k][3]
		if view_mode == 0:
			var dc: Color = Color(0.22, 0.08, 0.05) if dead else turrets[k][4]
			if dm.albedo_color != dc: dm.albedo_color = dc
		if arbiter and k < _arbiter_rig.size() and view_mode == 0:
			for part in _arbiter_rig[k][5]:
				var hm: StandardMaterial3D = part[0]
				var hc: Color = Color(0.22, 0.08, 0.05) if dead else part[1]
				if hm.albedo_color != hc: hm.albedo_color = hc

# ------------------------------------------------------------------ materials

## Copies of the hull materials, one per source material and role, so tinting this ship never touches another.
## Section meshes are named N_ / B_ / A_. Radiator fins under a RadPivot glow with heat.
func _bind_hull_materials(root: Node3D, grid: ImageTexture) -> void:
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

# ------------------------------------------------------------------ Arbiter (Lance)

## The coilgun Earth's hull. Native metres are a little shorter than the Dagger, so the root is scaled to the
## Earth length the camera, nameplate and sensor view already assume. Nose, origin and axes already match.
func _build_arbiter() -> void:
	arbiter = true
	var root: Node3D = (load("res://models/arbiter.glb") as PackedScene).instantiate()
	root.scale = Vector3.ONE * (length / ARBITER_NATIVE_LENGTH)
	add_child(root)
	_bind_hull_materials(root, _grid_texture())
	_bind_arbiter_radiators(root)
	_build_arbiter_turrets(root)
	_build_arbiter_markers(root)
	_build_arbiter_oms(root)
	_build_arbiter_anims(root)
	var far := root.find_child("Target_Track_Point", true, false) as Node3D
	if far: far.position = Vector3.ZERO
	# Hull size from the section meshes, in this node's space (the root scale included).
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name)
		# The pressure hull only. Mounts, doors and the point-defence lattices sit outside it and would
		# push a beam's hot spot off the skin.
		if nm != "N_hull" and nm != "B_hull" and nm != "A_hull": continue
		var bb: AABB = _xform_under(mi) * mi.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	if not first:
		hull_r = 0.5 * minf(box.size.x, box.size.y)
		hull_z = Vector2(box.position.z, box.end.z)
	_build_beam_glows()
	# The Arbiter brings its own plume. This dummy keeps the Dagger path's field from being read unready.
	plume = MeshInstance3D.new()
	plume.visible = false
	add_child(plume)
	plume_mat = ShaderMaterial.new()

## Transform of n in this ship's space, including the scaled model root. Valid before the ship enters the tree.
func _xform_under(n: Node3D) -> Transform3D:
	var x := Transform3D.IDENTITY
	var p: Node = n
	while p != null and p != self:
		x = (p as Node3D).transform * x
		p = p.get_parent()
	return x

## Dark radiator skins glow with heat, the same way the Dagger's fins do. One shared copy per source material.
func _bind_arbiter_radiators(root: Node3D) -> void:
	var copies := {}
	for mi: MeshInstance3D in root.find_children("Radiator_*Geo", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			var src := mi.get_active_material(si) as StandardMaterial3D
			if src == null: continue
			var id := src.get_instance_id()
			if copies.has(id):
				mi.set_surface_override_material(si, copies[id])
				continue
			var m := src.duplicate() as StandardMaterial3D
			copies[id] = m
			mi.set_surface_override_material(si, m)
			if m.albedo_color.get_luminance() < 0.25:
				m.emission_enabled = true
				m.emission = Color(0.55, 0.12, 0.03)
				m.emission_energy_multiplier = 0.0
				radiators.append([m, m.albedo_color])

## Three laser heads. Each sim turret drives the visual mount nearest its arc, and a marker at the aperture
## (the beam mesh itself stays hidden: a beam in vacuum is not drawn).
func _build_arbiter_turrets(root: Node3D) -> void:
	for k in 3:
		var vis: int = ARBITER_TURRET_VISUAL[k]
		var tag := "%02d" % vis
		var yaw := root.find_child("Turret_%s_Yaw" % tag, true, false) as Node3D
		var pitch := root.find_child("Turret_%s_Pitch" % tag, true, false) as Node3D
		var beam := root.find_child("Turret_%s_LaserBeam" % tag, true, false) as Node3D
		if yaw == null or pitch == null or beam == null:
			push_error("Arbiter turret %s is missing a yaw, pitch or beam node" % tag)
			continue
		beam.visible = false
		var muzzle := Marker3D.new()
		muzzle.name = "Muzzle%d" % k
		muzzle.position = beam.position
		pitch.add_child(muzzle)
		var b0: Vector3 = (pitch.transform.basis * (beam.transform.basis * Vector3.UP)).normalized()
		var mats: Array = []
		var geo := root.find_child("Turret_%s_Pitch_Geo" % tag, true, false) as MeshInstance3D
		if geo:
			for si in geo.mesh.get_surface_count():
				var src := geo.get_active_material(si) as StandardMaterial3D
				if src == null: continue
				var m := src.duplicate() as StandardMaterial3D
				geo.set_surface_override_material(si, m)
				mats.append([m, m.albedo_color])
		# Stand-in for the Dagger's lens mesh, so the shared dead-turret path has a node to hide.
		# It has to live in the tree: an orphaned MeshInstance3D leaks its cull instance on quit.
		var lens := MeshInstance3D.new()
		lens.name = "Lens%d" % k
		pitch.add_child(lens)
		var dummy := StandardMaterial3D.new()
		_arbiter_rig.append([yaw, pitch, yaw.quaternion, pitch.quaternion, b0, mats, 0.0, 0.0])
		turrets.append([pitch, muzzle, lens, dummy, dummy.albedo_color, yaw, yaw.basis, pitch.basis, 0.0])

## Reference points the HUD, the hot spot and the firing effect already look up by name.
func _build_arbiter_markers(root: Node3D) -> void:
	var recoil := root.find_child("Coilgun_A093_Barrel_Recoil", true, false) as Node3D
	var flash := root.find_child("Coilgun_MuzzleFlash", true, false) as Node3D
	gun_breech = recoil
	gun_muzzle = flash
	# Drive, Laser, Gun, Sensors, Radiators, Crew, in authored metres (the root scale carries them out).
	var places := [Vector3(0, 0, 74), Vector3(0, 14, -29), Vector3(0, -12.4, -36),
		Vector3(0, 13, 23), Vector3(0, 22, 50), Vector3(0, 0, -55)]
	for i in places.size():
		var m := Marker3D.new()
		m.name = "Sys%d" % i
		m.position = places[i]
		root.add_child(m)
		sys_nodes.append(m)
	for n in root.find_children("Coilgun_Coil_*_Glow", "Node3D", true, false):
		if String(n.name).ends_with("_Geo"): continue
		n.visible = false
		n.scale = Vector3.ZERO
		_gun_fx.append(n)
	for nm in ["Coilgun_MuzzleFlash", "Coilgun_MuzzleFlare"]:
		var fx := root.find_child(nm, true, false) as Node3D
		if fx:
			fx.visible = false
			_gun_fx.append(fx)
	var shot := root.find_child("Coilgun_Projectile", true, false) as Node3D
	if shot: shot.visible = false
	_drive_node = root.find_child("MainDrive_A001-A004_Plume", true, false) as Node3D
	if _drive_node:
		_drive_node.visible = false

## The model's own bells. Radial and tangent plumes point across the hull; fore and aft stations stand in for a
## burn along the ship, the same stations the Dagger lights.
func _build_arbiter_oms(root: Node3D) -> void:
	var clusters := [
		["OMS_A010_Fore_Bottom", "F"], ["OMS_A011_Fore_Port", "F"], ["OMS_A012_Fore_Stbd", "F"], ["OMS_A013_Fore_Top", "F"],
		["OMS_A006_Aft_Bottom", "A"], ["OMS_A007_Aft_Port", "A"], ["OMS_A008_Aft_Stbd", "A"], ["OMS_A009_Aft_Top", "A"],
	]
	for c in clusters:
		for kind in ["Radial", "TangentA", "TangentB"]:
			var n := root.find_child("%s_Plume_%s" % [c[0], kind], true, false) as Node3D
			if n == null: continue
			var dir := (_xform_under(n).basis * Vector3.UP).normalized()
			n.visible = false
			n.scale = Vector3.ZERO
			_oms_jets.append([n, dir, c[1]])

func _share_player(src: AnimationPlayer, pname: String) -> AnimationPlayer:
	var p := AnimationPlayer.new()
	p.name = pname
	src.get_parent().add_child(p)
	p.root_node = src.root_node
	var lib := AnimationLibrary.new()
	for lname in src.get_animation_library_list():
		var slib := src.get_animation_library(lname)
		for aname in slib.get_animation_list():
			lib.add_animation(aname, slib.get_animation(aname).duplicate())
	p.add_animation_library("", lib)
	return p

## Clips stay on the imported player. Radiators are posed from RadiatorDeploy (0 stowed, 1 deployed). The drive
## and the gun each have their own player so a shot does not cancel the wings.
func _build_arbiter_anims(root: Node3D) -> void:
	var ap := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		push_error("Arbiter model has no AnimationPlayer")
		return
	_rad_player = ap
	_drive_player = _share_player(ap, "DriveAnims")
	_gun_player = _share_player(ap, "GunAnims")
	for nm in ["MainDriveIdle", "MainDriveLow", "MainDriveMedium", "MainDriveFull"]:
		if _drive_player.has_animation(nm):
			_drive_player.get_animation(nm).loop_mode = Animation.LOOP_LINEAR
	if _rad_player.has_animation("RadiatorDeploy"):
		var anim := _rad_player.get_animation("RadiatorDeploy")
		_rad_player.speed_scale = 0.0
		_rad_player.play("RadiatorDeploy")
		_rad_player.seek(anim.length, true)
		_rad_player.pause()

## Point the visual head along the sim's aim. Yaw spins the mount about its local Y; pitch, about the head's
## local Z. The beam mesh lies in the yaw node's XY plane, so pitch sets the component along the yaw axis and
## yaw swings the rest.
func _aim_arbiter(aims: Array) -> void:
	for k in mini(_arbiter_rig.size(), aims.size()):
		var rec: Array = _arbiter_rig[k]
		var yaw: Node3D = rec[0]
		var pitch: Node3D = rec[1]
		var rest_y: Quaternion = rec[2]
		var rest_p: Quaternion = rec[3]
		var b0: Vector3 = rec[4]
		var a: Vector3 = aims[k]
		var world_dir := (global_transform.basis.orthonormalized() * Vector3(a.y, a.z, -a.x)).normalized()
		var parent_basis := (yaw.get_parent() as Node3D).global_transform.basis.orthonormalized()
		var d_local := (rest_y.inverse() * (parent_basis.inverse() * world_dir)).normalized()
		var y := clampf(d_local.y, -1.0, 1.0)
		var xmag := sqrt(maxf(0.0, 1.0 - y * y))
		var x := xmag if b0.x >= 0.0 else -xmag
		var alpha: float = rec[6]
		if absf(x) > 0.02:
			alpha = atan2(-d_local.z / x, d_local.x / x)
		var beta := atan2(y, x) - atan2(b0.y, b0.x)
		beta = wrapf(beta, -PI, PI)
		rec[6] = alpha
		rec[7] = beta
		yaw.quaternion = rest_y * Quaternion(Vector3(0, 1, 0), alpha)
		pitch.quaternion = rest_p * Quaternion(Vector3(0, 0, 1), beta)

func _show_arbiter(s: Dictionary, _glow: float) -> void:
	if _rad_player and _rad_player.has_animation("RadiatorDeploy") and _rad_open != _rad_shown:
		_rad_shown = _rad_open
		var anim := _rad_player.get_animation("RadiatorDeploy")
		_rad_player.speed_scale = 0.0
		_rad_player.play("RadiatorDeploy")
		_rad_player.seek(_rad_open * anim.length, true)
		_rad_player.pause()
	if _drive_node:
		var burning: bool = s["burning"]
		_drive_node.visible = burning
		if burning and _drive_player:
			var th: float = clampf(float(s["throttle"]), 0.0, 1.0)
			var clip := "MainDriveFull" if th > 0.8 else ("MainDriveMedium" if th > 0.45 else ("MainDriveLow" if th > 0.15 else "MainDriveIdle"))
			if clip != _drive_clip:
				_drive_clip = clip
				_drive_player.play(clip)
		elif _drive_player and _drive_player.is_playing():
			_drive_player.stop()
			_drive_clip = ""
	var oms: Vector2 = s["oms"]
	var exhaust := Vector3.ZERO
	if oms.length() > 0.01 and is_inside_tree():
		var h: float = s["heading"]
		var push_sim := Vector2(cos(h), sin(h)) * oms.x + Vector2(-sin(h), cos(h)) * oms.y
		var push_world := Vector3(push_sim.x, 0, -push_sim.y)
		exhaust = global_transform.basis.inverse() * (-push_world)
	_show_oms_arbiter(exhaust)

func _show_oms_arbiter(exhaust: Vector3) -> void:
	var radial := Vector3(exhaust.x, exhaust.y, 0)
	var radial_n := radial.normalized() if radial.length() > 0.2 else Vector3.ZERO
	for rec in _oms_jets:
		var n: Node3D = rec[0]
		var dir: Vector3 = rec[1]
		var station: String = rec[2]
		var on := false
		if radial_n != Vector3.ZERO and dir.dot(radial_n) > 0.55:
			on = true
		if exhaust.z < -0.2 and station == "F":
			on = true
		if exhaust.z > 0.2 and station == "A":
			on = true
		n.visible = on
		n.scale = Vector3.ONE if on else Vector3.ZERO

## The coil lights in the model (CoilgunFire) plus the running wave the other ships use. The model's projectile
## stays hidden: the round in flight is the one main.gd draws from the sim.
func _fire_arbiter_gun() -> void:
	if _gun_player == null or not _gun_player.has_animation("CoilgunFire"): return
	for n: Node3D in _gun_fx:
		n.visible = true
	_gun_player.play("CoilgunFire")
	_gun_fx_left = _gun_player.get_animation("CoilgunFire").length
