extends Node2D

var target_enemy = null
var active = true
var returning = false
var speed = 600
var velocity = Vector2.ZERO

func launch(target_pos: Vector2):
	velocity = (target_pos - global_position).normalized() * speed

func _process(_delta):
	if returning:
		var dir = (get_parent().get_node("../Player").global_position - global_position)
		if dir.length() < 5:
			queue_free()
			return
		global_position += dir.normalized() * speed * _delta
	elif target_enemy:
		if not target_enemy.is_inside_tree():
			returning = true
	else:
		global_position += velocity * _delta
		# Colisão com inimigos
		for e in get_parent().get_parent().get_node("Enemies").get_children():
			if global_position.distance_to(e.global_position) < 20:
				target_enemy = e
				velocity = Vector2.ZERO
				break

func pull_player(player):
	if not target_enemy: return
	var dir = (target_enemy.global_position - player.global_position)
	player.global_position += dir.normalized() * speed * get_process_delta_time()
	if dir.length() < 5:
		target_enemy.queue_free()
		queue_free()

func return_to_player():
	target_enemy = null
	returning = true
