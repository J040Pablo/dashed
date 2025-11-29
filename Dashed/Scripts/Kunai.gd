extends Node2D

var velocity = Vector2.ZERO
var speed = 600

func launch(target_pos):
	velocity = (target_pos - global_position).normalized() * speed

func _process(_delta):
	global_position += velocity * _delta

	# Colisão com inimigos
	for e in get_parent().get_parent().get_node("Enemies").get_children():
		if global_position.distance_to(e.global_position) < 20:
			e.queue_free()
			queue_free()
			break

	# Sair da tela
	if global_position.x < 0 or global_position.x > 800 or global_position.y < 0 or global_position.y > 600:
		queue_free()
