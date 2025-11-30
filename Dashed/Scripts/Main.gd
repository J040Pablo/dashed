extends Node2D

@onready var player = $Player
@onready var enemies_node = $Enemies

func _ready():
	for e in enemies_node.get_children():
		if e:
			e.target = player
