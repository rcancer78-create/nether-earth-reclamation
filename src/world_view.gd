extends Node3D
const Rules = preload("res://src/rules.gd")
const CELL = 3.0
const TEAM = [Color("66dfdd"),Color("fa795a"),Color("baa97a")]
var sim
var ground_root: Node3D
var actors_root: Node3D
var effects_root: Node3D
var actors: Dictionary = {}
var structures: Dictionary = {}
var camera: Camera3D
var drone: Node3D
var ring: MeshInstance3D
var focus = Vector3(40,0,40)
var zoom = 52.0
var yaw = 0.0
var clock = 0.0
var shake = 0.0
var materials: Dictionary = {}
var geometry: Dictionary = {}
var selected = -1
var particle_rng = RandomNumberGenerator.new()

func mat(color: Color, metallic: float = 0.0, glow: float = 0.0) -> StandardMaterial3D:
	var key = str(color)+str(metallic)+str(glow)
	if materials.has(key): return materials[key]
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = 0.38 if metallic > 0 else 0.82
	if glow > 0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	materials[key] = m
	return m

func mesh(parent: Node3D, shape: Mesh, position: Vector3, material: Material) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	node.mesh = shape
	node.position = position
	node.material_override = material
	parent.add_child(node)
	return node

func box(parent: Node3D, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var key = str(size)
	var shape: Mesh
	if geometry.has(key): shape = geometry[key]
	elif minf(size.x,minf(size.y,size.z)) > 0.28 and maxf(size.x,maxf(size.y,size.z)) < 30:
		shape = beveled_box(size)
		geometry[key] = shape
	else:
		shape = BoxMesh.new()
		shape.size = size
		geometry[key] = shape
	return mesh(parent,shape,pos,material)

func beveled_box(size: Vector3) -> ArrayMesh:
	var h = size*0.5
	var bevel = minf(0.14,minf(h.x,minf(h.y,h.z))*0.24)
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Six inset faces, twelve bevels, eight corner caps.
	for axis in 3:
		var u = (axis+1)%3
		var v = (axis+2)%3
		for sign_value in [-1,1]:
			var points = []
			for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
				var p = Vector3.ZERO
				p[axis] = h[axis]*sign_value
				p[u] = (h[u]-bevel)*corner.x
				p[v] = (h[v]-bevel)*corner.y
				points.append(p)
			add_polygon(st,points)
	for a in 3:
		var b = (a+1)%3
		var c = (a+2)%3
		for sa in [-1,1]:
			for sb in [-1,1]:
				var points = []
				for entry in [Vector2(-1,0),Vector2(1,0),Vector2(1,1),Vector2(-1,1)]:
					var p = Vector3.ZERO
					p[a] = (h[a]-(bevel if entry.y else 0))*sa
					p[b] = (h[b]-(0 if entry.y else bevel))*sb
					p[c] = (h[c]-bevel)*entry.x
					points.append(p)
				add_polygon(st,points)
	for sx in [-1,1]:
		for sy in [-1,1]:
			for sz in [-1,1]:
				var points = []
				for axis in 3:
					var p = Vector3((h.x-bevel)*sx,(h.y-bevel)*sy,(h.z-bevel)*sz)
					p[axis] = h[axis]*[sx,sy,sz][axis]
					points.append(p)
				add_polygon(st,points)
	return st.commit()

func add_polygon(st: SurfaceTool, points: Array):
	var normal: Vector3 = (points[1]-points[0]).cross(points[2]-points[0]).normalized()
	if normal.dot(points[0]) < 0: points.reverse(); normal = -normal
	for i in range(1,points.size()-1):
		# Godot front faces use clockwise winding.
		for p in [points[0],points[i+1],points[i]]:
			st.set_normal(normal)
			st.add_vertex(p)

func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, material: Material, top: float = -1.0) -> MeshInstance3D:
	var shape = CylinderMesh.new()
	shape.bottom_radius = radius
	shape.top_radius = radius if top < 0 else top
	shape.height = height
	shape.radial_segments = 16
	return mesh(parent,shape,pos,material)

