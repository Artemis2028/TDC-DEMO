class_name ShipModel
extends Node3D
## A long-spine warship: a sensor bulb at the nose, a string of pressure modules and tanks on a thin spine,
## an open truss around the reactor and drive at the stern, and big flat radiator panels standing out from the
## hull (their planes contain the ship's axis, so they sit edge-on to the drive and to anything ahead).
## Three laser turrets on raised mounts ring the hull amidships, well away from the nose that takes enemy fire.
## The nose points along -Z. Everything is built from code; there are no imported meshes.

var length := 160.0
var mars := false
var view_mode := 0          # 0 real colour, 1 armour condition
var sec_parts: Array = [[], [], []]   # per section (nose, body, aft): [material, base colour]
var radiators: Array = []             # [pivot, panel, material, base colour, span]
var plume: MeshInstance3D
var pods: Array = []                  # OMS pods: [outward direction, radial jet, axial jet]
var turrets: Array = []               # [pivot (barrel along its -Z), muzzle, outward direction, ball, barrel]
const TURRET_ANGLES := [deg_to_rad(45.0), deg_to_rad(165.0), deg_to_rad(290.0)]
const OMS_FWD := 0.10      # OMS stations, as fractions of the length from the nose
const OMS_AFT := 0.80
const OMS_R := 2.3         # pod centres sit this many hull radii out from the axis
var _rad_open := 1.0
var _grid: ImageTexture

const HULL := Color(0.60, 0.63, 0.67)
const HULL_MARS := Color(0.66, 0.54, 0.44)
const BAND := Color(0.13, 0.14, 0.16)
const TRUSS := Color(0.30, 0.31, 0.33)

