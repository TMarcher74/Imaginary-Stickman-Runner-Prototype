extends Node

var frames = [] # array of loaded pics for each frame of the background
var current_frame = 0 # which frame we're on, used as key for frame_floors
var frame_floors = {} # dictionary, key = frame number, value = list of array of Vector2 points per frame

var all_lines_nodes: Array = [] # Line2D nodes, one per line
var selected_line_idx: int = -1 # which line is selected
var current_points = [] # points of the line we're currently drawing/manipulating
var line_start_pos = Vector2.ZERO # where the mouse was when we started drawing a line, used for straight line mode

var drawing_mode = false # whether we're currently drawing a line (holding mouse button down)
var straight_line_mode = true # whether to draw freehand lines or straight lines

var move_speed = 0.5 # how fast the line moves when using WASD
var rotate_speed = 0.005 # how fast the line rotates when using Q/E

var fps = 10 # how many frames per second the editor runs at

# player
var player_x = 200.0
var player_y = 400.0
var player_scale = 1.0
var target_scale = 1.0

@onready var texture_rect = $HBoxContainer/TextureRect
@onready var label = $HBoxContainer/CanvasLayer/Label
@onready var preview_line = $HBoxContainer/PreviewLine
@onready var id_spin_box = $HBoxContainer/CanvasLayer/IDSpinBox
@onready var scale_spinbox = $HBoxContainer/CanvasLayer/ScaleSpinBox
@onready var player = $Player
@onready var sprite = $Player/Sprite2D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
   # load frames
	load_background()
	load_floors()
	go_to_frame(0)
	connect_buttons()
	player.position.x = player_x

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	handle_input()
	
	# snap player to selected floor
	if selected_line_idx != -1 and not all_lines_nodes.is_empty():
		var selected_node = all_lines_nodes[selected_line_idx]
		var floor_id = selected_node.get_meta("floor_id")
		var floor_y = get_floor_y_at(floor_id, current_frame, player.position.x)
		player.position.y = floor_y

		# scale
		target_scale = selected_node.get_meta("floor_scale", 1.0)
		player_scale = lerp(player_scale, target_scale, delta * 15.0)
		player.scale = Vector2(player_scale, player_scale)

		# skew player based on floor angle
		# var angle = clamp(get_floor_angle(selected_line_idx, current_frame, player_x), -45.0, 45.0)
		var angle = get_floor_angle(selected_line_idx, current_frame, player_x)
		sprite.rotation = lerp_angle(sprite.rotation, angle, delta * 15.0)

func _unhandled_input(event: InputEvent) -> void:
	"""
	This function only runs if the UI (Buttons, SpinBox) didn't consume the input event. 
	Allowing us to use the same keys for both UI interaction and line manipulation without conflicts.
	"""
	# left mouse button starts/stops drawing, mouse motion adds points to current line
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			drawing_mode = true
			selected_line_idx = -1
			current_points = []
			if straight_line_mode:
				line_start_pos = event.position
				current_points = [event.position]
			print("Started drawing at: ", event.position)
		else:
			drawing_mode = false
			preview_line.points = PackedVector2Array([]) # resetting preview line
			if not current_points.is_empty():
				add_line_node(current_points)
				selected_line_idx = all_lines_nodes.size() - 1
				highlight_selected()
				save_frame_lines()
				print("Saved floor for frame ", current_frame, ": ", current_points)

	if event is InputEventMouseMotion and drawing_mode:
		if straight_line_mode:
			current_points = [line_start_pos, event.position]
			print("End of line pointing at: ", event.position)
		else:
			if current_points.is_empty() or event.position.distance_to(current_points.back()) > 5.0:
				current_points.append(event.position)

		preview_line.points = PackedVector2Array(current_points)

func _input(event: InputEvent) -> void:
	# delete key deletes selected line
	if event is InputEventKey and event.pressed and event.keycode == KEY_DELETE:
		if selected_line_idx != -1:
			all_lines_nodes[selected_line_idx].queue_free()
			all_lines_nodes.remove_at(selected_line_idx)
			selected_line_idx = -1
			current_points = []
			save_frame_lines()

			# after deletion, select the last line if there are any left
			if all_lines_nodes.size() > 0:
				selected_line_idx = all_lines_nodes.size() - 1
				current_points = Array(all_lines_nodes[selected_line_idx].points)
				highlight_selected()

	# tab key cycles through lines
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		if all_lines_nodes.size() > 1:
			selected_line_idx = (selected_line_idx + 1) % all_lines_nodes.size()
			current_points = Array(all_lines_nodes[selected_line_idx].points)
			highlight_selected()

