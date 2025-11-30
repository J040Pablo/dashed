extends Node2D

@onready var player = $Player
@onready var enemy = $Enemy

func _ready():
	print("Main carregada com sucesso")
	enemy.target = player