## Build the ship. gun_kind: 0 none, 1 railgun, 2 coilgun.
func build(is_mars: bool, gun_kind: int) -> void:
	mars = is_mars
	length = 130.0 if mars else 160.0
	_grid = _grid_texture()
	var hull_col := HULL_MARS if mars else HULL
	var r := 0.026 * length               # module radius
	var spine := 0.016 * length
	# --- nose: sensor bulb and the first module
	var nose_mat := _mat(hull_col, 0)
	_lathe([[0.0, 0.0], [0.004, 0.55], [0.012, 0.85], [0.024, 1.0], [0.036, 0.85], [0.044, 0.6]], r, nose_mat)
	_band(0.046, r * 0.75, 0.006, 0)
	_lathe([[0.048, 0.45], [0.06, 0.45]], r, nose_mat)
	_module(0.06, 0.17, r, nose_mat)
	# --- body: pressure modules, then the tank stack
	var body_mat := _mat(hull_col, 1)
	_lathe([[0.17, spine / r], [0.185, spine / r]], r, body_mat)
	_module(0.185, 0.31, r, body_mat)
	_lathe([[0.31, spine / r], [0.325, spine / r]], r, body_mat)
	_module(0.325, 0.45, r, body_mat)
	_lathe([[0.45, spine / r], [0.465, spine / r]], r, body_mat)
	_module(0.465, 0.62, r * 1.1, body_mat)
	_lathe([[0.62, spine / r], [0.632, spine / r]], r, body_mat)
	_module(0.632, 0.80, r * 1.2, body_mat)
	# hatches and windows: small dark marks on the modules
	for x in [0.11, 0.25, 0.38, 0.53]:
		for k in 3:
			_box(Vector3(r * 0.98, 0, _z(x + k * 0.012)), Vector3(r * 0.06, r * 0.18, length * 0.007), BAND, 1)
	# --- aft: open truss around the reactor, drive bell
	var aft_mat := _mat(hull_col, 2)
	var truss_mat := _mat(TRUSS, 2)
	_lathe([[0.80, 0.55], [0.97, 0.55]], r, truss_mat)           # reactor core inside the truss
	_truss(0.80, 0.955, r * 1.35, truss_mat)
	_lathe([[0.955, 0.6], [0.965, 1.15], [0.975, 1.15], [0.985, 0.7], [1.0, 1.25]], r, aft_mat)
	# --- radiators: (x along hull, angle around it, radial span, axial width, colour)
	var dark := Color(0.06, 0.065, 0.075)
	var bronze := Color(0.42, 0.33, 0.22) if not mars else Color(0.5, 0.3, 0.18)
	var light := Color(0.78, 0.8, 0.82)
	_radiator_pair(0.22, 0.0, 0.17, 0.07, light)
	_radiator_pair(0.27, PI / 2, 0.14, 0.035, dark)
	_radiator_pair(0.57, PI / 2, 0.40, 0.085, dark)
	_radiator_pair(0.70, PI / 2 + 0.95, 0.30, 0.11, bronze)
	# --- laser turrets: three raised barbettes around the hull amidships, between the radiator panels. Each is a
	# clean drum with a marking ring and a rotating dome; the emitter is a short lens tube in the dome.
	# Angles match the sim (kTurretAngle): measured about the axis from the ship's right (+X) toward its top (+Y).
	var lens_col := Color(0.35, 0.65, 1.0) if not mars else Color(1.0, 0.55, 0.3)
	var drum_mat := _mat(Color(0.7, 0.72, 0.75) if not mars else Color(0.7, 0.6, 0.5), 1)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.86, 0.7, 0.18)
	for k in TURRET_ANGLES.size():
		var a: float = TURRET_ANGLES[k]
		var out := Vector3(cos(a), sin(a), 0)
		var base := out * r * 0.85 + Vector3(0, 0, _z(0.40))
		var drum := MeshInstance3D.new()
		var dm := CylinderMesh.new()
		dm.top_radius = r * 0.40
		dm.bottom_radius = r * 0.46
		dm.height = r * 0.55
		drum.mesh = dm
		drum.material_override = drum_mat
		drum.transform = Transform3D(_basis_y(out), base + out * r * 0.27)
		add_child(drum)
		var ring := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = r * 0.415
		rm.bottom_radius = r * 0.415
		rm.height = r * 0.06
		ring.mesh = rm
		ring.material_override = ring_mat
		ring.transform = Transform3D(_basis_y(out), base + out * r * 0.45)
		add_child(ring)
		var piv := Node3D.new()
		piv.position = base + out * r * 0.55
		add_child(piv)
		var dome := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = r * 0.36
		sm.height = r * 0.72
		dome.mesh = sm
		dome.material_override = _mat(Color(0.82, 0.84, 0.86) if not mars else Color(0.78, 0.68, 0.58), 1)
		piv.add_child(dome)
		var tube := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r * 0.17
		cm.bottom_radius = r * 0.17
		cm.height = r * 0.5
		tube.mesh = cm
		tube.rotation.x = -PI / 2
		tube.position = Vector3(0, 0, -r * 0.3)
		tube.material_override = _mat(Color(0.25, 0.27, 0.3), 1)
		piv.add_child(tube)
		var lens := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = r * 0.13
		lm.bottom_radius = r * 0.13
		lm.height = r * 0.04
		lens.mesh = lm
		lens.rotation.x = -PI / 2
		lens.position = Vector3(0, 0, -r * 0.56)
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = lens_col
		lmat.emission_enabled = true
		lmat.emission = lens_col
		lmat.emission_energy_multiplier = 1.5
		lens.material_override = lmat
		piv.add_child(lens)
		var mz := Node3D.new()
		mz.position = Vector3(0, 0, -r * 0.6)
		piv.add_child(mz)
		turrets.append([piv, mz, out, dome, tube, lens])
	# --- spinal gun along the belly, muzzle just aft of the sensor bulb
	if gun_kind != 0:
		var gm := _mat(Color(0.62, 0.55, 0.42), 1)
		var y := -r * 1.45
		_rod(Vector3(0, y, _z(0.07)), Vector3(0, y, _z(0.74)), r * 0.16, gm)
		for x in [0.2, 0.35, 0.5, 0.65]:
			_rod(Vector3(0, -r * 0.9, _z(x)), Vector3(0, y, _z(x)), r * 0.08, gm)    # pylons
		if gun_kind == 2:
			var k := 0.09
			while k < 0.72:
				_ring(Vector3(0, y, _z(k)), r * 0.34, r * 0.07, gm)               # coil stages
				k += 0.035
		else:
			_rod(Vector3(r * 0.22, y, _z(0.08)), Vector3(r * 0.22, y, _z(0.70)), r * 0.09, gm)
			_rod(Vector3(-r * 0.22, y, _z(0.08)), Vector3(-r * 0.22, y, _z(0.70)), r * 0.09, gm)
	# --- OMS pods: thruster clusters on short booms at a forward and an aft station, so together they push the ship
	# without turning it. Forward pods fire forward (to slow), aft pods fire aft, and both fire outward for sideways
	# moves: no jet ever runs along the hull past the turrets or radiators.
	var pod_mat := _mat(Color(0.78, 0.8, 0.82) if not mars else Color(0.72, 0.62, 0.52), 1)
	var boom_mat := _mat(Color(0.4, 0.42, 0.45), 1)
	var noz_mat := StandardMaterial3D.new()
	noz_mat.albedo_color = Color(0.2, 0.2, 0.22)
	noz_mat.metallic = 0.6
	for st in [OMS_FWD, OMS_AFT]:
		for k in 4:
			var a := PI / 4 + k * PI / 2
			var out := Vector3(cos(a), sin(a), 0)
			var c := out * r * OMS_R + Vector3(0, 0, _z(st))
			_rod(out * r * 0.9 + Vector3(0, 0, _z(st)), c, r * 0.18, boom_mat)
			var ball := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = r * 0.42
			sm.height = r * 0.84
			ball.mesh = sm
			ball.material_override = pod_mat
			ball.position = c
			add_child(ball)
			# nozzles: one outward, one along the axis (forward on the forward pods, aft on the aft pods)
			var axial := Vector3(0, 0, -1 if st == OMS_FWD else 1)
			for d in [out, axial]:
				var nz := MeshInstance3D.new()
				var nm := CylinderMesh.new()
				nm.top_radius = r * 0.16
				nm.bottom_radius = r * 0.08
				nm.height = r * 0.22
				nm.cap_top = false
				nz.mesh = nm
				nz.material_override = noz_mat
				nz.transform = Transform3D(_basis_y(d), c + d * r * 0.46)
				add_child(nz)
			pods.append([out, st, _jet(r), _jet(r)])
	# --- drive plume
	plume = MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = r * 1.0
	pm.bottom_radius = r * 3.2
	pm.height = length * 0.8
	pm.cap_top = false
	pm.cap_bottom = false
	plume.mesh = pm
	plume.rotation.x = -PI / 2
	plume.position = Vector3(0, 0, length * 0.5 + length * 0.4)
	var plm := StandardMaterial3D.new()
	plm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	plm.albedo_color = Color(0.35, 0.28, 0.9, 0.55) if not mars else Color(0.9, 0.45, 0.25, 0.55)
	plm.cull_mode = BaseMaterial3D.CULL_DISABLED
	plume.material_override = plm
	plume.visible = false
	add_child(plume)

