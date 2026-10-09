extends Control
signal navigate(position: Vector2)
var sim
var craft = Vector2.ZERO
var selected = -1
const COLORS = [Color("6bdcdd"),Color("f27c66"),Color("a79875")]

func _ready():
	custom_minimum_size = Vector2(280,112)
	mouse_filter = Control.MOUSE_FILTER_STOP

func project(p: Vector2) -> Vector2:
	return Vector2(10,10)+Vector2(p.x/sim.width,p.y/sim.depth)*(size-Vector2(20,20))

func _draw():
	draw_style_box(panel(),Rect2(Vector2.ZERO,size))
	if sim == null: return
	for x in range(1,8):
		var px = x*size.x/8
		draw_line(Vector2(px,6),Vector2(px,size.y-6),Color(0.2,0.3,0.32,0.4))
	for b in sim.buildings:
		if not b.alive: continue
		var point = project(Vector2(b.pos))
		var color = COLORS[b.owner if b.owner >= 0 else 2]
		var radius = 4 if b.kind == 0 else 2
		draw_rect(Rect2(point-Vector2.ONE*radius,Vector2.ONE*radius*2),color)
	for r in sim.robots:
		if r.alive: draw_circle(project(Vector2(r.pos)),2.2,COLORS[r.owner])
	var p = project(craft)
	draw_circle(p,5,Color.WHITE,false,1.2)
	draw_line(p-Vector2(8,0),p+Vector2(8,0),Color.WHITE,1)
	draw_line(p-Vector2(0,8),p+Vector2(0,8),Color.WHITE,1)

func panel() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color("0d1a21")
	style.border_color = Color("3c5159")
	style.set_border_width_all(1)
	return style

func _gui_input(event):
	if sim != null and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var fraction = (event.position-Vector2(10,10))/(size-Vector2(20,20))
		navigate.emit(Vector2(clampf(fraction.x,0,1)*sim.width,clampf(fraction.y,0,1)*sim.depth))
		accept_event()