func sphere(parent: Node3D, pos: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var shape = SphereMesh.new()
	shape.radius = radius
	shape.height = radius*2
	shape.radial_segments = 12
	shape.rings = 6
	return mesh(parent,shape,pos,material)

func point(pos: Vector2i) -> Vector3:
	return Vector3(pos.x*CELL,sim.altitude(pos)*0.16,pos.y*CELL)

func setup(model):
	sim = model
	for child in get_children():
		remove_child(child)
		child.queue_free()
	actors.clear()
	structures.clear()
	ground_root = Node3D.new()
	actors_root = Node3D.new()
	effects_root = Node3D.new()
	add_child(ground_root)
	add_child(actors_root)
	add_child(effects_root)
	var world = WorldEnvironment.new()
	var env = Environment.new()
	var sky = Sky.new()
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("1c3548")
	sky_mat.sky_horizon_color = Color("af9c80")
	sky_mat.ground_horizon_color = Color("af9c80")
	sky_mat.ground_bottom_color = Color("172127")
	sky_mat.sun_angle_max = 12
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8eabb7")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("687b7c")
	env.fog_density = 0.0024
	env.fog_sky_affect = 0.5
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		env.ssao_enabled = true
		env.ssao_radius = 2.0
		env.ssao_intensity = 2.0
		env.glow_enabled = true
		env.glow_intensity = 0.65
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.003
	world.environment = env
	add_child(world)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38,-32,0)
	sun.light_color = Color("ffe0b0")
	sun.light_energy = 1.75
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220
	add_child(sun)
	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25,145,0)
	fill.light_color = Color("6697ae")
	fill.light_energy = 0.38
	add_child(fill)
	camera = Camera3D.new()
	camera.fov = 47
	camera.far = 1700
	camera.current = true
	add_child(camera)
	var landmat = ShaderMaterial.new()
	landmat.shader = preload("res://src/terrain.gdshader")
	box(ground_root,Vector3(sim.width*CELL/2.0,-0.75,sim.depth*CELL/2.0),Vector3(sim.width*CELL+120,1.5,sim.depth*CELL+140),landmat)
	build_scenery()
	for b in sim.buildings: create_building(b)
	for r in sim.robots: create_robot(r)
	drone = create_drone()
	add_child(drone)
	var torus = TorusMesh.new()
	torus.inner_radius = 1.6
	torus.outer_radius = 1.72
	ring = mesh(self,torus,Vector3.ZERO,mat(TEAM[0],0.2,2.0))
	var b = sim.buildings[0]
	focus = point(b.pos)+Vector3(12,0,0)
	drone.position = point(b.pos)+Vector3(0,10,4)
	particle_rng.seed = int(sim.map.seed)

func build_scenery():
	var rng = RandomNumberGenerator.new()
	rng.seed = int(sim.map.seed)
	var rock_material = mat(Color("424a49"),0.0)
	var ruin_material = mat(Color("384044"),0.35)
	# Deterministic instanced rocks. Their traversability is taken from the simulation grid.
	var rock_mesh = SphereMesh.new()
	rock_mesh.radial_segments = 5
	rock_mesh.rings = 3
	rock_mesh.radius = 1
	rock_mesh.height = 2
	var transforms: Array[Transform3D] = []
	for x in sim.width:
		for y in sim.depth:
			var p = Vector2i(x,y)
			var kind = sim.terrain[y*sim.width+x]
			if kind < 2 or sim.blocked.has(p): continue
			if kind >= 15:
				if x % 2 == 0 and y % 2 == 0:
					var tall = 4.0 if kind in [17,18] else 1.5
					box(ground_root,Vector3(x*CELL,tall/2,y*CELL),Vector3(2.4,tall,2.4),ruin_material)
				continue
			var height = sim.altitude(p)*0.25+0.18
			var basis = Basis.from_euler(Vector3(0,rng.randf()*TAU,0)).scaled(Vector3(1.7,height,1.6))
			transforms.append(Transform3D(basis,Vector3(x*CELL,height*0.35,y*CELL)))
	var multi = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = rock_mesh
	multi.instance_count = transforms.size()
	for i in transforms.size(): multi.set_instance_transform(i,transforms[i])
	var rocks = MultiMeshInstance3D.new()
	rocks.multimesh = multi
	rocks.material_override = rock_material
	ground_root.add_child(rocks)
	# Distant mountain silhouettes and border infrastructure.
	for x in range(-30,sim.width*3+90,28):
		for z in [-35.0,sim.depth*3.0+40]:
			var mountain = cylinder(ground_root,Vector3(x,-2,z),rng.randf_range(15,26),rng.randf_range(20,46),mat(Color("293a42")),0)
			mountain.rotation_degrees.y = rng.randf()*360
	for x in range(0,sim.width*3,18):
		for z in [0.0,sim.depth*3.0]:
			box(ground_root,Vector3(x,0.6,z),Vector3(0.3,1.2,0.3),ruin_material)
			box(ground_root,Vector3(x,1.25,z),Vector3(0.35,0.1,0.35),mat(Color("e9b16f"),0,1.2))

