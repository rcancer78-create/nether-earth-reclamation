extends RefCounted
const Rules = preload("res://src/rules.gd")
const Commander = preload("res://src/ai/commander.gd")
const DIRS = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
const TERRAIN_HEIGHT = [0,0,2,2,2,2,3,3,6,6,6,6,0,0,0,7,15,7,15,0,0,99,0]
var map: Dictionary
var profile: Dictionary
var width: int
var depth: int
var terrain = PackedInt32Array()
var blocked: Dictionary = {}
var robots: Array = []
var buildings: Array = []
var projectiles: Array = []
var resources: Array = []
var events: Array = []
var tick = 0
var next_id = 1
var result = -1
var rng = RandomNumberGenerator.new()
var direct_id = -1
var direct_direction = -1
var direct_fire = false
var paths: Array = []
var bases_destroyed = 0
var story_fired: Array = []

func setup(definition: Dictionary, ai_override: String = ""):
	map = integer_data(definition)
	width = int(map.width)
	depth = int(map.height)
	var profiles = JSON.parse_string(FileAccess.get_file_as_string("res://data/ai_profiles.json"))
	var ai_name = ai_override if not ai_override.is_empty() else str(map.ai)
	map.ai = ai_name
	profile = profiles[ai_name]
	rng.seed = int(map.seed)
	tick = 0
	next_id = 1
	result = -1
	bases_destroyed = 0
	story_fired.clear()
	direct_id = -1
	robots.clear()
	buildings.clear()
	projectiles.clear()
	events.clear()
	blocked.clear()
	resources = [[int(map.resources),0,0,0,0,0,0], [int(map.resources),0,0,0,0,0,0]]
	terrain.resize(width * depth)
	terrain.fill(0)
	for item in map.get("elements", []):
		for dx in 2:
			for dy in 2:
				var pos = Vector2i(int(item[1])+dx,int(item[2])-dy)
				if inside(pos): terrain[pos.y*width+pos.x] = int(item[0])
	for data in map.buildings:
		var b = {"id":next_id,"pos":Vector2i(int(data.x),int(data.y)),"kind":int(data.kind),"owner":int(data.owner),"capture":0,"captor":-1,"alive":true}
		next_id += 1
		buildings.append(b)
		var radius = 3 if b.kind == 0 else 2
		for x in range(-radius,radius+1):
			for y in range(-4,-1):
				var p = b.pos + Vector2i(x,y)
				if inside(p): blocked[p] = b.id
		# Always leave an accessible approach to every entrance.
		for x in range(-2,3):
			for y in range(-1,3):
				var p = b.pos + Vector2i(x,y)
				if inside(p): terrain[p.y*width+p.x] = 0
	for data in map.get("starting_robots", []):
		spawn(int(data.owner), Vector2i(int(data.x),int(data.y)), int(data.parts))
	rebuild_paths()

func inside(p: Vector2i) -> bool:
	return p.x >= 1 and p.x < width-1 and p.y >= 1 and p.y < depth-1

func altitude(p: Vector2i) -> int:
	if not inside(p): return 99
	return TERRAIN_HEIGHT[clampi(terrain[p.y*width+p.x],0,22)]

func robot_at(p: Vector2i, except_id: int = -1):
	for r in robots:
		if r.alive and r.id != except_id and r.pos == p: return r
	return null

func by_id(id: int):
	for r in robots:
		if r.id == id and r.alive: return r
	for b in buildings:
		if b.id == id and b.alive: return b
	return null

func count_robots(owner: int) -> int:
	var count = 0
	for r in robots:
		if r.alive and r.owner == owner: count += 1
	return count

func count_bases(owner: int) -> int:
	var count = 0
	for b in buildings:
		if b.alive and b.kind == 0 and b.owner == owner: count += 1
	return count

func walkable(p: Vector2i, parts: int, except_id: int = -1, occupancy: bool = true) -> bool:
	if not inside(p) or blocked.has(p): return false
	var kind = terrain[p.y*width+p.x]
	if kind >= [8,12,15][Rules.chassis(parts)]: return false
	return not occupancy or robot_at(p,except_id) == null

