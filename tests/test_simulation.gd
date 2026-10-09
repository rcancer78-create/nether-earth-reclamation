extends SceneTree
const Sim = preload("res://src/simulation.gd")
const Rules = preload("res://src/rules.gd")
var checks = 0
var failures = 0

func check(condition: bool, message: String):
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: "+message)

func fixture(ai: String = "tactician"):
	var s = Sim.new()
	s.setup({"id":"test","width":64,"height":24,"seed":1987,"resources":50,"ai":ai,"capture_ticks":144,"day_ticks":288,"elements":[],"buildings":[{"kind":0,"x":8,"y":12,"owner":0},{"kind":0,"x":54,"y":12,"owner":1},{"kind":4,"x":22,"y":8,"owner":-1}],"starting_robots":[]})
	return s

func _initialize():
	check(Rules.valid_parts(9),"Bipod + cannon accepted")
	check(not Rules.valid_parts(11),"Two chassis rejected")
	check(not Rules.valid_parts(1),"Unarmed robot rejected")
	check(not Rules.valid_parts(121),"Four weapons rejected")
	check(Rules.height(9)==17 and Rules.height(10)==13,"Original module heights")
	check(Rules.damage(10,0,5)==44,"Phaser versus tracks+cannon is 44")
	check(Rules.damage(10,6,5)==40,"High ground damage reduction")
	check(Rules.weapon_range(4,true)==8,"Electronics improves missile range")
	check(Rules.payment([3,0,0,0,0,2,0],9)==[0,0,0,0,0,0,0],"Specialized stock precedes general stock")
	check(Rules.payment([4,0,0,0,0,0,0],9).is_empty(),"Insufficient funds rejected atomically")
	var s = fixture()
	var before = s.resources[0].duplicate()
	check(s.construct(s.buildings[0].id,9)=="","Construction succeeds")
	check(s.resources[0][0]==45 and s.count_robots(0)==1,"Payment and spawn committed")
	check(not s.construct(s.buildings[0].id,9).is_empty(),"Occupied base cannot spawn")
	check(s.resources[0][0]==45,"Failed construction spends nothing")
	s = fixture()
	var r = s.spawn(0,s.buildings[2].pos,9)
	for i in 143: s.update_captures()
	check(s.buildings[2].owner == -1,"Capture not early")
	s.update_captures()
	check(s.buildings[2].owner == 0,"144-tick capture")
	s.income()
	check(s.resources[0][0]==55 and s.resources[0][4]==2,"Correct daily income")
	s.resources[0][0] = 98
	s.income()
	check(s.resources[0][0]==99,"Resource cap")
	s = fixture()
	r = s.spawn(0,s.buildings[2].pos,9)
	for i in 72: s.update_captures()
	r.pos += Vector2i(1,0)
	s.update_captures()
	check(s.buildings[2].capture==0,"Leaving entrance cancels capture")
	s = fixture()
	r = s.spawn(0,Vector2i(20,12),10)
	var enemy = s.spawn(1,Vector2i(23,12),10)
	r.dir = 0
	for i in 3:
		r.cooldown = 0
		s.fire(r,3)
	check(s.projectiles.size()==2,"Two automatic bullet slots per side")
	for i in 3: s.update_projectiles()
	check(enemy.hp==56,"Two cannon impacts deal original damage")
	s = fixture()
	r = s.spawn(0,Vector2i(19,8),65)
	var friend = s.spawn(0,Vector2i(20,8),9)
	enemy = s.spawn(1,Vector2i(20,9),9)
	s.detonate(r.id)
	check(not r.alive and not friend.alive and not enemy.alive,"Nuclear blast affects both teams and carrier")
	check(not s.buildings[2].alive,"Nuclear blast destroys factories")
	s = fixture()
	for i in 25: s.spawn(0,Vector2i(4+i,20),9)
	check(s.count_robots(0)==24,"24 robot hard cap")
	s = fixture()
	s.resources[1][0] = 0
	s.map.day_ticks = 100000
	r = s.spawn(0,Vector2i(12,16),138)
	s.give_order(r.id,6)
	for i in 1200:
		s.step()
		if s.buildings[2].owner == 0: break
	check(s.buildings[2].owner==0,"Modern robot reaches and captures assigned factory")
	var snapshot = JSON.parse_string(JSON.stringify(s.snapshot()))
	var restored = Sim.new()
	check(restored.restore(snapshot),"JSON save restores")
	check(restored.snapshot()==s.snapshot(),"Snapshot exact round trip")
	for i in 400:
		s.step()
		restored.step()
	check(restored.snapshot()==s.snapshot(),"Save continuation determinism")
	check(not restored.restore({"version":999}),"Unknown save versions rejected")
	var malformed = snapshot.duplicate(true)
	malformed.robots[0].parts = 255
	check(not restored.restore(malformed),"Invalid saved module masks rejected")
	malformed = snapshot.duplicate(true)
	malformed.robots[0].goal = "invalid"
	check(not restored.restore(malformed),"Malformed saved coordinates rejected")
	malformed = snapshot.duplicate(true)
	malformed.terrain[0] = 900
	check(not restored.restore(malformed),"Unknown terrain rejected")
	malformed = snapshot.duplicate(true)
	malformed.resources[0][0] = -1
	check(not restored.restore(malformed),"Negative stock rejected")
	s = fixture()
	s.map.story = [{"id":"intro","tick":1,"text":"Contact"}]
	s.step()
	check(s.story_fired == ["intro"],"Story trigger fires")
	s.events.clear()
	s.step()
	check(s.events.filter(func(e): return e.type == "radio").is_empty(),"Story trigger fires only once")
	s = fixture()
	var guard = s.spawn(1,Vector2i(53,16),138)
	var invader = s.spawn(0,Vector2i(48,16),10)
	for i in 15: s.step()
	check(guard.order==3 and guard.target==invader.id,"Tactical AI defends a threatened base")
	for id in ["original","breach","relay","core"]:
		var map = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/"+id+".json"))
		check(Sim.valid_map(map),id+" map valid")
		s = Sim.new()
		s.setup(map)
		check(s.count_bases(0)==1 and s.count_bases(1)>=1,id+" has both sides")
		for i in 2000: s.step()
		check(s.count_robots(1)>0,id+" AI constructs robots")
		var ordered = false
		for unit in s.robots:
			if unit.owner==1 and unit.order!=0: ordered = true
		check(ordered,id+" AI issues orders")
		check(s.count_robots(0)<=24 and s.count_robots(1)<=24,id+" army limits under simulation")
		restored = Sim.new()
		check(restored.restore(JSON.parse_string(JSON.stringify(s.snapshot()))),id+" save restores")
	s = fixture()
	s.buildings[1].owner = 0
	s.step()
	check(s.result==0,"Victory when enemy has no bases")
	s = fixture()
	s.buildings[0].alive = false
	s.step()
	check(s.result==1,"Defeat when player has no bases")
	print("TESTS: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