func handle_input():
	if selected_line_idx==-1 or all_lines_nodes.is_empty():
		return

	var node = all_lines_nodes[selected_line_idx]
	current_points = Array(node.points)
	var moved = false
	var offset = Vector2.ZERO
	
	if Input.is_key_pressed(KEY_W): offset.y -= move_speed
	if Input.is_key_pressed(KEY_S): offset.y += move_speed
	if Input.is_key_pressed(KEY_A): offset.x -= move_speed
	if Input.is_key_pressed(KEY_D): offset.x += move_speed
	
	if offset != Vector2.ZERO:
		current_points = current_points.map(func(p): return p + offset)
		moved = true
	
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_E):
		var angle = rotate_speed if Input.is_key_pressed(KEY_E) else -rotate_speed
		var center = _get_center(current_points)
		current_points = current_points.map(func(p): return p.rotated(angle) + center - center.rotated(angle))
		moved = true
	
	if moved:
		node.points = PackedVector2Array(current_points)
		save_frame_lines()

func _get_center(points: Array) -> Vector2:
	var sum = Vector2.ZERO
	for p in points:
		sum += p
	return sum / points.size()
		
func go_to_frame(n):
	current_frame = clamp(n, 0, frames.size() - 1)
	texture_rect.texture = frames[current_frame]

	clear_line_nodes()
	clear_ghost_lines()
	selected_line_idx = -1
	current_points = []

	# load current frame line
	if frame_floors.has(str(current_frame)) and frame_floors[str(current_frame)].size() > 0:
		for raw_line in frame_floors[str(current_frame)]:
			var pts = arr_to_pts(raw_line["points"])
			var scale = raw_line.get("scale", 1.0)
			add_line_node(pts, raw_line["id"], scale)
			print("Loaded floor for frame ", current_frame, ": ", pts)

		selected_line_idx = all_lines_nodes.size() - 1
		current_points = arr_to_pts(frame_floors[str(current_frame)].back()["points"])
		
		highlight_selected()
		
	# load ghost of previous and next frame
	if $HBoxContainer/CanvasLayer/Green.button_pressed:
		load_ghost_line(current_frame, -1)
	if $HBoxContainer/CanvasLayer/Red.button_pressed:
		load_ghost_line(current_frame, +1)

func load_ghost_line(cur_frame, offset):
	var valid = false
	if offset < 0 and cur_frame > 0:
		valid = true
	if offset > 0 and cur_frame < frames.size() - 1:
		valid = true

	var tag = "ghost_prev" if offset < 0 else "ghost_next"
	for child in $HBoxContainer.get_children():
		if child.get_meta("ghost_tag", "") == tag:
			child.queue_free()

	var target_frame = str(cur_frame + offset)
	if valid and frame_floors.has(target_frame):
		for raw_line in frame_floors[target_frame]:
			var ghost = Line2D.new()
			ghost.width = 5
			ghost.default_color = Color.CHARTREUSE if offset < 0 else Color.ORANGE_RED
			ghost.modulate.a = 0.5
			ghost.points = PackedVector2Array(arr_to_pts(raw_line["points"]))
			ghost.set_meta("ghost_tag", tag)
			$HBoxContainer.add_child(ghost)
		
func clear_line_nodes():
	for node in all_lines_nodes:
		node.queue_free()
	all_lines_nodes = []

func clear_ghost_lines():
	for child in $HBoxContainer.get_children():
		if child.get_meta("ghost_tag", "") != "":
			child.queue_free()

func add_line_node(points: Array, id: int = -1, floor_scale: float = 1.0) -> Line2D:
	var line = Line2D.new()
	# if no id given, auto assign next available
	var assigned_id = id if id != -1 else get_next_floor_id()
	line.set_meta("floor_id", assigned_id)
	line.set_meta("floor_scale", floor_scale)
	line.default_color = Color.WHITE
	line.width = 5
	line.points = PackedVector2Array(points)

	$HBoxContainer.add_child(line)
	all_lines_nodes.append(line)

	#to keep ghost lines on top
	for child in $HBoxContainer.get_children():
		if child.get_meta("ghost_tag", "") != "":
			$HBoxContainer.move_child(child, -1)
	$HBoxContainer.move_child(preview_line, -1)

	return line

func set_selected_id():
	if selected_line_idx == -1:
		return
	var new_id = int(id_spin_box.value)
	all_lines_nodes[selected_line_idx].set_meta("floor_id", new_id)
	save_frame_lines()
	highlight_selected()

func set_selected_scale():
	if selected_line_idx == -1:
		return
	var new_scale = scale_spinbox.value
	all_lines_nodes[selected_line_idx].set_meta("floor_scale", new_scale)
	save_frame_lines()

func get_next_floor_id() -> int:
	var max_id = -1
	for key in frame_floors:
		for line_data in frame_floors[key]:
			if line_data["id"] > max_id:
				max_id = line_data["id"]
	return max_id + 1

func get_floor_scale(floor_id, frame_num) -> float:
	if not frame_floors.has(str(frame_num)):
		return player_scale
	for line_data in frame_floors[str(frame_num)]:
		if line_data["id"] == floor_id:
			return line_data.get("scale", 1.0)
	return player_scale