func rebuild_paths():
	paths.clear()
	for c in 3:
		var grid = AStarGrid2D.new()
		grid.region = Rect2i(0,0,width,depth)
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
		grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		grid.update()
		for x in width:
			for y in depth:
				var p = Vector2i(x,y)
				grid.set_point_solid(p,not walkable(p,1 << c,-1,false))
				grid.set_point_weight_scale(p,1.0+altitude(p)*0.06)
		paths.append(grid)

func spawn(owner: int, pos: Vector2i, parts: int):
	if not Rules.valid_parts(parts) or count_robots(owner) >= Rules.MAX_ROBOTS: return null
	var used = []
	for unit in robots:
		if unit.alive and unit.owner == owner: used.append(unit.slot)
	var slot = 0
	while slot in used: slot += 1
	var r = {"id":next_id,"slot":slot,"pos":pos,"previous":pos,"parts":parts,"owner":owner,"hp":100,"alive":true,"order":0,"target":-1,"goal":pos,"dir":2,"wait":1,"steps":0,"move_dir":2,"cooldown":0,"distance":20}
	next_id += 1
	robots.append(r)
	events.append({"type":"spawn","pos":pos,"owner":owner})
	return r

func construct(base_id: int, parts: int) -> String:
	var b = by_id(base_id)
	if b == null or not b.has("kind") or b.kind != 0 or b.owner < 0: return "Нужна действующая военная база"
	if count_robots(b.owner) >= Rules.MAX_ROBOTS: return "Лимит: 24 робота на сторону"
	if not walkable(b.pos,parts): return "Освободите выход из базы"
	var remaining = Rules.payment(resources[b.owner],parts)
	if remaining.is_empty(): return "Недостаточно ресурсов или неверная конфигурация"
	resources[b.owner] = remaining
	var r = spawn(b.owner,b.pos,parts)
	r.order = 9
	r.goal = b.pos + Vector2i(0,3)
	return ""

func give_order(id: int, order: int, goal: Vector2i = Vector2i.ZERO):
	var r = by_id(id)
	if r == null or not r.has("parts"): return
	r.order = order
	r.target = -1
	r.steps = 0
	r.distance = 20
	r.goal = goal
	if order in [4,5] and not r.parts & 64:
		r.order = 0
		events.append({"type":"message","text":"Уничтожение зданий требует ядерного заряда"})

func step():
	if result != -1: return
	tick += 1
	if tick % int(map.get("day_ticks",288)) == 0: income()
	Commander.update(self)
	for r in robots:
		if not r.alive: continue
		r.cooldown = maxi(0,r.cooldown-1)
		r.wait -= 1
		if r.wait > 0: continue
		update_robot(r)
		var ground = altitude(r.pos)
		r.wait = Rules.SPEED[0 if ground == 0 else (1 if ground < 4 else 2)][Rules.chassis(r.parts)]
	update_projectiles()
	update_captures()
	update_story()
	robots = robots.filter(func(r): return r.alive)
	if count_bases(1) == 0: result = 0
	elif count_bases(0) == 0: result = 1

func update_story():
	for entry in map.get("story",[]):
		if entry.id in story_fired: continue
		if tick < int(entry.get("tick",0)): continue
		var factories = 0
		for b in buildings:
			if b.alive and b.owner == 0 and b.kind != 0: factories += 1
		if factories < int(entry.get("factories",0)): continue
		story_fired.append(entry.id)
		events.append({"type":"radio","text":str(entry.text)})

func income():
	for b in buildings:
		if not b.alive or b.owner < 0: continue
		resources[b.owner][b.kind] = mini(99,resources[b.owner][b.kind]+(5 if b.kind == 0 else 2))
	events.append({"type":"income","text":"Поступили суточные ресурсы"})

