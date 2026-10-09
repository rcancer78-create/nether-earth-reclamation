extends Node3D
const Simulation = preload("res://src/simulation.gd")
const Rules = preload("res://src/rules.gd")
const World = preload("res://src/world_view.gd")
const MiniMap = preload("res://src/minimap.gd")
const Audio = preload("res://src/audio.gd")
const INK = Color("e5ece8")
const MUTED = Color("8ba1ab")
const CYAN = Color("6bdcdd")
const ORANGE = Color("e6ad70")
var sim = Simulation.new()
var world
var sound
var ui: CanvasLayer
var hud: Control
var overlay: Control
var modal: PanelContainer
var resources_label: Label
var mission_label: Label
var selection_label: Label
var status_label: Label
var briefing_label: Label
var toast_label: Label
var order_box: VBoxContainer
var minimap
var health: ProgressBar
var craft = Vector2(14,18)
var selected = -1
var accumulator = 0.0
var ui_accumulator = 0.0
var running = false
var paused = false
var speed = 1.0
var toast_time = 0.0
var mission_id = "breach"
var maps: Array = []
var campaign_progress: Dictionary = {}
var build_chassis: OptionButton
var build_checks: Array = []
var build_cost: Label
var build_base = -1
var build_preview: Node3D
var auto_test = false
var auto_time = 0.0
var screenshot_path = ""
var smoke_map = "breach"
var preview_world
var preview_robot
var hero
var speed_button: Button
var quitting = false

func _ready():
	get_tree().auto_accept_quit = false
	DisplayServer.window_set_title("NETHER EARTH / RECLAMATION")
	load_maps()
	load_progress()
	world = World.new()
	add_child(world)
	sound = Audio.new()
	add_child(sound)
	ui = CanvasLayer.new()
	add_child(ui)
	create_theme()
	create_hud()
	for arg in OS.get_cmdline_user_args():
		if arg == "--smoke": auto_test = true
		if arg.begins_with("--screenshot="): screenshot_path = arg.trim_prefix("--screenshot=")
		if arg.begins_with("--map="): smoke_map = arg.trim_prefix("--map=")
	if auto_test:
		start_map(smoke_map,true)
		give_selected(6)
	else:
		start_map("breach",false)
		show_menu()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST: safe_quit()

func safe_quit():
	if quitting: return
	quitting = true
	# Give the renderer frames to retire viewport/sky resources before shutdown.
	for child in get_children(): child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()

func load_maps():
	maps.clear()
	for id in ["original","breach","relay","core"]:
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/"+id+".json"))
		if data is Dictionary: maps.append(data)
	DirAccess.make_dir_recursive_absolute("user://maps")
	for file in DirAccess.get_files_at("user://maps"):
		if not file.ends_with(".json"): continue
		var data = JSON.parse_string(FileAccess.get_file_as_string("user://maps/"+file))
		if Simulation.valid_map(data):
			var duplicate = false
			for existing in maps:
				if existing.id == data.id: duplicate = true
			if not duplicate: maps.append(data)

func create_theme():
	var theme = Theme.new()
	theme.default_font_size = 16
	theme.set_color("font_color","Label",INK)
	theme.set_color("font_color","Button",INK)
	theme.set_color("font_hover_color","Button",Color.WHITE)
	for kind in ["Button","OptionButton"]:
		theme.set_stylebox("normal",kind,style(Color("1a2b34"),Color("3a505c"),6,12))
		theme.set_stylebox("hover",kind,style(Color("294753"),CYAN,6,12))
		theme.set_stylebox("pressed",kind,style(Color("31505a"),CYAN,6,12))
		theme.set_stylebox("focus",kind,style(Color(0,0,0,0),CYAN,6,12))
	theme.set_stylebox("panel","PanelContainer",style(Color(0.035,0.067,0.09,0.95),Color("344750"),8,20))
	theme.set_stylebox("background","ProgressBar",style(Color("192c32"),Color("192c32"),2,0))
	theme.set_stylebox("fill","ProgressBar",style(CYAN,CYAN,2,0))
	var root = Control.new()
	root.name = "Interface"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme
	ui.add_child(root)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)

func style(bg: Color, border: Color, radius: int, margin: int) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	return s

