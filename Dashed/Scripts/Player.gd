extends CharacterBody2D

@export var speed: float = 200
@export var kunai_scene: PackedScene
@export var hook_scene: PackedScene
@export var movement_speed: float = 500

var character_direction: Vector2 = Vector2.ZERO
var hook = null

# Referência ao AnimatedSprite2D
@onready var sprite: AnimatedSprite2D = $Sprite

func _physics_process(delta):
	# Movimento
	character_direction.x = Input.get_axis("move_left", "move_right")
	character_direction.y = Input.get_axis("move_up", "move_down")

	# Flip horizontal
	if character_direction.x > 0:
		sprite.flip_h = false
	elif character_direction.x < 0:
		sprite.flip_h = true

	# Movimento e animação
	if character_direction.length() > 0:
		velocity = character_direction.normalized() * movement_speed
		if sprite.animation != "Walking":
			sprite.play("Walking")
	else:
		velocity = velocity.move_toward(Vector2.ZERO, movement_speed)
		if sprite.animation != "Idle":
			sprite.play("Idle")

	move_and_slide()

	# Ataque corpo a corpo
	if Input.is_action_just_pressed("attack"):
		attack()
		# Pode tocar animação de ataque depois
		# sprite.play("Attack")

	# Lançar kunai
	if Input.is_action_just_pressed("kunai") and kunai_scene:
		var k = kunai_scene.instantiate()
		k.global_position = global_position
		get_parent().get_node("Projectiles").add_child(k)
		# k.launch(get_global_mouse_position()) → criar função launch

	# Gancho
	if Input.is_action_pressed("hook"):
		if hook and hook.target_enemy:
			hook.pull_player(self)
		elif not hook and hook_scene:
			hook = hook_scene.instantiate()
			hook.global_position = global_position
			get_parent().get_node("Projectiles").add_child(hook)
			# hook.launch(get_global_mouse_position()) → criar função launch

func attack():
	for e in get_parent().get_node("Enemies").get_children():
		if global_position.distance_to(e.global_position) < 40:
			e.queue_free()
			if hook and hook.target_enemy == e:
				hook.return_to_player()