func choose_target(r: Dictionary):
	var best = null
	var score = INF
	if r.order == 3:
		for t in robots:
			if not t.alive or t.owner == r.owner: continue
			var distance = r.pos.distance_squared_to(t.pos)
			if distance < score: best = t; score = distance
	else:
		for b in buildings:
			if not b.alive or b.owner == r.owner: continue
			if r.order == 6 and (b.kind == 0 or b.owner != -1): continue
			if r.order in [4,7] and (b.kind == 0 or b.owner != 1-r.owner): continue
			if r.order in [5,8] and (b.kind != 0 or b.owner != 1-r.owner): continue
			var distance = abs(r.pos.x-b.pos.x) if map.ai == "classic" else r.pos.distance_squared_to(b.pos)
			if distance < score: best = b; score = distance
	if best != null: r.target = best.id
	return best

func update_robot(r: Dictionary):
	if r.id == direct_id:
		if direct_direction >= 0: move_robot(r,direct_direction)
		if direct_fire: fire(r,best_weapon(r))
		return
	var enemy = visible_enemy(r)
	if enemy != null:
		var delta: Vector2i = enemy.pos-r.pos
		var dir = direction(delta)
		if r.dir != dir:
			r.dir = dir
			return
		var weapon = best_weapon(r)
		if map.ai == "classic":
			var available_weapons = rng.randi() & 56 & r.parts
			weapon = -1
			for i in [5,4,3]:
				if available_weapons & (1 << i): weapon = i; break
		if weapon >= 0:
			fire(r,weapon)
			if r.pos.distance_to(enemy.pos) <= Rules.weapon_range(weapon,bool(r.parts & 128)): return
	if r.order == 0: return
	var goal: Vector2i = r.pos
	if r.order in [1,2]:
		goal = r.pos + Vector2i(1 if r.order == 1 else -1,0)*r.distance
	elif r.order == 9:
		goal = r.goal
	else:
		var target = by_id(r.target)
		if target == null or target.owner == r.owner: target = choose_target(r)
		if target == null:
			if r.owner == 1: r.order = 3
			return
		goal = target.pos
		if r.order in [4,5] and r.pos.distance_to(goal) < 2.0:
			detonate(r.id)
			return
	if r.pos == goal:
		if r.order == 9: r.order = 0
		return
	var available = []
	for d in 4:
		if walkable(r.pos+DIRS[d],r.parts,r.id): available.append(d)
	if available.is_empty(): return
	var chosen = -1
	if map.ai == "classic" and r.order != 9:
		if r.steps > 0 and r.move_dir in available:
			chosen = r.move_dir
			r.steps -= 1
		else:
			var good = []
			for d in available:
				if (r.pos+DIRS[d]).distance_squared_to(goal) < r.pos.distance_squared_to(goal): good.append(d)
			var choices = good if not good.is_empty() else available
			chosen = choices[rng.randi_range(0,choices.size()-1)]
			r.steps = rng.randi_range(3,6)
			if abs(goal.x-r.pos.x) < 8: r.steps = maxi(0,abs(goal.x-r.pos.x)-1)
	else:
		var grid: AStarGrid2D = paths[Rules.chassis(r.parts)]
		if inside(goal) and not grid.is_point_solid(goal):
			var path = grid.get_id_path(r.pos,goal)
			if path.size() > 1:
				chosen = DIRS.find(path[1]-r.pos)
		if not chosen in available:
			available.sort_custom(func(a,b): return (r.pos+DIRS[a]).distance_squared_to(goal) < (r.pos+DIRS[b]).distance_squared_to(goal))
			chosen = available[0]
	if chosen >= 0:
		r.move_dir = chosen
		move_robot(r,chosen)

func direction(delta: Vector2i) -> int:
	if abs(delta.x) >= abs(delta.y): return 0 if delta.x > 0 else 1
	return 2 if delta.y > 0 else 3