func create_robot(r: Dictionary):
	var root = Node3D.new()
	root.position = point(r.pos)
	actors_root.add_child(root)
	var body = Node3D.new()
	root.add_child(body)
	var armor = mat(Color("6d858b") if r.owner == 0 else Color("66565a"),0.7)
	var dark = mat(Color("18272d"),0.75)
	var silver = mat(Color("bac3ba"),0.8)
	var glow = mat(TEAM[r.owner],0.4,2.5)
	var legs = []
	var chassis = Rules.chassis(r.parts)
	var h = 1.15
	if chassis == 0:
		for side in [-1,1]:
			var leg = Node3D.new()
			body.add_child(leg)
			leg.position.x = side*0.64
			cylinder(leg,Vector3(0,0.95,0),0.23,1.05,silver)
			box(leg,Vector3(0,0.25,0.1),Vector3(0.68,0.4,1.15),dark)
			box(leg,Vector3(0,0.8,-0.12),Vector3(0.45,0.7,0.5),armor)
			legs.append(leg)
		h = 1.8
	elif chassis == 1:
		for side in [-1,1]:
			box(body,Vector3(side*0.8,0.48,0),Vector3(0.65,0.85,2.1),dark)
			for z in [-0.7,0.0,0.7]:
				var wheel = cylinder(body,Vector3(side*1.14,0.47,z),0.3,0.07,silver)
				wheel.rotation_degrees.z = 90
			for z in range(-4,5): box(body,Vector3(side*0.8,0.92,z*0.22),Vector3(0.7,0.08,0.1),armor)
	else:
		cylinder(body,Vector3(0,0.55,0),1.18,0.38,dark,0.85)
		cylinder(body,Vector3(0,0.32,0),0.9,0.12,glow)
		for side in [-1,1]: box(body,Vector3(side*0.9,0.75,0),Vector3(0.6,0.5,1.6),armor)
	box(body,Vector3(0,h,0),Vector3(1.5,0.8,1.6),armor)
	box(body,Vector3(0,h+0.2,0.82),Vector3(1.0,0.15,0.05),glow)
	box(body,Vector3(0,h+0.49,-0.12),Vector3(1.1,0.2,1.1),dark)
	for side in [-1,1]:
		box(body,Vector3(side*0.77,h,-0.15),Vector3(0.12,0.38,0.9),silver)
		for z in [-0.42,-0.15,0.12]:
			box(body,Vector3(side*0.85,h+0.05,z),Vector3(0.05,0.2,0.1),dark)
	for x in [-0.42,0.42]:
		cylinder(body,Vector3(x,h+0.46,-0.55),0.12,0.45,dark)
	var stack = h+0.7
	for piece in range(3,7):
		if not r.parts & (1 << piece): continue
		if piece == 3:
			box(body,Vector3(0,stack,0.1),Vector3(1.1,0.48,1.1),armor)
			var barrel = cylinder(body,Vector3(0,stack,1.05),0.13,1.7,dark)
			barrel.rotation_degrees.x = 90
			box(body,Vector3(0,stack,1.94),Vector3(0.35,0.32,0.24),silver)
		elif piece == 4:
			for side in [-1,1]:
				box(body,Vector3(side*0.72,stack,0.25),Vector3(0.6,0.6,1.2),dark)
				for j in 3:
					var missile = cylinder(body,Vector3(side*0.72,stack-0.16+j*0.16,0.88),0.065,0.1,glow)
					missile.rotation_degrees.x = 90
		elif piece == 5:
			cylinder(body,Vector3(0,stack,0),0.6,0.38,armor)
			box(body,Vector3(0,stack,0.9),Vector3(0.22,0.2,1.7),glow)
			for z in [0.35,0.65,0.95]: box(body,Vector3(0,stack,z),Vector3(0.65,0.45,0.1),silver)
		else:
			sphere(body,Vector3(0,stack,0),0.52,mat(Color("c5ae65"),0.7))
			box(body,Vector3(0,stack,0.52),Vector3(0.4,0.1,0.05),mat(Color("ff633d"),0,3))
		stack += 0.52
	if r.parts & 128:
		cylinder(body,Vector3(0,stack+0.18,-0.35),0.05,0.8,silver)
		sphere(body,Vector3(0,stack+0.62,-0.35),0.13,glow)
	actors[r.id] = {"root":root,"body":body,"legs":legs,"chassis":chassis}

