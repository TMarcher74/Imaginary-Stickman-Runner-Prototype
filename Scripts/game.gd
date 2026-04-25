extends Node

@onready var texture_rect = $TextureRect
@onready var floor_container = $Node2D
@onready var player = $Player
@onready var sprite = $Player/Sprite2D
@onready var debug_label = $CanvasLayer/DebugLabel

var frames = []
var frame_floors = {}
var all_lines_nodes: Array = []
var timer = 0
var fps = 10
var current_frame = 0

# player
var player_x = 200.0
var player_y = 400.0
var target_y = 400.0
var current_floor_id = 0
var smoothing = 15.0
var input_locked = false
var last_valid_y: float = 400.0  # add this at top with other vars

func _ready():
	load_background()
	load_floor_data()
	load_floor(0)
	player.position.x = player_x
		
func _process(delta):
	timer += delta
	if timer >= 100.0 / fps:
		timer = 0.0
		current_frame = (current_frame + 1) % frames.size()
		texture_rect.texture = frames[current_frame]
		load_floor(current_frame)
		target_y = get_floor_y_at(current_floor_id, current_frame, player_x)

	#lerp player y position to floor
	player_y = lerp(player_y, target_y, delta * smoothing)
	player.position.y = target_y

	# skew player based on floor angle
	# var angle = clamp(get_floor_angle(current_floor_id, current_frame, player_x), -0.1, 0.1)
	# sprite.rotation = lerp_angle(sprite.rotation, angle, delta * smoothing)

	debug_label.text = """
	frame: %d
	floor_id: %d
	player_x: %.1f
	player_y: %.1f
	target_y: %.1f
	last_valid_y: %.1f
	angle: %.3f
	"""%[current_frame, current_floor_id, player_x, player_y, target_y, last_valid_y, sprite.rotation]

func _input(event):
	if input_locked:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP or event.keycode == KEY_W:
			switch_floor(-1)
		if event.keycode == KEY_DOWN or event.keycode == KEY_S:
			switch_floor(1)

func switch_floor(direction):
	"""
	Switch to the next floor in the given direction (-1 for up, 1 for down)
	"""
	var floors = get_floors_sorted_by_y(current_frame)
	if floors.is_empty():
		return
	
	# find current floor index
	var current_idx = -1
	for i in range(floors.size()):
		if floors[i] == current_floor_id:
			current_idx = i
			break

	# switch to next floor
	var next_idx = current_idx + direction
	if next_idx < 0 or next_idx >= floors.size():
		return
	current_floor_id = floors[next_idx]

	input_locked = true
	# wait a moment to prevent rapid switching
	# await get_tree().create_timer(0.3).timeout
	input_locked = false

func get_floors_sorted_by_y(frame_num) -> Array:
	"""
	Get floor IDs sorted by their average Y position for the given frame
	"""
	if not frame_floors.has(str(frame_num)):
		return []

	# calculate average Y for each floor and sort by it
	var id_y_pairs = []
	for line_data in frame_floors[str(frame_num)]:
		var pts = arr_to_pts(line_data["points"])
		var avg_y = 0.0
		for p in pts:
			avg_y += p.y

		avg_y /= pts.size()
		id_y_pairs.append({"id": line_data["id"], "avg_y": avg_y})
		
	id_y_pairs.sort_custom(func(a, b): return a["avg_y"] < b["avg_y"])
	return id_y_pairs.map(func(pair): return pair["id"])

func get_floor_y_at(floor_id, frame_num, x_pos) -> float:
	"""
	Get the Y position of the floor with the given ID at the given X position for the specified frame
	"""
	if not frame_floors.has(str(frame_num)):
		return last_valid_y

	for line_data in frame_floors[str(frame_num)]:
		if line_data["id"] != floor_id:
			continue

		var pts = arr_to_pts(line_data["points"])
		pts.sort_custom(func(a, b): return a.x < b.x)

		if pts.size() < 2:				# if only one point, return its Y; if no points, return current player Y
			return pts[0].y if pts.size() == 1 else last_valid_y	

		for i in range(pts.size() - 1):
			var a = pts[i]
			var b = pts[i + 1]
			if x_pos >= a.x and x_pos <= b.x:
				var t = (x_pos - a.x) / (b.x - a.x)
				last_valid_y = lerp(a.y, b.y, t)
				return last_valid_y				# linear interpolation between a and b based on x_pos
		if x_pos < pts[0].x:
			last_valid_y = pts[0].y
			return last_valid_y					# if player is left of the first point, return Y of first point			
		last_valid_y = pts[pts.size() - 1].y
		return last_valid_y						# if player is right of the last point, return Y of last point
	return last_valid_y							# if floor ID not found, return last valid Y to avoid sudden drops					

func get_floor_angle(floor_id, frame_num, x_pos) -> float:
	"""
	Get the angle of the floor with the given ID at the given X position for the specified frame
	"""
	if not frame_floors.has(str(frame_num)):
		return 0.0

	for line_data in frame_floors[str(frame_num)]:
		if line_data["id"] != floor_id:
			continue

		var pts = arr_to_pts(line_data["points"])
		if pts.size() < 2:
			return 0.0									# if less than 2 points, return 0 angle
		for i in range(pts.size() - 1):
			var a = pts[i]
			var b = pts[i + 1]
			if x_pos >= a.x and x_pos <= b.x:
				return (b - a).angle()					# angle of the segment between points a and b
		if x_pos < pts[0].x:
			return (pts[1] - pts[0]).angle()			# if player is left of the first point, return angle of first segment
		var last = pts.size() - 1
		return (pts[last] - pts[last - 1]).angle()		# if player is right of the last point, return angle of last segment
	return 0.0											# if floor ID not found, return 0 angle to avoid skewing


func load_floor(frame_idx: int):
	clear_line_nodes()
	if frame_floors.has(str(frame_idx)) and frame_floors[str(frame_idx)].size() > 0:
		for raw_line in frame_floors[str(frame_idx)]:
			var pts = arr_to_pts(raw_line["points"])
			add_line_node(pts, raw_line["id"])
			# print("Loaded floor for frame ", frame_idx, ": ", pts)

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
	# print("Loaded ", frames.size(), " frames")

		
func load_floor_data():
	if FileAccess.file_exists("res://level_floors.json"):
		var file = FileAccess.open("res://level_floors.json", FileAccess.READ)
		frame_floors = JSON.parse_string(file.get_as_text())
		if frame_floors is not Dictionary:
			frame_floors = {}