func move_robot(r: Dictionary, dir: int):
	if r.dir != dir:
		r.dir = dir
		return
	var p = r.pos+DIRS[dir]
	if not walkable(p,r.parts,r.id): return
	r.previous = r.pos
	r.pos = p
	if r.order in [1,2]:
		var intended = 0 if r.order == 1 else 1
		if dir == intended: r.distance -= 1
		elif dir == 1-intended: r.distance = mini(99,r.distance+1)
		if r.distance <= 0: r.order = 0

func visible_enemy(r: Dictionary):
	var best = null
	var nearest = INF
	for t in robots:
		if not t.alive or t.owner == r.owner: continue
		var delta: Vector2i = t.pos-r.pos
		if delta.x != 0 and delta.y != 0: continue
		var distance = abs(delta.x)+abs(delta.y)
		if distance > (12 if r.parts & 128 else 10): continue
		var dir = direction(delta)
		var clear = true
		for i in range(1,distance):
			var p: Vector2i = r.pos+DIRS[dir]*i
			if blocked.has(p) or altitude(p) >= 10: clear = false; break
		if clear and distance < nearest: best = t; nearest = distance
	return best

func best_weapon(r: Dictionary) -> int:
	for i in [5,4,3]:
		if r.parts & (1 << i): return i
	return -1

func fire(r: Dictionary, weapon: int):
	if weapon < 3 or r.cooldown > 0: return
	var pool = 2 if r.id == direct_id else r.owner
	var count = 0
	for p in projectiles:
		if p.pool == pool: count += 1
	if count >= (1 if pool == 2 else 2): return
	projectiles.append({"pos":r.pos,"dir":r.dir,"owner":r.owner,"pool":pool,"source":r.id,"weapon":weapon,"remaining":Rules.weapon_range(weapon,bool(r.parts & 128))*2})
	r.cooldown = 4
	events.append({"type":"shot","pos":r.pos,"dir":r.dir,"weapon":weapon,"owner":r.owner})

func update_projectiles():
	for i in range(projectiles.size()-1,-1,-1):
		var p = projectiles[i]
		p.pos += DIRS[p.dir]
		p.remaining -= 1
		var t = robot_at(p.pos,p.source)
		var remove = p.remaining <= 0 or not inside(p.pos) or blocked.has(p.pos) or altitude(p.pos) >= 10
		if t != null:
			t.hp -= Rules.damage(t.parts,altitude(t.pos),p.weapon)
			events.append({"type":"hit","pos":t.pos,"owner":t.owner})
			if t.hp <= 0: kill(t)
			remove = true
		if remove: projectiles.remove_at(i)

func kill(r: Dictionary):
	r.alive = false
	if direct_id == r.id: direct_id = -1
	events.append({"type":"explosion","pos":r.pos,"owner":r.owner})

func detonate(id: int):
	var r = by_id(id)
	if r == null or not r.has("parts") or not r.parts & 64: return
	var origin: Vector2i = r.pos
	for target in robots:
		if target.alive and abs(target.pos.x-origin.x) < 7 and abs(target.pos.y-origin.y) < 7 and abs(target.pos.x-origin.x)+abs(target.pos.y-origin.y) < 10: kill(target)
	for b in buildings:
		var dy = abs(b.pos.y-origin.y-(4 if b.kind == 0 else 0))
		var dx = abs(b.pos.x-origin.x)
		if b.alive and dx < 7 and dy < 7 and dx+dy < 10:
			b.alive = false
			if b.kind == 0: bases_destroyed += 1
			for p in blocked.keys():
				if blocked[p] == b.id: blocked.erase(p)
	for x in range(origin.x-6,origin.x+7):
		for y in range(origin.y-6,origin.y+7):
			var p = Vector2i(x,y)
			if inside(p) and terrain[y*width+x] in [17,18]: terrain[y*width+x] = 6
	if r.alive: kill(r)
	rebuild_paths()
	events.append({"type":"nuclear","pos":origin,"owner":r.owner})

