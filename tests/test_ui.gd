extends SceneTree
var failures = 0
var checks = 0
var game
var prior_files = {}
const Main = preload("res://src/main.gd")

func check(condition: bool, message: String):
	checks += 1
	if not condition:
		failures += 1
		push_error("UI FAILED: "+message)

func _initialize():
	call_deferred("run")

func capture(path: String):
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(path)

func find_button(node: Node, text: String):
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found = find_button(child,text)
		if found != null: return found
	return null

func run():
	for name in ["save.json","save.backup.json","campaign.json"]:
		prior_files[name] = FileAccess.get_file_as_bytes("user://"+name) if FileAccess.file_exists("user://"+name) else null
	game = Main.new()
	root.add_child(game)
	await process_frame
	check(game.modal != null and not game.running,"Main menu appears")
	await capture("res://build/menu.png")
	game.show_missions()
	check(game.maps.size() >= 4,"Mission list has original and campaign")
	game.show_briefing("original")
	check(game.modal != null,"Original briefing")
	game.start_map("original",true)
	check(game.sim.width == 512 and game.sim.buildings.size() == 28,"Original campaign loads")
	game.show_build()
	check(game.modal != null and game.build_cost != null,"Builder opens")
	check(game.build_mask()==138,"Builder default design valid")
	game.build_chassis.select(2)
	game.build_checks[1].button_pressed = true
	game.update_build_cost()
	check(game.build_mask()==156,"Builder combines selected modules")
	await capture("res://build/assembly.png")
	var build_button = find_button(game.modal,"СОБРАТЬ И ВЫПУСТИТЬ")
	build_button.pressed.emit()
	check(game.modal == null and game.sim.count_robots(0)==1 and game.sim.resources[0][0]==1,"Assembly button commits build and closes dialog")
	game.start_map("breach",true)
	game.paused = true
	var original_stock = game.sim.resources[0][0]
	var error = game.sim.construct(game.sim.buildings[0].id,138)
	check(error.is_empty() and game.sim.resources[0][0]==original_stock-10,"Build spends correct resources")
	game.selected = game.sim.robots.back().id
	game.dock()
	check(game.sim.direct_id==game.selected,"Enter direct control")
	game.dock()
	check(game.sim.direct_id==-1,"Exit direct control")
	game.give_selected(6)
	check(game.sim.by_id(game.selected).order==6,"Order UI routes to selected robot")
	game.save_game()
	var saved_tick = game.sim.tick
	game.sim.tick = 999
	game.load_game()
	game.paused = true
	check(game.sim.tick==saved_tick,"Save and load through UI")
	game.show_pause()
	check(game.paused and game.modal != null,"Pause dialog")
	game.close_modal()
	check(not game.paused,"Resume")
	game.speed = 4
	await create_timer(2).timeout
	check(game.sim.tick > saved_tick,"Simulation runs in native scene")
	game.world.zoom = 35
	game.world.focus = game.world.point(game.sim.robots[0].pos)
	await create_timer(0.4).timeout
	await capture("res://build/gameplay.png")
	game.show_help()
	await capture("res://build/help.png")
	game.close_modal()
	game.start_map("core",true)
	game.sim.result = 0
	game.show_result()
	check(game.modal != null and game.campaign_progress.has("core"),"Ending and campaign progress")
	print("UI TESTS: ",checks," checks, ",failures," failures")
	for name in prior_files:
		if prior_files[name] == null:
			DirAccess.remove_absolute("user://"+name)
		else:
			var file = FileAccess.open("user://"+name,FileAccess.WRITE)
			file.store_buffer(prior_files[name])
	quit(1 if failures else 0)
