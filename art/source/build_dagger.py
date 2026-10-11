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
oms=collection('09 | OMS maneuvering thruster clusters')

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
ship['length_m']=180.;ship['max_hull_diameter_m']=18.
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
cylinder('Armored tapered bow',(-85,0,0),4.6,10,ivory,crew,axis=(1,0,0),r2=7)
sphere('Rounded armored bow cap',(-89,0,0),4.6,ivory,crew,scale=(.22,1,1))
cylinder('Shadow shield protective collar',(-58,0,0),8.1,3,dark,crew)
for x in [-61,-54,-27,3,33,46]:
    cylinder('Identification / caution band',(x,0,0),8.12 if x< -50 else (9.04 if x<40 else 8.65),.22,gold,hull)

# Two side-mounted 12 m director housings with 5 m clear apertures.
# Shared source remains 10 MW total, not 10 MW per turret.
for side in [-1,1]:
    axis=Vector((0,side,0)); u=Vector((1,0,0)); v=u.cross(axis)
    center=Vector((-65,side*13.0,0))
    root=empty(('Port' if side<0 else 'Starboard')+' beam director | gimbal assembly',center,optics)
    root['clear_aperture_m']=5.;root['housing_diameter_m']=12.
    root['shared_source_MW']=10.;root['status']='Concept side director; optics and mount loads require rebudgeting.'
    def part(o):parent(o,root);return o
    part(cylinder('Side director hull bearing',(-65,side*7.4,0),4.8,1.2,steel,optics,axis=axis))
    part(torus('Side director protective bearing ring',(-65,side*8.1,0),4.7,.25,ivory,optics,axis=axis))
    # Open spherical shell: aperture faces outward, shell normals point outward.
    verts=[];faces=[];steps=28;segments=64
    for row in range(steps+1):
        polar=.55+(math.pi-.55)*row/steps
        for j in range(segments):
            phi=2*math.pi*j/segments
            verts.append(center+6*(axis*math.cos(polar)+math.sin(polar)*(u*math.cos(phi)+v*math.sin(phi))))
    for row in range(steps):
        for j in range(segments):
            n=(j+1)%segments
            faces.append((row*segments+j,row*segments+n,(row+1)*segments+n,(row+1)*segments+j))
    mesh=bpy.data.meshes.new('Open side turret shell');mesh.from_pydata(verts,[],faces);mesh.update()
    ball=bpy.data.objects.new('12 m side laser housing',mesh);optics.objects.link(ball);ball.data.materials.append(ivory)
    if mesh.polygons[0].normal.dot(mesh.polygons[0].center-center)<0:
        for f in mesh.polygons:f.flip()
        mesh.update()
    smooth(ball);part(ball)
    for sign in [-1,1]:
        part(beam('Side director gimbal cradle',(-65,side*8,sign*4.8),center+Vector((0,0,sign*6.25)),.55,steel,optics))
        part(cylinder('Side director elevation trunnion',center+Vector((0,0,sign*6.1)),1.3,1,ivory,optics,axis=(0,0,1)))
        part(cylinder('Side trunnion cover',center+Vector((0,0,sign*6.65)),.88,.12,steel,optics,axis=(0,0,1)))
    part(torus('Side laser armored aperture rim',center+axis*5.12,3.10,.30,steel,optics,axis=axis))
    part(torus('Side optical inner bezel',center+axis*5.17,2.60,.12,dark,optics,axis=axis))
    part(cylinder('5 m side optical aperture',center+axis*5.08,2.5,.08,glass,optics,axis=axis))

# Amidships OMS: recessed steerable bells in hemispherical protective fairings.
# Two separated stations retain pitch/yaw moment arms; diagonal positions clear wings.
def thruster_bell(name,base,direction,root):
    d=Vector(direction).normalized();base=Vector(base)
    q=d.to_track_quat('Z','Y');verts=[];faces=[];segments=32
    # Outer and inner walls joined at mouth: open nozzle, recessed throat.
    profile=[(0,.22),(.2,.27),(.55,.40),(1.05,.64),(1.5,.88),(1.5,.80),(1.05,.56),(.55,.32),(.2,.19)]
    for z,r in profile:
        for j in range(segments):
            t=2*math.pi*j/segments
            verts.append(base+q@Vector((r*math.cos(t),r*math.sin(t),z)))
    for i in range(len(profile)-1):
        for j in range(segments):
            n=(j+1)%segments;faces.append((i*segments+j,i*segments+n,(i+1)*segments+n,(i+1)*segments+j))
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    o=bpy.data.objects.new(name,mesh);oms.objects.link(o);o.data.materials.append(steel);smooth(o);parent(o,root)
    o['exhaust_direction']=list(d);o['throat_position_m']=list(base)
    o['thrust_N']='Unassigned; visual concept only'
    parent(cylinder('OMS recessed dark throat',base+d*.12,.18,.04,dark,oms,axis=d,vertices=32),root)
    for z,r in [( .55,.4),(1.05,.64),(1.48,.86)]:
        parent(torus('OMS nozzle reinforcement ring',base+d*z,r,.045,copper,oms,axis=d),root)