func create_building(b: Dictionary):
	var root = Node3D.new()
	root.position = point(b.pos)
	actors_root.add_child(root)
	var dark = mat(Color("25343b"),0.6)
	var wall = mat(Color("657273"),0.45)
	var edge = mat(Color("c2ba9d"),0.65)
	var lights = []
	var color = TEAM[b.owner if b.owner >= 0 else 2]
	var glow = mat(color,0.1,2.0)
	var base = b.kind == 0
	var w = 16.0 if base else 10.0
	box(root,Vector3(0,0.2,-4),Vector3(w+2,0.4,13 if base else 9),dark)
	box(root,Vector3(0,2.0,-7),Vector3(w,4,5),wall)
	box(root,Vector3(0,4.2,-7),Vector3(w+0.4,0.4,5.5),dark)
	for side in [-1,1]:
		box(root,Vector3(side*(w/2-1),2.8,-3),Vector3(2.1,5.6,6),wall)
		box(root,Vector3(side*(w/2-1),5.7,-3),Vector3(2.5,0.35,6.4),dark)
		lights.append(box(root,Vector3(side*(w/2-1),3.2,0.07),Vector3(0.22,3.0,0.15),glow))
		for z in [-4.0,-6.0,-8.0]: box(root,Vector3(side*(w/2+0.08),2,z),Vector3(0.2,0.5,0.9),dark)
	lights.append(box(root,Vector3(0,3,-4.44),Vector3(w-4,0.14,0.15),glow))
	for i in 7: box(root,Vector3(-3+i,0.44,0),Vector3(0.45,0.035,2),edge)
	# Exposed industrial services, segmented shutters and rooftop cooling grilles.
	for x in [-w*0.36,w*0.36]:
		for i in 5: box(root,Vector3(x-0.65+i*0.32,4.46,-7),Vector3(0.15,0.09,2.6),edge)
	for i in 7: box(root,Vector3(0,0.8+i*0.32,-4.46),Vector3(w-5,0.08,0.06),dark)
	for side in [-1,1]:
		var pipe = cylinder(root,Vector3(side*(w/2+0.48),1.25,-5),0.18,6,edge)
		pipe.rotation_degrees.x = 90
		for z in [-2.5,-5.0,-7.5]: box(root,Vector3(side*(w/2+0.48),1.25,z),Vector3(0.52,0.52,0.18),dark)
		box(root,Vector3(side*(w/2+1.5),0.7,-8),Vector3(1.4,1.4,2.2),wall)
		box(root,Vector3(side*(w/2+1.5),1.44,-8),Vector3(1.3,0.12,2),dark)
	if base:
		cylinder(root,Vector3(0,0.48,-1),2.6,0.1,dark)
		for x in [-0.65,0.65]: box(root,Vector3(x,0.55,-1),Vector3(0.2,0.025,1.8),glow)
		box(root,Vector3(0,0.55,-1),Vector3(1.4,0.025,0.2),glow)
		cylinder(root,Vector3(-5,7.5,-7),0.18,6,dark)
		var dish = cylinder(root,Vector3(-5,10.5,-7),1.4,0.5,edge,0.4)
		dish.rotation_degrees.z = 32
		lights.append(sphere(root,Vector3(-5,11.4,-7),0.23,glow))
	else:
		for x in [-2.2,0.0,2.2]:
			cylinder(root,Vector3(x,5.4,-7),0.64,2.8,dark)
			lights.append(cylinder(root,Vector3(x,6.2,-7),0.68,0.15,glow))
		var symbol = Label3D.new()
		symbol.text = ["","E","N","P","M","C","T"][b.kind]
		symbol.position = Vector3(0,3.1,-4.3)
		symbol.font_size = 72
		symbol.pixel_size = 0.027
		symbol.modulate = color
		root.add_child(symbol)
	structures[b.id] = {"root":root,"lights":lights,"owner":b.owner}

func create_drone() -> Node3D:
	var root = Node3D.new()
	var armor = mat(Color("c6cec4"),0.8)
	var dark = mat(Color("21353e"),0.6)
	box(root,Vector3.ZERO,Vector3(1.5,0.5,2.7),armor)
	box(root,Vector3(0,0.27,0.6),Vector3(0.95,0.32,1.25),mat(Color("4eb8c9"),0.8,0.4))
	for side in [-1,1]:
		box(root,Vector3(side*1.6,-0.05,-0.3),Vector3(2.0,0.16,1.1),dark)
		cylinder(root,Vector3(side*2.25,0,-0.3),0.55,0.28,armor)
		cylinder(root,Vector3(side*2.25,-0.2,-0.3),0.38,0.08,mat(TEAM[0],0,3))
	return root