## A thruster jet: a short bright cone along its local -Y, hidden until used.
func _jet(r: float) -> MeshInstance3D:
	var j := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.45       # wide end away from the nozzle (+Y points along the exhaust)
	cm.bottom_radius = r * 0.15
	cm.height = r * 5.5
	cm.cap_top = false
	cm.cap_bottom = false
	j.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.82, 0.9, 1.0, 0.75)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
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

## Show the OMS jets for a burn: exhaust (local, ship axes) is opposite to the push. Sideways: the pod facing the
## exhaust direction at each station. Forward exhaust (slowing): the forward pods; aft exhaust: the aft pods.
func _show_oms(exhaust: Vector3) -> void:
	var r := 0.026 * length
	var radial := Vector3(exhaust.x, exhaust.y, 0)
	var best := {}
	for k in pods.size():
		var st: float = pods[k][1]
		var d: float = (pods[k][0] as Vector3).dot(radial.normalized()) if radial.length() > 0.2 else 0.0
		if d > 0.3 and d > float(best.get(st, [0.0, -1])[0]): best[st] = [d, k]
	for k in pods.size():
		var out: Vector3 = pods[k][0]
		var st: float = pods[k][1]
		var c := out * r * OMS_R + Vector3(0, 0, _z(st))
		var rj: MeshInstance3D = pods[k][2]
		rj.visible = best.has(st) and int(best[st][1]) == k
		if rj.visible:
			var dir := radial.normalized()
			var sc := clampf(radial.length(), 0.4, 1.0)
			rj.transform = Transform3D(_basis_y(dir), c + dir * r * (0.55 + 2.75 * sc)).scaled_local(Vector3.ONE * sc)
		var aj: MeshInstance3D = pods[k][3]
		var fwd_pod := st == OMS_FWD
		aj.visible = (exhaust.z < -0.2 and fwd_pod) or (exhaust.z > 0.2 and not fwd_pod)
		if aj.visible:
			var dz := Vector3(0, 0, signf(exhaust.z))
			var sc := clampf(absf(exhaust.z), 0.4, 1.0)
			aj.transform = Transform3D(_basis_y(dz), c + dz * r * (0.55 + 2.75 * sc)).scaled_local(Vector3.ONE * sc)

