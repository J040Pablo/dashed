extends CharacterBody2D

@export var speed: float = 120
@export var min_distance: float = 24
@export var attack_damage: int = 10
@export var health: int = 50
@export var attack_cooldown: float = 1.0

var target: Node2D
var attack_timer: float = 0.0

@onready var sprite: AnimatedSprite2D = $Sprite

func _physics_process(delta):
	if not target:
		return

	# Atualiza timer
	attack_timer -= delta

	var direction = (target.global_position - global_position).normalized()
	var distance_to_player = global_position.distance_to(target.global_position)

	if distance_to_player > min_distance:
		# Segue o player
		velocity = direction * speed
		move_and_slide()

		if direction.x > 0:
			sprite.flip_h = false
		elif direction.x < 0:
			sprite.flip_h = true

		if sprite.animation != "Walking":
			sprite.play("Walking")
	else:
		velocity = Vector2.ZERO
		move_and_slide()

		# Ataca se o cooldown terminou
		if attack_timer <= 0:
			attack_player()
			attack_timer = attack_cooldown

func attack_player():
	if target:
		if sprite.animation != "Attack":
			sprite.play("Attack")
		target.take_damage(attack_damage)

func take_damage(damage: int):
	health -= damage
	print("Inimigo HP:", health)
	if health <= 0:
		queue_free()