func label(text: String, size: int = 16, color: Color = INK) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size",size)
	l.add_theme_color_override("font_color",color)
	return l

func paragraph(text: String, width: float = 540) -> Label:
	var l = label(text,17,MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l

func button(text: String, callback: Callable, parent: Node, minimum: Vector2 = Vector2(0,40)) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = minimum
	b.pressed.connect(callback)
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b

func panel(parent: Node, position: Vector2, dimensions: Vector2) -> PanelContainer:
	var p = PanelContainer.new()
	p.position = position
	p.size = dimensions
	parent.add_child(p)
	return p

func vbox(parent: Node, spacing: int = 10) -> VBoxContainer:
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation",spacing)
	parent.add_child(box)
	return box

func create_hud():
	var top = panel(hud,Vector2(24,20),Vector2(1552,78))
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 24
	top.offset_right = -24
	top.offset_top = 20
	top.offset_bottom = 98
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation",28)
	top.add_child(row)
	var title = label("NETHER\nEARTH",21)
	row.add_child(title)
	row.add_child(label("/",30,CYAN))
	var context = vbox(row,2)
	mission_label = label("ПЕРВЫЙ РАЗЛОМ",16)
	context.add_child(mission_label)
	status_label = label("ОПЕРАЦИЯ RECLAMATION",12,MUTED)
	context.add_child(status_label)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	resources_label = label("",15)
	row.add_child(resources_label)
	button("Ⅱ",toggle_pause,row,Vector2(44,38)).tooltip_text = "Пауза · P"
	speed_button = button("×1",func(): cycle_speed(),row,Vector2(52,38))
	button("МЕНЮ",show_pause,row,Vector2(90,38))
	var left = panel(hud,Vector2(24,120),Vector2(306,0))
	var info = vbox(left,10)
	info.add_child(label("ОПЕРАЦИЯ / 01",12,CYAN))
	briefing_label = paragraph("Захватите или уничтожьте\nвсе базы Инсигниан.",256)
	info.add_child(briefing_label)
	info.add_child(label("ТАКТИЧЕСКАЯ СЕТЬ",12,MUTED))
	minimap = MiniMap.new()
	info.add_child(minimap)
	minimap.navigate.connect(func(p): craft = p; world.focus = Vector3(p.x*3,0,p.y*3))
	var help = label("ЛКМ  выбрать    ПКМ  приказ\nWASD  корабль    E  стыковка\nКолесо  масштаб    Q / R  обзор",12,MUTED)
	info.add_child(help)
	var right = panel(hud,Vector2.ZERO,Vector2(306,480))
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -330
	right.offset_right = -24
	right.offset_top = 120
	order_box = vbox(right,8)
	order_box.add_child(label("КОМАНДНЫЙ КАНАЛ",12,CYAN))
	selection_label = label("KESTREL / КОМАНДИР",19)
	order_box.add_child(selection_label)
	health = ProgressBar.new()
	health.custom_minimum_size.y = 4
	health.show_percentage = false
	order_box.add_child(health)
	var instructions = paragraph("Выберите свой робот или базу. Захватывайте заводы, чтобы получать модули.",256)
	instructions.name = "Detail"
	order_box.add_child(instructions)
	button("СОБРАТЬ РОБОТА     B",show_build,order_box)
	button("ПРЯМОЕ УПРАВЛЕНИЕ     E",dock,order_box)
	var order_select = OptionButton.new()
	order_select.name = "Orders"
	order_select.fit_to_longest_item = false
	order_select.clip_text = true
	for i in 9: order_select.add_item(Rules.ORDERS[i],i)
	order_select.item_selected.connect(func(index): give_selected(index))
	order_select.custom_minimum_size.y = 44
	order_box.add_child(order_select)
	button("ЗАХВАТ ЗАВОДОВ",func(): give_selected(6),order_box)
	button("АТАКА БАЗ",func(): give_selected(8),order_box)
	button("ОБОРОНА",func(): give_selected(0),order_box)
	button("ЯДЕРНЫЙ ПОДРЫВ",confirm_nuclear,order_box)
	var bottom = panel(hud,Vector2.ZERO,Vector2(100,52))
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 24
	bottom.offset_right = -24
	bottom.offset_top = -68
	bottom.offset_bottom = -20
	var bottom_row = HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation",24)
	bottom.add_child(bottom_row)
	bottom_row.add_child(label("●  КАНАЛ ОТКРЫТ",12,CYAN))
	toast_label = label("Захватите промышленность. Сохраните последнюю базу.",14)
	toast_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_child(toast_label)
	bottom_row.add_child(label("F1  справка     F5  сохранить     F9  загрузить",12,MUTED))

func modal_box(width: float = 650) -> VBoxContainer:
	close_modal()
	var dim = ColorRect.new()
	dim.color = Color(0.008,0.017,0.025,0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	modal = PanelContainer.new()
	modal.custom_minimum_size.x = width
	modal.add_theme_stylebox_override("panel",style(Color("101e27"),Color("48606c"),10,30))
	center.add_child(modal)
	var box = vbox(modal,14)
	paused = true
	return box

func close_modal():
	preview_world = null
	preview_robot = null
	for c in overlay.get_children():
		overlay.remove_child(c)
		c.queue_free()
	modal = null
	build_cost = null
	if running: paused = false

func show_menu():
	running = false
	hud.visible = false
	var box = modal_box(720)
	var center: CenterContainer = modal.get_parent()
	center.anchor_right = 0.56
	overlay.get_child(0).color.a = 0.3
	if not is_instance_valid(hero):
		world.create_robot({"id":-1000,"pos":sim.buildings[0].pos+Vector2i(18,6),"parts":186,"owner":0})
		hero = world.actors[-1000].root
		hero.scale = Vector3.ONE*5.0
	world.zoom = 56
	world.yaw = -0.2
	world.focus = hero.position+Vector3(-14,6,0)
	box.add_child(label("RECLAMATION     /     NATIVE 3D STRATEGY",13,CYAN))
	box.add_child(label("NETHER EARTH",54))
	box.add_child(label("ЗЕМЛЯ ПОМНИТ ВАШ ПРИКАЗ",16,ORANGE))
	box.add_child(paragraph("Модульные боевые машины. Промышленная война. Последний человеческий плацдарм. Возглавьте освобождение поверхности — и узнайте, что скрывается под ней.",630))
	button("НАЧАТЬ КАМПАНИЮ     →",func(): show_briefing("breach"),box,Vector2(0,54))
	button("ОРИГИНАЛЬНАЯ КАРТА / ZX 1987",func(): show_briefing("original"),box)
	button("ГЛАВЫ И ПОЛЬЗОВАТЕЛЬСКИЕ КАРТЫ",show_missions,box)
	button("ПРОДОЛЖИТЬ СОХРАНЕНИЕ",load_game,box)
	var row = HBoxContainer.new()
	box.add_child(row)
	button("УПРАВЛЕНИЕ",show_help,row,Vector2(200,40))
	button("ЗВУК: ВКЛ / ВЫКЛ",func(): sound.muted = not sound.muted; toast("Звук выключен" if sound.muted else "Звук включён"),row,Vector2(200,40))
	button("ВЫХОД",safe_quit,row,Vector2(200,40))
	box.add_child(label("FAN REMAKE  /  0.1    ·    GODOT 4.5    ·    OFFLINE",11,MUTED))

func show_missions():
	load_maps()
	var box = modal_box(740)
	box.add_child(label("ТЕАТРЫ ВОЙНЫ",30))
	for map in maps:
		var id = str(map.id)
		var completed = "  ✓" if campaign_progress.has(id) else ""
		button(str(map.get("title",id))+completed+"   /   "+str(map.get("subtitle","")),func(): show_briefing(id),box)
	box.add_child(paragraph("Новые карты: JSON в папке пользовательских данных / maps. Все главы доступны отдельно; прохождение отмечается автоматически.",650))
	button("ОТКРЫТЬ ПАПКУ КАРТ",func(): OS.shell_open(ProjectSettings.globalize_path("user://maps")),box)
	button("НАЗАД",show_menu,box)

func find_map(id: String):
	for map in maps:
		if map.id == id: return map
	return maps[1]

func show_briefing(id: String):
	var data = find_map(id)
	var box = modal_box(720)
	box.add_child(label(str(data.get("title",id)),30))
	box.add_child(label(str(data.get("subtitle","")),17,ORANGE))
	box.add_child(paragraph(str(data.get("briefing","Захватите или уничтожьте все базы противника.")),630))
	box.add_child(label("ЦЕЛЬ  /  Все базы противника захвачены или уничтожены",15,CYAN))
	box.add_child(label("ПРОФИЛЬ ПРОТИВНИКА",12,MUTED))
	var ai = OptionButton.new()
	for name in ["Классический / ZX","Тактик / адаптивный","Осада / агрессивный"]: ai.add_item(name)
	ai.select(["classic","tactician","siege"].find(data.ai))
	box.add_child(ai)
	button("НАЧАТЬ ОПЕРАЦИЮ     →",func(): start_map(id,true,["classic","tactician","siege"][ai.selected]),box,Vector2(0,52))
	button("НАЗАД",show_menu,box)

func start_map(id: String, play: bool = true, ai: String = ""):
	hero = null
	mission_id = id
	sim.setup(find_map(id),ai)
	world.setup(sim)
	world.zoom = 52
	world.yaw = 0
	minimap.sim = sim
	selected = sim.robots[0].id if not sim.robots.is_empty() else sim.buildings[0].id
	craft = Vector2(sim.buildings[0].pos)+Vector2(1,4)
	world.focus = Vector3(craft.x*3+10,0,craft.y*3)
	accumulator = 0
	running = play
	paused = not play
	hud.visible = play
	close_modal()
	refresh_hud()
	toast("Начните с захвата заводов. B — сборка робота, F1 — помощь.")

func _process(delta):
	if quitting: return
	if world.camera == null: return
	auto_time += delta
	if auto_test and auto_time > 8:
		if not screenshot_path.is_empty():
			get_viewport().get_texture().get_image().save_png(screenshot_path)
		print("SMOKE_OK ticks=",sim.tick," robots=",sim.robots.size()," buildings=",sim.buildings.size())
		safe_quit()
		return
	if running and not paused:
		var movement = Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
		if sim.direct_id >= 0:
			sim.direct_direction = -1 if movement == Vector2.ZERO else sim.direction(Vector2i(movement))
			sim.direct_fire = Input.is_physical_key_pressed(KEY_SPACE)
			var r = sim.by_id(sim.direct_id)
			if r != null: craft = Vector2(r.pos)
		else:
			craft += movement.normalized()*delta*(20 if Input.is_physical_key_pressed(KEY_SHIFT) else 9)
			craft.x = clampf(craft.x,2,sim.width-3)
			craft.y = clampf(craft.y,2,sim.depth-3)
		if movement != Vector2.ZERO or sim.direct_id >= 0: world.focus = world.focus.lerp(Vector3(craft.x*3,0,craft.y*3),minf(1,delta*6))
		world.yaw += (float(Input.is_physical_key_pressed(KEY_Q))-float(Input.is_physical_key_pressed(KEY_R)))*delta*0.85
		accumulator += delta*speed
		var iterations = 0
		while accumulator >= Rules.TICK_SECONDS and iterations < 20:
			accumulator -= Rules.TICK_SECONDS
			sim.step()
			iterations += 1
			for event in sim.events:
				world.effect(event)
				if event.type in ["shot","hit","explosion","nuclear","capture"]: sound.play_event(event.type)
				if event.type == "capture": toast(("Объект захвачен" if event.owner == 0 else "Противник захватил объект")+" / "+Rules.RESOURCE_NAMES[event.kind])
				if event.type in ["income","message"]: toast(event.text)
				if event.type == "radio": toast("РАДИО / "+event.text); sound.play_event("radio")
			sim.events.clear()
			if sim.result >= 0:
				show_result()
				break
	world.update_view(delta,craft,selected)
	if preview_robot != null and is_instance_valid(preview_robot): preview_robot.rotation.y += delta*0.4
	if not running and is_instance_valid(hero): hero.rotation.y = sin(auto_time*0.14)*0.5+0.5
	ui_accumulator += delta
	if ui_accumulator > 0.15:
		ui_accumulator = 0
		refresh_hud()
	toast_time -= delta
	if toast_time < 0 and running: toast_label.text = "ПКМ — приказ в точку / по объекту. Захват: удерживайте робота у входа в здание."

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				if modal != null and running: close_modal()
				elif running: show_pause()
				else: show_menu()
			KEY_F1: show_help()
			KEY_F11: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
		if not running or modal != null: return
		match event.physical_keycode:
			KEY_B: show_build()
			KEY_E: dock()
			KEY_P: toggle_pause()
			KEY_F5: save_game()
			KEY_F9: load_game()
			KEY_TAB: next_robot()
			KEY_1: speed = 1
			KEY_2: speed = 2
			KEY_3: speed = 4
			KEY_HOME:
				for b in sim.buildings:
					if b.alive and b.owner == 0 and b.kind == 0: craft = Vector2(b.pos); selected = b.id; world.focus = world.point(b.pos); break
	if not running or modal != null: return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: world.zoom = maxf(25,world.zoom-5)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: world.zoom = minf(140,world.zoom+5)
		if event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
			var point = world.pick(event.position)
			if not sim.inside(point): return
			var target = nearest_entity(point)
			if event.button_index == MOUSE_BUTTON_LEFT:
				selected = target.id if target != null else -1
				refresh_hud()
			else:
				var r = sim.by_id(selected)
				if r == null or not r.has("parts") or r.owner != 0: return
				if target != null and target.has("kind") and target.owner != 0:
					var order = 8 if target.kind == 0 else (6 if target.owner == -1 else 7)
					sim.give_order(r.id,order)
					r.target = target.id
				elif target != null and target.has("parts") and target.owner == 1:
					sim.give_order(r.id,3)
					r.target = target.id
				else: sim.give_order(r.id,9,point)
				toast("Приказ передан / "+Rules.ORDERS[r.order])

func nearest_entity(point: Vector2i):
	var best = null
	var distance = 3.5
	for r in sim.robots:
		if r.alive and r.pos.distance_to(point) < distance: best = r; distance = r.pos.distance_to(point)
	if best != null: return best
	for b in sim.buildings:
		var d = Vector2(b.pos-Vector2i(0,2)).distance_to(point)
		if b.alive and d < 5: return b
	return null

func refresh_hud():
	if sim.map.is_empty(): return
	mission_label.text = str(sim.map.get("title",mission_id))
	var day_ticks = int(sim.map.get("day_ticks",288))
	var minutes = int(float(sim.tick % day_ticks)*1440/day_ticks)
	status_label.text = "%s  ·  ДЕНЬ %02d / %02d:%02d  ·  %s ×%d" % [str(sim.profile.name),1+int(sim.tick/day_ticks),int(minutes/60),minutes%60,"ПАУЗА" if paused else "АКТИВНО",int(speed)]
	speed_button.text = "×%d" % int(speed)
	var stock = sim.resources[0]
	resources_label.text = "ОБЩ %02d   ЭЛ %02d   ЯД %02d   ФЗ %02d   РК %02d   ПШ %02d   ШС %02d" % stock
	briefing_label.text = "Базы: %d свои / %d врага\nРоботы: %d / 24\nЗахватите или уничтожьте\nвсе базы Инсигниан." % [sim.count_bases(0),sim.count_bases(1),sim.count_robots(0)]
	minimap.craft = craft
	minimap.queue_redraw()
	var target = sim.by_id(selected)
	var detail: Label = order_box.get_node("Detail")
	health.visible = target != null
	if target == null:
		selection_label.text = "KESTREL / КОМАНДИР"
		detail.text = "Выберите свой робот или базу. B — сборка, Tab — следующий робот."
	elif target.has("parts"):
		selection_label.text = ("СОЮЗНИК" if target.owner == 0 else "ИНСИГНИАН")+" / %02d" % target.id
		health.value = target.hp
		var names = []
		for i in 8:
			if target.parts & (1 << i): names.append(Rules.PART_NAMES[i])
		detail.text = ", ".join(names)+"\n\n"+Rules.ORDERS[target.order]+"\nПрочность: %d / 100" % target.hp
		if sim.direct_id == target.id: detail.text += "\nПИЛОТ: WASD · Пробел · E выход"
	else:
		selection_label.text = "ВОЕННАЯ БАЗА" if target.kind == 0 else "ЗАВОД / "+Rules.RESOURCE_NAMES[target.kind].to_upper()
		health.value = float(target.capture)/int(sim.map.get("capture_ticks",144))*100
		detail.text = ("Наш объект" if target.owner == 0 else ("Объект противника" if target.owner == 1 else "Нейтральный объект"))+"\nДоход: "+("5 общих" if target.kind == 0 else "2 модуля")+" / сутки\nВход: %d : %d" % [target.pos.x,target.pos.y]
		if target.capture > 0: detail.text += "\nЗахват: %d%%" % health.value

func give_selected(order: int):
	var r = sim.by_id(selected)
	if r == null or not r.has("parts") or r.owner != 0:
		toast("Сначала выберите свой робот")
		return
	sim.give_order(selected,order)
	toast("Приказ: "+Rules.ORDERS[r.order])

func next_robot():
	var ids = []
	for r in sim.robots:
		if r.alive and r.owner == 0: ids.append(r.id)
	if ids.is_empty(): return
	selected = ids[(ids.find(selected)+1)%ids.size()]
	craft = Vector2(sim.by_id(selected).pos)
	world.focus = world.point(sim.by_id(selected).pos)

func dock():
	if sim.direct_id >= 0:
		sim.direct_id = -1
		toast("Автопилот восстановлен")
		return
	var r = sim.by_id(selected)
	if r != null and r.owner == 0:
		if r.has("parts"):
			sim.direct_id = r.id
			craft = Vector2(r.pos)
			toast("Прямое управление: WASD — движение; Пробел — огонь; E — выход")
		else: show_build()
	else: toast("Выберите свой робот или базу для стыковки")

func show_build():
	var base = sim.by_id(selected)
	if base == null or not base.has("kind") or base.kind != 0 or base.owner != 0:
		var nearest = INF
		base = null
		for b in sim.buildings:
			if b.alive and b.kind == 0 and b.owner == 0 and Vector2(b.pos).distance_to(craft) < nearest:
				base = b
				nearest = Vector2(b.pos).distance_to(craft)
	if base == null: toast("Нет доступной базы"); return
	build_base = base.id
	var box = modal_box(740)
	box.add_child(label("СБОРОЧНЫЙ КОМПЛЕКС",30))
	box.add_child(label("БАЗА %02d  /  ШАССИ + 1–3 ОРУЖИЯ + ЭЛЕКТРОНИКА" % base.id,13,CYAN))
	var columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation",24)
	box.add_child(columns)
	var controls = vbox(columns,9)
	controls.custom_minimum_size.x = 320
	var viewport_container = SubViewportContainer.new()
	viewport_container.custom_minimum_size = Vector2(280,280)
	viewport_container.stretch = true
	columns.add_child(viewport_container)
	var viewport = SubViewport.new()
	viewport.size = Vector2i(280,280)
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(viewport)
	preview_world = World.new()
	preview_world.sim = sim
	preview_world.actors_root = Node3D.new()
	preview_world.add_child(preview_world.actors_root)
	viewport.add_child(preview_world)
	var preview_camera = Camera3D.new()
	preview_camera.position = Vector3(4.5,3.8,6)
	preview_camera.fov = 34
	viewport.add_child(preview_camera)
	preview_camera.look_at(Vector3(0,1.7,0))
	var preview_light = DirectionalLight3D.new()
	preview_light.rotation_degrees = Vector3(-40,-30,0)
	preview_light.light_energy = 2.0
	viewport.add_child(preview_light)
	var preview_fill = DirectionalLight3D.new()
	preview_fill.rotation_degrees = Vector3(-15,140,0)
	preview_fill.light_color = CYAN
	preview_fill.light_energy = 0.6
	viewport.add_child(preview_fill)
	var preview_environment = WorldEnvironment.new()
	preview_environment.environment = Environment.new()
	preview_environment.environment.background_mode = Environment.BG_COLOR
	preview_environment.environment.background_color = Color("111e28")
	preview_environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	preview_environment.environment.ambient_light_color = Color("94b0c0")
	preview_environment.environment.ambient_light_energy = 0.5
	viewport.add_child(preview_environment)
	build_chassis = OptionButton.new()
	for i in 3: build_chassis.add_item(Rules.PART_NAMES[i]+"    /    "+str(Rules.COST[i])+" ед.")
	build_chassis.select(1)
	build_chassis.item_selected.connect(func(_i): update_build_cost())
	controls.add_child(build_chassis)
	build_checks.clear()
	for i in range(3,8):
		var check = CheckBox.new()
		check.text = Rules.PART_NAMES[i]+"    /    "+str(Rules.COST[i])+" ед."
		check.button_pressed = i in [3,7]
		check.toggled.connect(func(_on): update_build_cost())
		controls.add_child(check)
		build_checks.append(check)
	build_cost = paragraph("",650)
	box.add_child(build_cost)
	button("СОБРАТЬ И ВЫПУСТИТЬ",func():
		var error = sim.construct(build_base,build_mask())
		if error.is_empty():
			selected = sim.robots.back().id
			close_modal()
			toast("Робот выпущен. Выберите приказ после выхода из ангара.")
		else: build_cost.text = error
	,box,Vector2(0,50))
	button("ОТМЕНА",close_modal,box)
	update_build_cost()

func build_mask() -> int:
	var mask = 1 << build_chassis.selected
	for i in build_checks.size():
		if build_checks[i].button_pressed: mask |= 1 << (i+3)
	return mask

func update_build_cost():
	if build_cost == null: return
	var mask = build_mask()
	if preview_world != null:
		for child in preview_world.actors_root.get_children(): child.queue_free()
		preview_world.create_robot({"id":-1,"pos":Vector2i.ZERO,"parts":mask,"owner":0})
		preview_robot = preview_world.actors[-1].root
		preview_robot.position = Vector3.ZERO
		preview_robot.rotation.y = 0.5
	var cost = 0
	for i in 8:
		if mask & (1 << i): cost += Rules.COST[i]
	var paid = Rules.payment(sim.resources[0],mask)
	build_cost.text = "Стоимость модулей: %d  /  Высота брони: %d\n" % [cost,Rules.height(mask)]
	if not Rules.valid_parts(mask): build_cost.text += "Нужно от 1 до 3 видов оружия."
	elif paid.is_empty(): build_cost.text += "Недостаточно ресурсов. Захватывайте заводы и дождитесь суточного дохода."
	else: build_cost.text += "Из общих ресурсов: %d. Сначала расходуются запасы профильных заводов." % (sim.resources[0][0]-paid[0])

func confirm_nuclear():
	var r = sim.by_id(selected)
	if r == null or not r.has("parts") or r.owner != 0 or not r.parts & 64: toast("Нужен свой робот с ядерным зарядом"); return
	var id = selected
	var box = modal_box(620)
	box.add_child(label("ЯДЕРНЫЙ ПОДРЫВ",30,ORANGE))
	box.add_child(paragraph("Заряд уничтожит носитель, соседних роботов и здания обеих сторон. Подтвердите боевой приказ.",540))
	button("ПОДОРВАТЬ",func(): sim.detonate(id); close_modal(),box)
	button("ОТМЕНА",close_modal,box)

func toggle_pause():
	if modal == null: paused = not paused

func cycle_speed():
	speed = 2 if speed == 1 else (4 if speed == 2 else 1)
	toast("Скорость симуляции ×%d" % int(speed))

func show_pause():
	var box = modal_box()
	box.add_child(label("КОМАНДОВАНИЕ / ПАУЗА",28))
	button("ВЕРНУТЬСЯ В БОЙ",close_modal,box)
	button("СОХРАНИТЬ",func(): save_game(); close_modal(),box)
	button("ЗАГРУЗИТЬ",load_game,box)
	button("УПРАВЛЕНИЕ",show_help,box)
	button("ЗВУК: ВКЛ / ВЫКЛ",func(): sound.muted = not sound.muted,box)
	button("ГЛАВНОЕ МЕНЮ",show_menu,box)

func show_help():
	var box = modal_box(780)
	box.add_child(label("ПОЛЕВОЕ РУКОВОДСТВО",30))
	box.add_child(paragraph("ЛКМ — выбрать робот / здание. ПКМ — двигаться, атаковать робота или захватывать здание. Приказы автономны: отряд сам ищет цель. Tab — следующий свой робот; Home — своя база.\n\nWASD — корабль и камера, Shift — быстрее. Q / R — поворот камеры; колесо — масштаб. E — управление выбранным роботом: WASD и Пробел для стрельбы. E снова возвращает автопилот.\n\nB — сборка. Требуется одно шасси, 1–3 оружия; электроника увеличивает дальность. Заводы дают профильные ресурсы, база — общие. Запас каждого типа ограничен 99.\n\nДля захвата стойте на отмеченном входе до заполнения индикатора. Здания уничтожаются только ядерным зарядом. Ядерный взрыв поражает обе стороны. Потеря последней базы означает поражение.\n\nP — пауза. 1 / 2 / 3 — скорость ×1 / ×2 / ×4. F5 / F9 — сохранение / загрузка. F11 — полный экран. Esc — меню.\n\nКлассический профиль воспроизводит ключевые правила и структуру решений ZX. Это реконструкция, а не тактовая эмуляция оригинала.",690))
	button("ПОНЯТНО",func(): close_modal() if running else show_menu(),box)

func show_result():
	var victory = sim.result == 0
	if victory:
		campaign_progress[mission_id] = {"tick":sim.tick,"destroyed":sim.bases_destroyed}
		var file = FileAccess.open("user://campaign.json",FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(campaign_progress))
	var box = modal_box(720)
	box.add_child(label("ОПЕРАЦИЯ ЗАВЕРШЕНА" if victory else "ПЛАЦДАРМ ПОТЕРЯН",30,CYAN if victory else ORANGE))
	var report = str(sim.map.get("debrief","Противник лишился всех баз.")) if victory else "Последняя база потеряна. Защищайте промышленный плацдарм и держите резерв у входа в базу."
	if victory and mission_id == "core": report += "\n\nАрхив сохранён. Обе цивилизации услышат друг друга." if sim.bases_destroyed == 0 else "\n\nЧасть архива утрачена в ядерных вспышках. Оставшиеся голоса зовут к перемирию."
	box.add_child(paragraph(report,630))
	if victory and not str(sim.map.get("next","")).is_empty():
		var next = str(sim.map.next)
		button("СЛЕДУЮЩАЯ ГЛАВА",func(): show_briefing(next),box)
	button("ПОВТОРИТЬ",func(): start_map(mission_id),box)
	button("ГЛАВНОЕ МЕНЮ",show_menu,box)

func save_game():
	var state = sim.snapshot()
	state.view = {"craft":[craft.x,craft.y],"selected":selected,"zoom":world.zoom,"yaw":world.yaw}
	var file = FileAccess.open("user://save.tmp",FileAccess.WRITE)
	if file == null: toast("Ошибка записи сохранения"); return
	file.store_string(JSON.stringify(state))
	file.close()
	var destination = ProjectSettings.globalize_path("user://save.json")
	if FileAccess.file_exists(destination):
		DirAccess.copy_absolute(destination,ProjectSettings.globalize_path("user://save.backup.json"))
	var error = DirAccess.rename_absolute(ProjectSettings.globalize_path("user://save.tmp"),destination)
	toast("Игра сохранена" if error == OK else "Не удалось заменить файл сохранения")

func load_game():
	if not FileAccess.file_exists("user://save.json"):
		var box = modal_box()
		box.add_child(label("СОХРАНЕНИЕ НЕ НАЙДЕНО",26))
		button("НАЗАД",func(): close_modal() if running else show_menu(),box)
		return
	var state = JSON.parse_string(FileAccess.get_file_as_string("user://save.json"))
	var candidate = Simulation.new()
	if not state is Dictionary or not candidate.restore(state):
		toast("Файл сохранения повреждён или несовместим")
		return
	sim = candidate
	hero = null
	mission_id = str(sim.map.id)
	world.setup(sim)
	minimap.sim = sim
	craft = Vector2(sim.buildings[0].pos)
	selected = -1
	if state.has("view"):
		craft = Vector2(state.view.craft[0],state.view.craft[1])
		selected = int(state.view.selected)
		world.zoom = float(state.view.zoom)
		world.yaw = float(state.view.yaw)
	world.focus = Vector3(craft.x*3,0,craft.y*3)
	accumulator = 0
	running = true
	hud.visible = true
	close_modal()
	toast("Сохранение загружено")
	if sim.result >= 0: show_result()

func load_progress():
	if FileAccess.file_exists("user://campaign.json"):
		var data = JSON.parse_string(FileAccess.get_file_as_string("user://campaign.json"))
		if data is Dictionary: campaign_progress = data

func toast(text: String):
	toast_label.text = text
	toast_time = 7.0