func update_captures():
	for b in buildings:
		if not b.alive: continue
		var r = robot_at(b.pos)
		if r == null or r.owner == b.owner:
			b.capture = 0
			b.captor = -1
			continue
		if b.captor != r.id: b.capture = 0; b.captor = r.id
		b.capture += 1
		if b.capture >= int(map.get("capture_ticks",144)):
			b.owner = r.owner
			b.capture = 0
			r.target = -1
			events.append({"type":"capture","pos":b.pos,"owner":b.owner,"kind":b.kind})

func snapshot() -> Dictionary:
	var state = {"version":1,"map":map,"tick":tick,"next_id":next_id,"rng":str(rng.state),"resources":resources.duplicate(true),"result":result,"bases_destroyed":bases_destroyed,"story_fired":story_fired.duplicate(),"robots":[],"buildings":[],"projectiles":[]}
	for key in ["robots","buildings","projectiles"]:
		for source in get(key):
			var item = source.duplicate(true)
			for field in item.keys():
				if item[field] is Vector2i: item[field] = [item[field].x,item[field].y]
			state[key].append(item)
	state.terrain = Array(terrain)
	return state

func restore(state: Dictionary) -> bool:
	if state.get("version",0) != 1 or not state.has_all(["map","robots","buildings","resources","tick","rng","terrain","projectiles","next_id","result","bases_destroyed"]): return false
	if not valid_map(state.map) or not state.resources is Array or state.resources.size() != 2: return false
	for stock in state.resources:
		if not stock is Array or stock.size() != 7: return false
		for n in stock:
			if not (n is int or n is float) or n < 0 or n > 99: return false
	if not state.terrain is Array or state.terrain.size() != int(state.map.width)*int(state.map.height): return false
	for cell in state.terrain:
		if not integer_between(cell,0,22): return false
	if not integer_between(state.tick,0,2147483647) or not integer_between(state.next_id,1,2147483647): return false
	if not state.rng is String or not state.rng.is_valid_int(): return false
	if not integer_between(state.result,-1,1) or not integer_between(state.bases_destroyed,0,4096): return false
	if not state.get("story_fired",[]) is Array: return false
	var ids = {}
	for key in ["robots","buildings","projectiles"]:
		if not state[key] is Array or state[key].size() > 4096: return false
		for item in state[key]:
			if not item is Dictionary or not item.has("pos") or not item.pos is Array or item.pos.size() != 2: return false
			if not valid_position(item.pos,int(state.map.width),int(state.map.height)): return false
			if key == "robots" and not item.has_all(["id","slot","parts","owner","hp","alive","order","target","goal","previous","dir","wait","steps","move_dir","cooldown","distance"]): return false
			if key == "buildings" and not item.has_all(["id","kind","owner","capture","captor","alive"]): return false
			if key == "projectiles" and not item.has_all(["dir","owner","pool","source","weapon","remaining"]): return false
			if key != "projectiles":
				if not integer_between(item.id,1,int(state.next_id)-1) or ids.has(int(item.id)) or not item.alive is bool: return false
				ids[int(item.id)] = true
			if not integer_between(item.owner,-1 if key == "buildings" else 0,1): return false
			if key == "robots":
				if not integer_between(item.parts,0,255) or not Rules.valid_parts(int(item.parts)): return false
				if not integer_between(item.slot,0,23) or not integer_between(item.order,0,9) or not integer_between(item.dir,0,3): return false
				if not valid_position(item.goal,int(state.map.width),int(state.map.height),true) or not valid_position(item.previous,int(state.map.width),int(state.map.height)): return false
				for field in ["hp","target","wait","steps","move_dir","cooldown","distance"]:
					if not integer_between(item[field],-1000,2147483647): return false
			if key == "buildings":
				if not integer_between(item.kind,0,6) or not integer_between(item.capture,0,100000) or not integer_between(item.captor,-1,2147483647): return false
			if key == "projectiles":
				if not integer_between(item.dir,0,3) or not integer_between(item.weapon,3,5) or not integer_between(item.pool,0,2): return false
				if not integer_between(item.source,1,2147483647) or not integer_between(item.remaining,0,32): return false
	if state.buildings.size() != state.map.buildings.size(): return false
	setup(state.map)
	for key in ["robots","buildings","projectiles"]:
		var restored = []
		for source in state[key]:
			var item = source.duplicate(true)
			for field in ["pos","previous","goal"]:
				if item.has(field): item[field] = Vector2i(int(item[field][0]),int(item[field][1]))
			for field in item.keys():
				if item[field] is float: item[field] = int(item[field])
			restored.append(item)
		set(key,restored)
	tick = int(state.tick)
	next_id = int(state.next_id)
	resources = integer_data(state.resources)
	result = int(state.result)
	bases_destroyed = int(state.bases_destroyed)
	story_fired = state.get("story_fired",[]).duplicate()
	rng.state = int(state.rng)
	terrain = PackedInt32Array(state.terrain)
	for b in buildings:
		if not b.alive:
			for p in blocked.keys():
				if blocked[p] == b.id: blocked.erase(p)
	events.clear()
	rebuild_paths()
	return true

