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
var turrets: Array = []               # [pivot (barrel along its -Z), muzzle, outward direction, ball, barrel]
const TURRET_ANGLES := [deg_to_rad(45.0), deg_to_rad(165.0), deg_to_rad(290.0)]
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
	# --- laser turrets: three raised mounts around the hull amidships, between the radiator panels.
	# Angles match the sim (kTurretAngle): measured about the axis from the ship's right (+X) toward its top (+Y).
	var lens_col := Color(0.3, 0.6, 0.9) if not mars else Color(0.95, 0.5, 0.25)
	for k in TURRET_ANGLES.size():
		var a: float = TURRET_ANGLES[k]
		var out := Vector3(cos(a), sin(a), 0)
		var mount := Node3D.new()
		mount.position = out * r * 1.0 + Vector3(0, 0, _z(0.40))
		add_child(mount)
		var post := MeshInstance3D.new()
		var pm0 := CylinderMesh.new()
		pm0.top_radius = r * 0.22
		pm0.bottom_radius = r * 0.3
		pm0.height = r * 0.5
		post.mesh = pm0
		post.material_override = _mat(Color(0.45, 0.47, 0.5), 1)
		post.transform = Transform3D(Basis(Quaternion(Vector3.UP, out)), out * r * 0.25)
		mount.add_child(post)
		var piv := Node3D.new()
		piv.position = out * r * 0.55
		mount.add_child(piv)
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = r * 0.42
		sm.height = r * 0.84
		ball.mesh = sm
		ball.material_override = _mat(Color(0.55, 0.58, 0.62), 1)
		piv.add_child(ball)
		var barrel := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r * 0.13
		cm.bottom_radius = r * 0.18
		cm.height = r * 1.3
		barrel.mesh = cm
		barrel.rotation.x = -PI / 2
		barrel.position = Vector3(0, 0, -r * 0.65)
		barrel.material_override = _mat(lens_col, 1)
		piv.add_child(barrel)
		var mz := Node3D.new()
		mz.position = Vector3(0, 0, -r * 1.3)
		piv.add_child(mz)
		turrets.append([piv, mz, out, ball, barrel])
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
	# knocked-out turrets go dark
	var thp: PackedFloat64Array = s["turret_hp"]
	for k in turrets.size():
		var dead := thp[k] <= 0
		(turrets[k][4] as MeshInstance3D).visible = not dead
		var bm := (turrets[k][3] as MeshInstance3D).material_override as StandardMaterial3D
		if view_mode == 0:
			bm.albedo_color = Color(0.25, 0.08, 0.05) if dead else Color(0.55, 0.58, 0.62)

## Where turret k sits, in world space.
func turret_position(k: int) -> Vector3:
	return (turrets[k][0] as Node3D).global_position
