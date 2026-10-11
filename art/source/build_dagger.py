"""Run with Blender 4.3+: blender -b --python build_dagger.py"""
import bpy, math, os
from mathutils import Vector, Matrix

OUT = os.path.dirname(os.path.abspath(__file__))
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for c in list(bpy.data.collections):
    if c.name != 'Collection': bpy.data.collections.remove(c)
base=bpy.data.collections.get('Collection'); base.name='DAGGER | scene'

def collection(name):
    c=bpy.data.collections.new(name); bpy.context.scene.collection.children.link(c); return c
hull=collection('01 | cylindrical hull and tanks')
crew=collection('02 | forward crew and shield')
optics=collection('03 | beam directors and sensors')
drive=collection('04 | fusion machinery and magnetic nozzle')
hot=collection('05 | four drive radiator wings')
service=collection('06 | service and crew radiators')
detail=collection('07 | missile bays and surface hardware')
stage=collection('08 | cameras and lighting')

def mat(name,color,metal=0,rough=.45):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    return m
ivory=mat('Pale aerospace protective panels',(.72,.76,.77),.38)
light=mat('Panel variation',(.88,.87,.79),.3)
black=mat('Graphite carbon-carbon radiator fins',(.023,.031,.038),.25,.6)
steel=mat('Titanium hardware — appearance only',(.21,.25,.28),.8,.3)
dark=mat('Shadow-shield casing',(.07,.085,.09),.65)
gold=mat('Muted caution ochre',(.65,.39,.07),.5)
glass=mat('Dark optical aperture',(.012,.034,.06),.85,.12)
copper=mat('Copper-colored machinery',(.39,.17,.08),.8)

def move(o,c,m):
    for old in list(o.users_collection):old.objects.unlink(o)
    c.objects.link(o)
    if m:o.data.materials.append(m)
    return o
def smooth(o):
    for p in o.data.polygons:p.use_smooth=True
def bevel(o,width=.08):
    mod=o.modifiers.new('Machined edge bevel','BEVEL');mod.width=width;mod.segments=2
    mod=o.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
def box(name,loc,size,m,c,edge=0):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name
    o.scale=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    move(o,c,m)
    if edge:bevel(o,edge)
    return o
def cylinder(name,loc,radius,length,m,c,axis=(1,0,0),r2=None,vertices=64):
    if r2 is None:bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=length,location=loc)
    else:bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=radius,radius2=r2,depth=length,location=loc)
    o=bpy.context.object;o.name=name;o.rotation_euler=Vector(axis).to_track_quat('Z','Y').to_euler()
    move(o,c,m);smooth(o);return o
