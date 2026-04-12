extends Node

@onready var texture_rect = $HBoxContainer/TextureRect

var fps = 10
var frames = []
var current_frame = 0
var timer = 0

func _ready():
	for i in range(1, 700):
		frames.append(load("res://background/frames/frame_%04d.png" % i))
		
func _process(delta):
	timer += delta
	if timer >= 5.0 / fps:
		timer = 0.0
		current_frame = (current_frame + 1) % frames.size()
		texture_rect.texture = frames[current_frame]
		