## Turn the turrets that bear toward a point in world space; the others park pointing forward along the hull.
func aim(world_target: Vector3, bears: Array) -> void:
	if not is_inside_tree(): return
	for k in turrets.size():
		var piv: Node3D = turrets[k][0]
		var on: bool = k < bears.size() and bool(bears[k])
		var tgt := world_target if on else piv.global_position - global_transform.basis.z * 1000.0
		var d := tgt - piv.global_position
		if d.length() < 1.0: continue
		var up: Vector3 = global_transform.basis * Vector3(turrets[k][2])
		if absf(d.normalized().dot(up.normalized())) > 0.99: up = global_transform.basis.z
		piv.look_at(tgt, up)

func muzzle_position(k: int) -> Vector3:
	return (turrets[k][1] as Node3D).global_position

## Where a system sits, in world space (Drive, Laser, Gun, Sensors, Radiators, Crew), for HUD callouts.
func sys_position(sys: int) -> Vector3:
	var r := 0.026 * length
	var local: Vector3 = [Vector3(0, 0, _z(0.97)), Vector3(0, r * 1.5, _z(0.40)), Vector3(0, -r * 1.45, _z(0.40)),
		Vector3(0, 0, _z(0.02)), Vector3(0, r * 4.0, _z(0.57)), Vector3(0, 0, _z(0.25))][sys]
	return global_transform * local

# ------------------------------------------------------------------ building blocks

func _z(x: float) -> float:
	return -length * 0.5 + x * length