static func integer_data(value):
	if value is float: return int(value)
	if value is Array:
		var result_array = []
		for item in value: result_array.append(integer_data(item))
		return result_array
	if value is Dictionary:
		var result_dict = {}
		for key in value: result_dict[key] = integer_data(value[key])
		return result_dict
	return value

static func valid_map(data) -> bool:
	if not data is Dictionary or not data.has_all(["id","width","height","seed","resources","ai","buildings"]): return false
	if not str(data.ai) in ["classic","tactician","siege"]: return false
	if not integer_between(data.width,24,1024) or not integer_between(data.height,12,128): return false
	if not integer_between(data.resources,0,99) or not integer_between(data.seed,0,2147483647): return false
	if not integer_between(data.get("day_ticks",288),1,100000) or not integer_between(data.get("capture_ticks",144),1,100000): return false
	if not data.buildings is Array or data.buildings.size() < 2: return false
	var sides = [false,false]
	for b in data.buildings:
		if not b is Dictionary or not b.has_all(["x","y","kind","owner"]): return false
		if not integer_between(b.kind,0,6) or not integer_between(b.owner,-1,1): return false
		if not integer_between(b.x,4,int(data.width)-5) or not integer_between(b.y,2,int(data.height)-3): return false
		if int(b.x) < 4 or int(b.x) >= int(data.width)-4 or int(b.y) < 2 or int(b.y) >= int(data.height)-2: return false
		if int(b.kind) == 0 and int(b.owner) >= 0: sides[int(b.owner)] = true
	for field in ["elements","starting_robots","story"]:
		if not data.get(field,[]) is Array or data.get(field,[]).size() > 100000: return false
	for element in data.get("elements",[]):
		if not element is Array or element.size() != 3: return false
		if not integer_between(element[0],0,22) or not integer_between(element[1],0,int(data.width)-1) or not integer_between(element[2],0,int(data.height)-1): return false
	for robot in data.get("starting_robots",[]):
		if not robot is Dictionary or not robot.has_all(["x","y","owner","parts"]): return false
		if not integer_between(robot.owner,0,1) or not integer_between(robot.parts,0,255) or not Rules.valid_parts(int(robot.parts)): return false
		if not integer_between(robot.x,1,int(data.width)-2) or not integer_between(robot.y,1,int(data.height)-2): return false
	for entry in data.get("story",[]):
		if not entry is Dictionary or not entry.has_all(["id","text"]) or not entry.id is String or not entry.text is String: return false
		if not integer_between(entry.get("tick",0),0,2147483647) or not integer_between(entry.get("factories",0),0,4096): return false
	return sides[0] and sides[1]

static func integer_between(value, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and value >= minimum and value <= maximum and value == int(value)

static func valid_position(value, w: int, h: int, allow_zero: bool = false) -> bool:
	if not value is Array or value.size() != 2: return false
	return integer_between(value[0],0 if allow_zero else 1,w-1) and integer_between(value[1],0 if allow_zero else 1,h-1)