def sphere(name,loc,radius,m,c,scale=(1,1,1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32,ring_count=16,radius=radius,location=loc)
    o=bpy.context.object;o.name=name;o.scale=scale;move(o,c,m);smooth(o);return o
def torus(name,loc,major,minor,m,c,axis=(1,0,0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major,minor_radius=minor,major_segments=64,minor_segments=10,location=loc)
    o=bpy.context.object;o.name=name;o.rotation_euler=Vector(axis).to_track_quat('Z','Y').to_euler();move(o,c,m);smooth(o);return o
def beam(name,a,b,r,m,c):
    a,b=Vector(a),Vector(b);return cylinder(name,(a+b)/2,r,(b-a).length,m,c,axis=b-a,vertices=12)
def empty(name,loc,c):
    o=bpy.data.objects.new(name,None);c.objects.link(o);o.location=loc;return o
def parent(o,p):
    bpy.context.view_layer.update()
    matrix=o.matrix_world.copy();o.parent=p;o.matrix_world=matrix

# X is the thrust axis; bow -90 m, nozzle exit +90 m. Dimensions in meters.
ship=empty('DAGGER | 2300 Earth destroyer', (0,0,0),hull)
ship['length_m']=187.7;ship['max_hull_diameter_m']=18.
ship['loaded_mass_t']=2500.;ship['dry_mass_t']=1000.
ship['jet_power_GW']=10.;ship['shared_laser_MW']=10.
ship['status']='Concept blockout; geometry and material appearances are not validated equipment engineering.'
sections=[('Crew protective shell',-73,20,7.0,crew),('Shield connection',-59,8,7.8,crew),('Forward tank',-41,28,9,hull),('Central tank',-11,28,9,hull),('Aft tank',19,28,9,hull),('Systems transition',40,12,8.6,hull),('Drive casing',53,12,8,drive)]
for name,x,length,r,c in sections:
    cylinder(name,(x,0,0),r,length,ivory,c)
    for end in [-1,1]:
        cylinder(name+' end collar',(x+end*(length/2-.18),0,0),r+.12,.38,steel,c)
    for dx in range(-int(length/2)+3,int(length/2),4):
        torus(name+' panel seam',(x+dx,0,0),r+.018,.025,dark,c)
    # Circumferential seams indicate replaceable axial panels.
    for theta in range(0,360,30):
        t=math.radians(theta)
        beam(name+' axial seam',(x-length/2+.6,(r+.025)*math.cos(t),(r+.025)*math.sin(t)),(x+length/2-.6,(r+.025)*math.cos(t),(r+.025)*math.sin(t)),.025,dark,c)
cylinder('Tapered nose turret foundation',(-84,0,0),7,6,ivory,crew,axis=(-1,0,0),r2=5.4)
cylinder('Shadow shield protective collar',(-58,0,0),8.1,3,dark,crew)
for x in [-61,-54,-27,3,33,46]:
    cylinder('Identification / caution band',(x,0,0),8.12 if x< -50 else (9.04 if x<40 else 8.65),.22,gold,hull)

# Enlarged nose director: a single 12 m housing with a provisional 5 m aperture.
root=empty('Nose beam director | gimbal assembly',(-87,0,0),optics)
root['clear_aperture_m']=5.;root['housing_diameter_m']=12.;root['source_MW']=10.
root['status']='Larger optical assembly; mass, pointing and optical performance require rebudgeting.'
mount=cylinder('Nose director azimuth bearing',(-87,0,0),5.6,1.6,steel,optics);parent(mount,root)
ring=torus('Nose bearing protective collar',(-87.8,0,0),5.45,.32,ivory,optics);parent(ring,root)
# Open-front spherical shell, rather than hiding the aperture under a solid sphere.
verts=[];faces=[];steps=28;segments=64;radius=6.;cx=-92.
for row in range(steps+1):
    polar=.55+(math.pi-.55)*row/steps
    for j in range(segments):
        phi=2*math.pi*j/segments
        verts.append((cx-radius*math.cos(polar),radius*math.sin(polar)*math.cos(phi),radius*math.sin(polar)*math.sin(phi)))
for row in range(steps):
    for j in range(segments):
        n=(j+1)%segments
        faces.append((row*segments+j,row*segments+n,(row+1)*segments+n,(row+1)*segments+j))
mesh=bpy.data.meshes.new('Open spherical nose director shell');mesh.from_pydata(verts,[],faces);mesh.update()
ball=bpy.data.objects.new('12 m rounded nose turret housing',mesh);optics.objects.link(ball);ball.data.materials.append(ivory)
smooth(ball);parent(ball,root)
for sign in [-1,1]:
    arm=beam('Nose director gimbal cradle',(-86.8,sign*4.8,0),(-92,sign*6.25,0),.55,steel,optics);parent(arm,root)
    tr=cylinder('Nose director elevation trunnion',(-92,sign*6.1,0),1.3,1.,ivory,optics,axis=(0,1,0));parent(tr,root)
    cap=cylinder('Trunnion bearing cover',(-92,sign*6.65,0),.88,.12,steel,optics,axis=(0,1,0));parent(cap,root)
rim=torus('Large aperture armored rim',(-97.12,0,0),3.10,.30,steel,optics);parent(rim,root)
inner=torus('Optical aperture inner bezel',(-97.17,0,0),2.60,.12,dark,optics);parent(inner,root)
eye=cylinder('5 m nose optical aperture',(-97.08,0,0),2.5,.08,glass,optics);parent(eye,root)
# Segmented protective bezel leaves the optical opening unobstructed.
for j in range(12):
    phi=2*math.pi*j/12
    o=box('Aperture rim segment',(-97.20,3.18*math.cos(phi),3.18*math.sin(phi)),(.24,.45,.35),light,optics,.04)
    o.rotation_euler.x=phi;parent(o,root)
for t in [0,2.094,4.189]:
    axis=(-.5,.866*math.cos(t),.866*math.sin(t));loc=(-80,6.8*math.cos(t),6.8*math.sin(t))
    cylinder('Shoulder sensor / tightbeam head',loc,.48,.6,dark,optics,axis=axis)
    sphere('Sensor optical face',loc,.38,glass,optics)
camera_note='Nose turret replaces both former small side beam directors.'

# Missile door dimensions indicate bays only; magazine capacity is unassigned.
for x in [-13,-5,3,11]:
    for sign in [-1,1]:
        box('Recessed missile bay frame',(x,sign*8.97,0),(5,.15,2),dark,detail,.08)
        box('Missile bay protective door',(x,sign*9.09,0),(4.65,.12,1.65),steel,detail,.06)
        box('Door identifier stripe',(x,sign*9.16,-.52),(3,.03,.07),gold,detail)
for x in [-46,-35,26,37]:
    for sign in [-1,1]:
        box('Service access panel',(x,sign*8.5,3),(2.6,.4,1.8),light,detail,.12)

# Four transverse drive-radiator planforms; long axis perpendicular to hull X.
L=100.;W=9433.547550322935/(4*L)
for index,theta in enumerate([0,math.pi/2,math.pi,3*math.pi/2]):
    center_x=25.; rootradius=9.5
    pivot=empty('Drive wing %d | root assembly'%(index+1),(center_x,rootradius*math.cos(theta),rootradius*math.sin(theta)),hot)
    pivot['planform_m2']=L*W;pivot['rated_temperature_K']=1300.;pivot['folding']='No validated stow mechanism or deployment animation.'
    pivot['radial_length_m']=L;pivot['axial_width_m']=W
    def wingpart(name,dx,radial,tangent,size,m,edge=0):
        distance=rootradius+L/2+dx
        o=box(name,(center_x+W/2-radial,distance*math.cos(theta)-tangent*math.sin(theta),distance*math.sin(theta)+tangent*math.cos(theta)),size,m,hot,edge)
        o.rotation_euler=(Matrix.Rotation(theta,4,'X') @ Matrix.Rotation(math.pi/2,4,'Z')).to_euler()
        parent(o,pivot);return o
    # Eight replaceable cassettes run radially outward from the root.
    for seg in range(8):
        dx=-L/2+(seg+.5)*L/8
        wingpart('Wing %d graphite fin cassette %02d'%(index+1,seg+1),dx,W/2,0,(L/8-.10,W-.08,.14),black)
        wingpart('Cassette cross frame',dx-L/16+.06,W/2,0,(.12,W,.24),steel)
    for radial in [0,W]:
        wingpart('Radiator perimeter beam',0,radial,0,(L,.25,.3),steel)
    for j in range(1,17):
        wingpart('Heat-pipe rib',0,j*W/17,.12,(L-.2,.08,.10),steel)
    for axial in [1,W/4,W/2,3*W/4,W-1]:
        wingpart('Isolated radiator root bracket',-L/2+.2,axial,0,(1.8,1.3,.8),steel,.08)
        wingpart('Dual manifold casing',-L/2-.5,axial,0,(.65,2.0,.7),light,.08)

# Independent transverse cold and service panels, clear of the main wings.
for label,width,temp,m,c,angles in [('Cold crew',1330.5/80,300,ivory,service,[0,math.pi]),('Hot service',776/80,1000,black,service,[math.pi/2,3*math.pi/2])]:
    for i,t in enumerate(angles):
        r=9.5
        rotation=(Matrix.Rotation(t,4,'X') @ Matrix.Rotation(math.pi/2,4,'Z')).to_euler()
        o=box(label+' radiator '+str(i+1),(-42,(r+20)*math.cos(t),(r+20)*math.sin(t)),(40,width,.16),m,c)
        o.rotation_euler=rotation;o['planform_m2']=40*width;o['rated_temperature_K']=temp
        o['radial_length_m']=40.;o['axial_width_m']=width
        for distance in [0,10,20,30,40]:
            b=box(label+' panel frame',(-42,(r+distance)*math.cos(t),(r+distance)*math.sin(t)),(.12,width,.25),steel,c)
            b.rotation_euler=rotation
        for offset in [-width/2,width/2]:
            b=box(label+' longitudinal frame',(-42+offset,(r+20)*math.cos(t),(r+20)*math.sin(t)),(40,.18,.25),steel,c)
            b.rotation_euler=rotation
        for offset in [-width/3,width/3]:
            b=box(label+' root connection',(-42+offset,r*math.cos(t),r*math.sin(t)),(1.2,1.4,.8),steel,c,.08)
            b.rotation_euler=rotation

# Aft open machinery; rendered rings indicate magnet housings, not a reactor blueprint.
cylinder('Fusion assembly inner housing',(69,0,0),5.6,20,dark,drive)
for x in [60,64,68,72,76,80]:
    torus('Magnet casing',(x,0,0),6.4,.55,steel,drive)
    torus('Magnet insulation band',(x+.45,0,0),6.4,.16,ivory,drive)
for t in [j*math.pi/4 for j in range(8)]:
    y,z=7.3*math.cos(t),7.3*math.sin(t)
    beam('Aft structural longeron',(58,y,z),(82,y*.77,z*.77),.16,steel,drive)
    beam('Driver service conduit',(59,y*.82,z*.82),(79,y*.82,z*.82),.15,copper,drive)
    cylinder('Driver service pod',(68,y*.82,z*.82),.55,9,ivory,drive)
for x in [80,83,86]:torus('Magnetic nozzle field coil',(x,0,0),4.8+(x-80)*.17,.40,steel,drive)
# Open annular nozzle exit with no filled opaque cap.
torus('Nozzle exit rim',(89.6,0,0),6.0,.4,dark,drive)
for t in [j*math.pi/8 for j in range(16)]:
    beam('Nozzle cage rib',(80,4.8*math.cos(t),4.8*math.sin(t)),(89.6,6*math.cos(t),6*math.sin(t)),.11,steel,drive)

# Parent assembly-level objects to the ship root without altering placements.
for c in [hull,crew,optics,drive,hot,service,detail]:
    for o in list(c.objects):
        if o!=ship and o.parent is None:parent(o,ship)

def camera(name,loc,target,scale):
    data=bpy.data.cameras.new(name);o=bpy.data.objects.new(name,data);stage.objects.link(o);o.location=loc
    o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
    data.type='ORTHO';data.ortho_scale=scale;data.clip_end=2000;return o
hero=camera('Hero three-quarter',(-170,-260,170),(0,0,0),330)
camera('True side — X axis horizontal',(0,-300,0),(0,0,0),300)
camera('Nose turret close-up',(-125,-42,24),(-89,0,0),42)
camera('Bow axial inspection',(-300,0,0),(0,0,0),300)
def area(name,loc,power,size,color):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color
    o=bpy.data.objects.new(name,data);stage.objects.link(o);o.location=loc;o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler()
area('Cool broad key',(-65,-100,130),65000,100,(.85,.92,1.))
area('Warm aft rim',(100,60,100),55000,85,(1.,.83,.62))
area('Soft bow fill',(-130,40,20),35000,80,(.85,.90,1.))
scene=bpy.context.scene;scene.camera=hero
scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1.
scene.render.engine='CYCLES';scene.cycles.samples=48
scene.cycles.use_denoising=False
scene.render.resolution_x=1800;scene.render.resolution_y=1400;scene.render.resolution_percentage=100
scene.world.color=(.10,.10,.10);scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.055,.07,.09,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value=.45
scene.view_settings.view_transform='AgX'
scene.view_settings.exposure=1.0
scene.render.image_settings.file_format='PNG';scene.render.filepath=os.path.join(OUT,'dagger_preview.png')
scene['design_basis']='Spacecraft_Combat_Unified_Framework.md; closed Dagger mass/power/thermal assumptions.'
scene['scope']='Editable visual blockout. No reactor internals, stress solution, optical train, validated deployment or assigned missile capacity.'
for a in bpy.context.screen.areas:
    if a.type=='VIEW_3D':
        a.spaces.active.region_3d.view_distance=230
        a.spaces.active.region_3d.view_location=(0,0,0)
        a.spaces.active.clip_end=2000
bpy.ops.object.select_all(action='DESELECT')
ship.select_set(True);bpy.context.view_layer.objects.active=ship
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'Dagger_Earth_Destroyer.blend'))
bpy.ops.render.render(write_still=True)
print('DAGGER_COMPLETE',len(bpy.data.objects),'objects; drive radiator planform',4*L*W)