func get_floor_y_at(floor_id, frame_num, x_pos) -> float:
	"""
	Get the Y position of the floor with the given ID at the given X position for the specified frame
	"""
	if not frame_floors.has(str(frame_num)):
		return player.position.y

	for line_data in frame_floors[str(frame_num)]:
		if line_data["id"] != floor_id:
			continue

		var pts = arr_to_pts(line_data["points"])
		pts.sort_custom(func(a, b): return a.x < b.x)

		if pts.size() < 2:				# if only one point, return its Y; if no points, return current player Y
			return pts[0].y if pts.size() == 1 else player.position.y

		for i in range(pts.size() - 1):
			var a = pts[i]
			var b = pts[i + 1]
			if x_pos >= a.x and x_pos <= b.x:
				var t = (x_pos - a.x) / (b.x - a.x)
				return lerp(a.y, b.y, t)		# linear interpolation between a and b based on x_pos
		if x_pos < pts[0].x:
			return pts[0].y						# if player is left of the first point, return Y of first point			
		return pts[pts.size() - 1].y			# if player is right of the last point, return Y of last point
	return player.position.y					# if floor ID not found, return last valid Y to avoid sudden drops					

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
		pts.sort_custom(func(a, b): return a.x < b.x)

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

func apply_scale_to_all_frames():
	if selected_line_idx == -1:
		return
	var floor_id = all_lines_nodes[selected_line_idx].get_meta("floor_id")
	var floor_scale = all_lines_nodes[selected_line_idx].get_meta("floor_scale", 1.0)

	for key in frame_floors:
		for line_data in frame_floors[key]:
			if line_data["id"] == floor_id:
				line_data["scale"] = floor_scale

	save_floors()
	print("Applied scale ", floor_scale, " to all frames for floor ID ", floor_id)

func next_frame():
	go_to_frame(current_frame + 1)

func prev_frame():
	go_to_frame(current_frame - 1)
	
func duplicate_previous():
	var prev = str(current_frame - 1)
	if not frame_floors.has(prev):
		return

	clear_line_nodes()
	selected_line_idx = -1

	print("Duping")
	for raw_line in frame_floors[prev]:
		add_line_node(arr_to_pts(raw_line))

	selected_line_idx = all_lines_nodes.size() - 1
	highlight_selected()
	save_frame_lines()

func highlight_selected():
	for i in range(all_lines_nodes.size()):
		all_lines_nodes[i].default_color = Color.YELLOW if i == selected_line_idx else Color.WHITE
	if selected_line_idx != -1:
		id_spin_box.value = all_lines_nodes[selected_line_idx].get_meta("floor_id")
		scale_spinbox.value = all_lines_nodes[selected_line_idx].get_meta("floor_scale", 1.0)
		label.text = "Frame: %d / %d  |  Floor ID: %d | Floor Scale: %d" % [current_frame, frames.size() - 1, id_spin_box.value, scale_spinbox.value]
		
func toggle_straight_mode():
	straight_line_mode = !straight_line_mode
	$HBoxContainer/CanvasLayer/GayButton.text = "Straight" if straight_line_mode else "Freehand"

# Vector2 can't survive JSON roundtrip, manually convert
func pts_to_arr(points: Array) -> Array:
	var arr = []
	for p in points:
		arr.append([p.x, p.y])
	return arr

func arr_to_pts(arr: Array) -> Array:
	var points = []
	for p in arr:
		points.append(Vector2(p[0], p[1]))
	return points
		
func connect_buttons():
	$HBoxContainer/CanvasLayer/PrevButton.pressed.connect(prev_frame)
	$HBoxContainer/CanvasLayer/NextButton.pressed.connect(next_frame)
	$HBoxContainer/CanvasLayer/DupeButton.pressed.connect(duplicate_previous)
	$HBoxContainer/CanvasLayer/GayButton.pressed.connect(toggle_straight_mode)
	$HBoxContainer/CanvasLayer/SetIDButton.pressed.connect(set_selected_id)
	$HBoxContainer/CanvasLayer/SetScaleButton.pressed.connect(set_selected_scale)
	$HBoxContainer/CanvasLayer/SetScaleToAllButton.pressed.connect(apply_scale_to_all_frames)

func load_background():
	var i = 1
	while i < 100:
		frames.append(load("res://background/frames/frame_%04d.png" % i))
		i += 1
	print("Loaded ", frames.size(), " frames")

func save_frame_lines():
	var all = []
	for node in all_lines_nodes:
		all.append({
			"id": node.get_meta("floor_id"),
			"scale": node.get_meta("floor_scale", 1.0),
			"points": pts_to_arr(Array(node.points))
		})
	frame_floors[str(current_frame)] = all
	save_floors()

func save_floors():
	var file = FileAccess.open("res://level_floors.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(frame_floors))

func load_floors():
	if FileAccess.file_exists("res://level_floors.json"):
		var file = FileAccess.open("res://level_floors.json", FileAccess.READ)
		frame_floors = JSON.parse_string(file.get_as_text())
		if frame_floors is not Dictionary:
			frame_floors = {}