func update_view(delta: float, craft: Vector2, selection: int):
	clock += delta
	selected = selection
	for id in actors.keys():
		if id > 0 and sim.by_id(id) == null:
			actors[id].root.queue_free()
			actors.erase(id)
	for r in sim.robots:
		if not actors.has(r.id) and r.alive: create_robot(r)
		if not actors.has(r.id): continue
		var a = actors[r.id]
		a.root.visible = r.alive
		if not r.alive: continue
		var destination = point(r.pos)
		var moving = a.root.position.distance_to(destination) > 0.12
		a.root.position = a.root.position.lerp(destination,minf(1.0,delta*7))
		a.body.rotation.y = lerp_angle(a.body.rotation.y,[PI/2,-PI/2,0,PI][r.dir],minf(1.0,delta*9))
		if a.chassis == 2: a.body.position.y = sin(clock*3+r.id)*0.15
		if a.chassis == 0:
			for i in a.legs.size(): a.legs[i].position.y = maxf(0,sin(clock*10+i*PI))*0.4 if moving else 0.0
	for b in sim.buildings:
		var structure = structures[b.id]
		structure.root.scale.y = 1.0 if b.alive else 0.15
		if b.owner != structure.owner:
			structure.owner = b.owner
			for light in structure.lights: light.material_override = mat(TEAM[b.owner],0.1,2)
	drone.position = drone.position.lerp(Vector3(craft.x*CELL,9.0+sin(clock*2)*0.28,craft.y*CELL),minf(1,delta*8))
	drone.rotation.z = sin(clock*1.7)*0.025
	var target = sim.by_id(selected)
	ring.visible = target != null
	if target != null:
		ring.position = point(target.pos)+Vector3(0,0.13,0)
		ring.scale = Vector3.ONE*(1.0 if target.has("parts") else 2.0)
	var offset = Vector3(0,zoom*0.65,zoom*0.85).rotated(Vector3.UP,yaw)
	camera.position = focus+offset+Vector3(sin(clock*61),sin(clock*47),0)*shake
	camera.look_at(focus)
	shake = move_toward(shake,0,delta*3)

func pick(screen: Vector2) -> Vector2i:
	var origin = camera.project_ray_origin(screen)
	var ray = camera.project_ray_normal(screen)
	var pos = Plane(Vector3.UP,0).intersects_ray(origin,ray)
	if pos == null: return Vector2i(-1,-1)
	return Vector2i(roundi(pos.x/CELL),roundi(pos.z/CELL))

func effect(event: Dictionary):
	if not event.has("pos"): return
	var pos = point(event.pos)+Vector3(0,1.5,0)
	var kind = event.type
	if kind == "shot":
		var direction = Vector3([1,-1,0,0][event.dir],0,[0,0,1,-1][event.dir])
		var beam = box(effects_root,pos+direction*3,Vector3(0.13,0.13,6),mat(TEAM[event.owner],0,4))
		if direction.x != 0: beam.rotation.y = PI/2
		var tween = create_tween()
		tween.tween_property(beam,"position",pos+direction*15,0.25)
		tween.tween_callback(beam.queue_free)
	elif kind in ["explosion","hit","nuclear"]:
		var nuclear = kind == "nuclear"
		var size = 20.0 if nuclear else (2.2 if kind == "explosion" else 0.7)
		var ball = sphere(effects_root,pos,0.6,mat(Color("ffd396"),0,4))
		var tween = create_tween()
		tween.tween_property(ball,"scale",Vector3.ONE*size,0.24)
		tween.tween_property(ball,"scale",Vector3.ONE*0.01,0.7)
		tween.tween_callback(ball.queue_free)
		for i in (24 if nuclear else 8):
			var debris = box(effects_root,pos,Vector3.ONE*0.22,mat(Color("fca564"),0.3,1))
			var endpoint = pos+Vector3(particle_rng.randf_range(-size,size),particle_rng.randf_range(1,size+2),particle_rng.randf_range(-size,size))
			var t = create_tween()
			t.tween_property(debris,"position",endpoint,0.6)
			t.parallel().tween_property(debris,"scale",Vector3.ONE*0.01,0.9)
			t.tween_callback(debris.queue_free)
		if pos.distance_to(focus) < 80: shake = 1.7 if nuclear else 0.2
