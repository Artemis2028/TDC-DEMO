class_name ShipModel
extends Node3D
## A ship drawn from a few numbers: a lathe-turned hull in three sections (nose, body, aft), radiator wings that
## fold, a drive plume, a laser turret and, if fitted, a spinal gun. The nose points along -Z.

var length := 110.0
var mars := false
var sections: Array[MeshInstance3D] = []
var section_mats: Array[StandardMaterial3D] = []
var radiators: Array[Node3D] = []
var plume: MeshInstance3D
var turret: Node3D
var view_mode := 0          # 0 real colour, 1 armour condition
var _rad_open := 1.0

const PROFILE := [[0.0, 0.02], [0.27, 0.055], [0.80, 0.055], [0.93, 0.045], [1.0, 0.045]]   # (x / L, r / L)
const SPLITS := [0.0, 0.27, 0.80, 1.0]

func build(is_mars: bool, has_gun: bool) -> void:
	mars = is_mars
	var hull_col := Color(0.78, 0.66, 0.56) if mars else Color(0.86, 0.86, 0.84)
	for k in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = _lathe(SPLITS[k], SPLITS[k + 1])
		var m := StandardMaterial3D.new()
		m.albedo_color = hull_col
		m.roughness = 0.55
		m.metallic = 0.2
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
		add_child(mi)
		sections.append(mi)
		section_mats.append(m)
	# Radiator wings: four panels on the body, folding flat against the hull.
	for i in 4:
		var pivot := Node3D.new()
		pivot.position = Vector3(0, 0, -length * 0.5 + length * 0.62)
		pivot.rotation.z = PI / 4 + i * PI / 2
		var wing := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(length * 0.20, 0.3, length * 0.32)
		wing.mesh = bm
		wing.position = Vector3(length * 0.055 + length * 0.10, 0, 0)
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.13, 0.13, 0.15)
		wm.emission_enabled = true
		wm.emission = Color(0.5, 0.1, 0.03)
		wm.emission_energy_multiplier = 0.0
		wing.material_override = wm
		pivot.add_child(wing)
		add_child(pivot)
		radiators.append(pivot)
	# Laser turret on top of the body.
	turret = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = length * 0.012
	cm.bottom_radius = length * 0.016
	cm.height = length * 0.04
	turret.mesh = cm
	turret.position = Vector3(0, length * 0.062, -length * 0.5 + length * 0.42)
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.9, 0.35, 0.9) if not mars else Color(1.0, 0.55, 0.3)
	turret.material_override = tm
	add_child(turret)
	if has_gun:
		var gun := MeshInstance3D.new()
		var gm := CylinderMesh.new()
		gm.top_radius = length * 0.006
		gm.bottom_radius = length * 0.008
		gm.height = length * 0.75
		gun.mesh = gm
		gun.rotation.x = PI / 2
		gun.position = Vector3(0, -length * 0.062, -length * 0.5 + length * 0.36)
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color = Color(0.95, 0.75, 0.35)
		gmat.metallic = 0.6
		gun.material_override = gmat
		add_child(gun)
	# Drive plume behind the stern.
	plume = MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = length * 0.03
	pm.bottom_radius = length * 0.09
	pm.height = length * 0.9
	pm.cap_top = false
	pm.cap_bottom = false
	plume.mesh = pm
	plume.rotation.x = -PI / 2
	plume.position = Vector3(0, 0, length * 0.5 + length * 0.45)
	var plm := StandardMaterial3D.new()
	plm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	plm.albedo_color = Color(0.35, 0.28, 0.9, 0.55) if not mars else Color(0.9, 0.45, 0.25, 0.55)
	plm.cull_mode = BaseMaterial3D.CULL_DISABLED
	plume.material_override = plm
	plume.visible = false
	add_child(plume)

func _lathe(a: float, b: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 48
	var pts: Array = []
	for p in PROFILE:
		if p[0] >= a - 1e-6 and p[0] <= b + 1e-6:
			pts.append(p)
	if pts.is_empty() or pts[0][0] > a + 1e-6:
		pts.push_front([a, _r_at(a)])
	if pts[-1][0] < b - 1e-6:
		pts.append([b, _r_at(b)])
	for i in range(pts.size() - 1):
		var z0: float = -length * 0.5 + pts[i][0] * length
		var z1: float = -length * 0.5 + pts[i + 1][0] * length
		var r0: float = pts[i][1] * length
		var r1: float = pts[i + 1][1] * length
		for k in seg:
			var t0 := TAU * k / seg
			var t1 := TAU * (k + 1) / seg
			var v := [Vector3(cos(t0) * r0, sin(t0) * r0, z0), Vector3(cos(t0) * r1, sin(t0) * r1, z1),
					  Vector3(cos(t1) * r1, sin(t1) * r1, z1), Vector3(cos(t1) * r0, sin(t1) * r0, z0)]
			for idx in [0, 1, 2, 0, 2, 3]:
				var p: Vector3 = v[idx]
				st.set_normal(Vector3(p.x, p.y, 0).normalized())
				st.add_vertex(p)
	return st.commit()

func _r_at(x: float) -> float:
	for i in range(PROFILE.size() - 1):
		var p0 = PROFILE[i]
		var p1 = PROFILE[i + 1]
		if x >= p0[0] and x <= p1[0]:
			return lerp(float(p0[1]), float(p1[1]), (x - p0[0]) / max(1e-6, p1[0] - p0[0]))
	return PROFILE[-1][1]

## Colour and animate from the sim's view of the ship.
func show_state(s: Dictionary, delta: float) -> void:
	var armor: PackedFloat64Array = s["armor"]
	var armor_max: PackedFloat64Array = s["armor_max"]
	var st: PackedFloat64Array = s["structure"]
	var st_max: PackedFloat64Array = s["structure_max"]
	for k in 3:
		var m := section_mats[k]
		if view_mode == 1:
			var af: float = armor[k] / max(1.0, armor_max[k])
			var sf: float = st[k] / max(1.0, st_max[k])
			var c: Color
			if af > 0.0:
				c = Color(0.25, 0.75, 0.55).lerp(Color(0.95, 0.65, 0.2), 1.0 - af)
			else:
				c = Color(0.95, 0.45, 0.15).lerp(Color(0.85, 0.1, 0.08), 1.0 - sf)
			m.albedo_color = c
			m.emission_enabled = true
			m.emission = c * 0.35
		else:
			m.albedo_color = Color(0.78, 0.66, 0.56) if mars else Color(0.86, 0.86, 0.84)
			m.emission_enabled = false
	var target := 1.0 if s["radiators_extended"] else 0.0
	_rad_open = move_toward(_rad_open, target, delta * 0.8)
	var health: PackedFloat64Array = s["health"]
	for i in radiators.size():
		var wing := radiators[i].get_child(0) as MeshInstance3D
		wing.scale = Vector3(max(0.08, _rad_open), 1, 1)
		wing.position.x = (length * 0.055 + length * 0.10 * _rad_open)
		var wm := wing.material_override as StandardMaterial3D
		wm.emission_energy_multiplier = clamp((float(s["heat"]) - 30.0) / 70.0, 0.0, 1.0) * 1.5
		wm.albedo_color = Color(0.13, 0.13, 0.15) if health[4] > 0 else Color(0.3, 0.06, 0.04)
	plume.visible = s["burning"]
