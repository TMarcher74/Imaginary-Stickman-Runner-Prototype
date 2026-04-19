extends Node

@onready var texture_rect = $TextureRect
@onready var floor_container = $Node2D

var frames = []
var frame_floors = {}

var all_lines_nodes: Array = []

var timer = 0
var fps = 10
var current_frame = 0


func _ready():
	load_background()
	load_floor_data()
		
func _process(delta):
	timer += delta
	if timer >= 1.0 / fps:
		timer = 0.0
		current_frame = (current_frame + 1) % frames.size()
		texture_rect.texture = frames[current_frame]
		load_floor(current_frame)

func load_floor(frame_idx: int):
	clear_line_nodes()
	if frame_floors.has(str(frame_idx)) and frame_floors[str(frame_idx)].size() > 0:
		for raw_line in frame_floors[str(frame_idx)]:
			var pts = arr_to_pts(raw_line["points"])
			add_line_node(pts, raw_line["id"])
			print("Loaded floor for frame ", frame_idx, ": ", pts)

func add_line_node(points: Array, id: int = -1) -> Line2D:
	var line = Line2D.new()
	
	line.set_meta("floor_id", id)
	line.default_color = Color.WHITE
	line.width = 3
	line.points = PackedVector2Array(points)

	floor_container.add_child(line)
	all_lines_nodes.append(line)

	return line

func clear_line_nodes():
	for node in all_lines_nodes:
		node.queue_free()
	all_lines_nodes = []

func arr_to_pts(arr: Array) -> Array:
	var points = []
	for p in arr:
		points.append(Vector2(p[0], p[1]))
	return points

func load_background():
	var i = 1
	while i < 100:
		frames.append(load("res://background/frames/frame_%04d.png" % i))
		i += 1
	print("Loaded ", frames.size(), " frames")

		
func load_floor_data():
	if FileAccess.file_exists("res://level_floors.json"):
		var file = FileAccess.open("res://level_floors.json", FileAccess.READ)
		frame_floors = JSON.parse_string(file.get_as_text())
		if frame_floors is not Dictionary:
			frame_floors = {}
