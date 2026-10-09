extends RefCounted
const Rules = preload("res://src/rules.gd")

static func update(s):
	if s.map.ai == "classic": classic_commander(s)
	elif s.tick % int(s.profile.decision_ticks) == 0: tactical_commander(s)

static func classic_commander(s):
	# Lb7f4: choose one of 32 slots. Eight are deliberate no-ops.
	var slot = s.rng.randi() & 31
	if slot >= 24: return
	for r in s.robots:
		if r.alive and r.owner == 1 and r.slot == slot:
			if r.order != 0 and s.rng.randi() & 31 != 0: return
			if r.parts & 64:
				var byte = s.rng.randi() & 255
				r.order = 4 + ((byte | (byte >> 7)) & 1)
			else:
				var byte = s.rng.randi() & 255
				r.order = 6 if byte & 1 else (7 if byte & 2 else 8)
			r.target = -1
			if s.choose_target(r) == null: r.order = 3
			return
	for b in s.buildings:
		if b.kind != 0: continue
		if s.rng.randi() & 1 == 0 or b.owner != 1 or not b.alive: continue
		var parts = s.rng.randi() & 255
		if not Rules.valid_parts(parts): return
		var weapons = 0
		for i in range(3,7):
			if parts & (1 << i): weapons += 1
		# Follow cp / ret c in the machine code, not its contradictory prose comment.
		if weapons < ((int(s.count_robots(1) / 8) + 1) & 3): return
		var paid = Rules.payment(s.resources[1],parts)
		if paid.is_empty(): return
		if s.resources[1][0] - paid[0] > maxi(11,s.resources[1][0]/2): return
		s.construct(b.id,parts)
		return

static func tactical_commander(s):
	var owned = []
	for r in s.robots:
		if r.alive and r.owner == 1: owned.append(r)
	for b in s.buildings:
		if not b.alive or b.kind != 0 or b.owner != 1: continue
		var candidates = [146,138,161,12,9]
		if s.map.ai == "siege": candidates = [228,194,162,146,9]
		for mask in candidates:
			var paid = Rules.payment(s.resources[1],mask)
			if paid.is_empty() or paid[0] < int(s.profile.reserve): continue
			if s.construct(b.id,mask).is_empty(): break
	for r in owned:
		var threat = null
		for enemy in s.robots:
			if not enemy.alive or enemy.owner != 0: continue
			for b in s.buildings:
				if b.alive and b.owner == 1 and b.kind == 0 and enemy.pos.distance_to(b.pos) < float(s.profile.defense_radius):
					if r.pos.distance_to(b.pos) < 32: threat = enemy
		if threat != null:
			r.order = 3
			r.target = threat.id
			continue
		if r.order >= 6 and r.order <= 8:
			var current = s.by_id(r.target)
			if current != null and current.owner != 1: continue
		r.order = 5 if r.parts & 64 else (8 if owned.size() >= int(s.profile.assault_size) and r.slot % 3 != 0 else 6)
		r.target = -1
		if s.choose_target(r) == null:
			r.order = 7
			if s.choose_target(r) == null: r.order = 8