for x in [-22.,8.]:
    for index in range(4):
        t=math.pi/4+index*math.pi/2
        radial=Vector((0,math.cos(t),math.sin(t))); tangent=Vector((0,-math.sin(t),math.cos(t)))
        axial=Vector((1,0,0));center=Vector((x,0,0))+radial*9.05
        root=empty(('Forward amidships' if x<0 else 'Aft amidships')+' OMS pod '+str(index+1),center,oms)
        root['nozzle_count']=1;root['fairing_radius_m']=2.5;root['gimbal_cone_deg']=10.
        root['radial_axis']=list(radial);root['axial_station_m']=x
        root['status']='Concept pod; 10 degree gimbal envelope is provisional; plume heating and thrust unassigned.'
        def podpart(o):parent(o,root);return o
        podpart(torus('OMS flush mounting flange',center,2.48,.10,steel,oms,axis=radial))
        # Half-ball fairing with an open circular recess at its outward pole.
        verts=[];faces=[];steps=20;segments=64
        for row in range(steps+1):
            polar=.5+(math.pi/2-.5)*row/steps
            for j in range(segments):
                phi=2*math.pi*j/segments
                verts.append(center+2.5*(radial*math.cos(polar)+math.sin(polar)*(axial*math.cos(phi)+tangent*math.sin(phi))))
        for row in range(steps):
            for j in range(segments):
                n=(j+1)%segments
                faces.append((row*segments+j,row*segments+n,(row+1)*segments+n,(row+1)*segments+j))
        mesh=bpy.data.meshes.new('OMS open hemispherical fairing');mesh.from_pydata(verts,[],faces);mesh.update()
        o=bpy.data.objects.new('OMS half-ball fairing',mesh);oms.objects.link(o);o.data.materials.append(ivory)
        if mesh.polygons[0].normal.dot(mesh.polygons[0].center-center)<0:
            for face in mesh.polygons:face.flip()
            mesh.update()
        smooth(o);podpart(o)
        podpart(torus('OMS recessed aperture lip',center+radial*(2.5*math.cos(.5)),2.5*math.sin(.5),.075,steel,oms,axis=radial))
        podpart(cylinder('OMS shadowed gimbal cavity',center+radial*.65,1.12,.06,dark,oms,axis=radial))
        pivot=center+radial*.8
        gimbal=empty('OMS steerable nozzle | local X-Y tilt',pivot,oms)
        gimbal.rotation_euler=radial.to_track_quat('Z','Y').to_euler();parent(gimbal,root)
        gimbal.empty_display_type='ARROWS';gimbal.empty_display_size=1.3
        gimbal['control']='Rotate local X/Y within a combined 10 degree cone. Local Z is nominal exhaust axis.'
        gimbal['gimbal_cone_deg']=10.
        thruster_bell('OMS gimballed recessed nozzle',pivot,radial,gimbal)
        for sign in [-1,1]:
            podpart(cylinder('OMS gimbal trunnion',pivot+axial*(sign*.54),.18,.20,steel,oms,axis=axial,vertices=32))
        # Small seam ring keeps the protective surface restrained.
        podpart(torus('OMS fairing service seam',center+radial*.45,math.sqrt(2.5**2-.45**2),.015,dark,oms,axis=radial))
ship['oms_pod_count']=8;ship['oms_nozzle_count']=8
ship['oms_stations_m']='-22, +8 along hull X; 30 m separation'

ship['laser_director_count']=2

for t in [0,2.094,4.189]:
    axis=(-.5,.866*math.cos(t),.866*math.sin(t));loc=(-80,6.8*math.cos(t),6.8*math.sin(t))
    cylinder('Shoulder sensor / tightbeam head',loc,.48,.6,dark,optics,axis=axis)
    sphere('Sensor optical face',loc,.38,glass,optics)
camera_note='Two side directors; armored bow; eight amidships hemispherical OMS pods.'

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
for c in [hull,crew,optics,drive,hot,service,detail,oms]:
    for o in list(c.objects):
        if o!=ship and o.parent is None:parent(o,ship)

def camera(name,loc,target,scale):
    data=bpy.data.cameras.new(name);o=bpy.data.objects.new(name,data);stage.objects.link(o);o.location=loc
    o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
    data.type='ORTHO';data.ortho_scale=scale;data.clip_end=2000;return o
hero=camera('Hero three-quarter',(-170,-260,170),(0,0,0),330)
camera('True side — X axis horizontal',(0,-300,0),(0,0,0),300)
camera('Side laser and forward OMS close-up',(-102,-75,35),(-68,-7,0),65)
camera('Amidships OMS close-up',(-38,-54,38),(-22,-7,6),27)
camera('Amidships OMS layout',(-35,-85,60),(-5,0,0),90)
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
print('DAGGER_V3_COMPLETE',len(bpy.data.objects),'objects; drive radiator planform',4*L*W)