func _mat(c: Color, section: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.5
	m.metallic = 0.25
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	sec_parts[section].append([m, c])
	return m

## A surface of revolution from (x fraction, radius as a multiple of r) points, with smooth normals.
func _lathe(profile: Array, r: float, m: StandardMaterial3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 40
	for i in range(profile.size() - 1):
		var z0 := _z(profile[i][0])
		var z1 := _z(profile[i + 1][0])
		var r0: float = profile[i][1] * r
		var r1: float = profile[i + 1][1] * r
		var slope := (r1 - r0) / maxf(0.001, z1 - z0)
		for k in seg:
			var t0 := TAU * k / seg
			var t1 := TAU * (k + 1) / seg
			var v := [Vector3(cos(t0) * r0, sin(t0) * r0, z0), Vector3(cos(t0) * r1, sin(t0) * r1, z1),
					  Vector3(cos(t1) * r1, sin(t1) * r1, z1), Vector3(cos(t1) * r0, sin(t1) * r0, z0)]
			var ang := [t0, t0, t1, t1]
			for idx in [0, 1, 2, 0, 2, 3]:
				var a: float = ang[idx]
				st.set_normal(Vector3(cos(a), sin(a), -slope).normalized())
				st.add_vertex(v[idx])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	add_child(mi)

## A pressure module: rounded ends, a dark band at each end.
func _module(a: float, b: float, r: float, m: StandardMaterial3D) -> void:
	var e := 0.012
	_lathe([[a, 0.62], [a + e * 0.3, 0.88], [a + e, 1.0], [b - e, 1.0], [b - e * 0.3, 0.88], [b, 0.62]], r, m)
	var section := 0 if b <= 0.17 else (1 if b <= 0.8 else 2)
	_band(a + e * 1.4, r * 1.03, 0.005, section)
	_band(b - e * 1.4, r * 1.03, 0.005, section)

func _band(x: float, r: float, w: float, _section: int) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = BAND
	m.roughness = 0.7
	_lathe([[x - w * 0.5, 1.0], [x + w * 0.5, 1.0]], r, m)

func _box(pos: Vector3, size: Vector3, c: Color, _section: int) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	mi.material_override = m
	mi.position = pos
	add_child(mi)

func _rod(a: Vector3, b: Vector3, thick: float, m: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(thick, thick, a.distance_to(b))
	mi.mesh = bm
	mi.material_override = m
	var dir := (b - a).normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	mi.transform = Transform3D(Basis.looking_at(dir, up), (a + b) * 0.5)
	add_child(mi)

func _ring(pos: Vector3, r: float, w: float, m: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - w
	tm.outer_radius = r
	tm.rings = 20
	tm.ring_segments = 8
	mi.mesh = tm
	mi.material_override = m
	mi.rotation.x = PI / 2
	mi.position = pos
	add_child(mi)

## An open truss: eight longerons, ring frames and diagonal braces.
func _truss(a: float, b: float, r: float, m: StandardMaterial3D) -> void:
	var n := 8
	var frames := 5
	var t := r * 0.07
	for k in n:
		var ang := TAU * k / n
		var p := Vector3(cos(ang) * r, sin(ang) * r, 0)
		_rod(p + Vector3(0, 0, _z(a)), p + Vector3(0, 0, _z(b)), t, m)
	for f in frames + 1:
		var z := _z(lerpf(a, b, float(f) / frames))
		for k in n:
			var a0 := TAU * k / n
			var a1 := TAU * (k + 1) / n
			_rod(Vector3(cos(a0) * r, sin(a0) * r, z), Vector3(cos(a1) * r, sin(a1) * r, z), t * 0.9, m)
		if f < frames:
			var z1 := _z(lerpf(a, b, float(f + 1) / frames))
			for k in n:
				var a0 := TAU * k / n
				var a1 := TAU * (k + 1) / n
				var s := 1 if (k + f) % 2 == 0 else -1
				var p0 := Vector3(cos(a0) * r, sin(a0) * r, z if s > 0 else z1)
				var p1 := Vector3(cos(a1) * r, sin(a1) * r, z1 if s > 0 else z)
				_rod(p0, p1, t * 0.6, m)

## Two flat panels standing out from the hull on opposite sides, in a plane containing the ship's axis.
func _radiator_pair(x: float, angle: float, span: float, width: float, c: Color) -> void:
	for side in 2:
		var pivot := Node3D.new()
		pivot.position = Vector3(0, 0, _z(x))
		pivot.rotation.z = angle + side * PI
		var panel := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(span * length, 0.35, width * length)
		panel.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.albedo_texture = _grid
		m.uv1_scale = Vector3(3, 2, 1)
		m.roughness = 0.6
		m.metallic = 0.15
		m.emission_enabled = true
		m.emission = Color(0.55, 0.12, 0.03)
		m.emission_energy_multiplier = 0.0
		panel.material_override = m
		pivot.add_child(panel)
		add_child(pivot)
		radiators.append([pivot, panel, m, c, span * length])

## Panel texture: pale cells with dark seams, tinted by each panel's colour.
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
	var armor: PackedFloat64Array = s["armor"]
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
		for part in sec_parts[k]:
			var m: StandardMaterial3D = part[0]
			if view_mode == 1:
				m.albedo_color = c
				m.emission_enabled = true
				m.emission = c * 0.35
			else:
				m.albedo_color = part[1]
				m.emission_enabled = false
	var target := 1.0 if s["radiators_extended"] else 0.0
	_rad_open = move_toward(_rad_open, target, delta * 0.8)
	var health: PackedFloat64Array = s["health"]
	var glow: float = clamp((float(s["heat"]) - 30.0) / 70.0, 0.0, 1.0) * 1.5
	var hull_r := 0.026 * length
	for rd in radiators:
		var panel: MeshInstance3D = rd[1]
		var span: float = rd[4]
		var open: float = max(0.06, _rad_open)
		panel.scale = Vector3(open, 1, 1)
		panel.position.x = hull_r * 0.8 + span * 0.5 * open
		var m: StandardMaterial3D = rd[2]
		m.emission_energy_multiplier = glow
		m.albedo_color = rd[3] if health[4] > 0 else Color(0.3, 0.06, 0.04)
	plume.visible = s["burning"]
	# OMS: the push in the battle plane, from (forward, left) in ship axes, turned into this model's own axes
	var oms: Vector2 = s["oms"]
	var h: float = s["heading"]
	var push_sim := Vector2(cos(h), sin(h)) * oms.x + Vector2(-sin(h), cos(h)) * oms.y
	var push_world := Vector3(push_sim.x, 0, -push_sim.y)
	_show_oms(global_transform.basis.inverse() * (-push_world) if oms.length() > 0.01 and is_inside_tree() else Vector3.ZERO)
	# knocked-out turrets go dark
	var thp: PackedFloat64Array = s["turret_hp"]
	for k in turrets.size():
		var dead := thp[k] <= 0
		(turrets[k][5] as MeshInstance3D).visible = not dead          # lens shattered
		var bm := (turrets[k][3] as MeshInstance3D).material_override as StandardMaterial3D
		if view_mode == 0 and dead:
			bm.albedo_color = Color(0.22, 0.08, 0.05)                    # scorched dome

## Where turret k sits, in world space.
func turret_position(k: int) -> Vector3:
	return (turrets[k][0] as Node3D).global_position
