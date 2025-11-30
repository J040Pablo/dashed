extends CharacterBody2D

@export var movement_speed: float = 500
@export var attack_damage: int = 20
@export var health: int = 100
@export var attack_cooldown: float = 0.5  # segundos entre ataques
@export var kunai_scene: PackedScene
@export var hook_scene: PackedScene

var character_direction: Vector2 = Vector2.ZERO
var hook = null
var attack_timer: float = 0.0
var is_attacking: bool = false

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var enemies_node: Node2D = null

func _ready():
	# Procura pelo nó "Enemies"
	if get_parent().has_node("Enemies"):
		enemies_node = get_parent().get_node("Enemies")
	else:
		print("Atenção: nó 'Enemies' não encontrado!")

	# Conecta sinal de fim de animação
	sprite.connect("animation_finished", Callable(self, "_on_animation_finished"))

func _physics_process(delta):
	# Atualiza cooldown
	if attack_timer > 0:
		attack_timer -= delta

	# Movimento
	character_direction.x = Input.get_axis("move_left", "move_right")
	character_direction.y = Input.get_axis("move_up", "move_down")

	# Flip horizontal
	if character_direction.x > 0:
		sprite.flip_h = false
	elif character_direction.x < 0:
		sprite.flip_h = true

	# Atualiza velocity
	if character_direction.length() > 0:
		velocity = character_direction.normalized() * movement_speed
		if not is_attacking and sprite.animation != "Walking":
			sprite.play("Walking")
	else:
		velocity = velocity.move_toward(Vector2.ZERO, movement_speed)
		if not is_attacking and sprite.animation != "Idle":
			sprite.play("Idle")

	move_and_slide()

	# Ataque corpo a corpo
	if Input.is_action_just_pressed("attack") and attack_timer <= 0:
		attack()
		attack_timer = attack_cooldown

	# Lançar kunai
	if Input.is_action_just_pressed("kunai") and kunai_scene:
		var k = kunai_scene.instantiate()
		k.global_position = global_position
		get_parent().get_node("Projectiles").add_child(k)

	# Gancho
	if Input.is_action_pressed("hook"):
		if hook and hook.target_enemy:
			hook.pull_player(self)
		elif not hook and hook_scene:
			hook = hook_scene.instantiate()
			hook.global_position = global_position
			get_parent().get_node("Projectiles").add_child(hook)

func attack():
	# Reinicia animação de ataque corretamente
	sprite.stop()
	sprite.animation = "Attack"
	sprite.play()
	is_attacking = true

	# Aplica dano
	if enemies_node:
		for e in enemies_node.get_children():
			if e and global_position.distance_to(e.global_position) < 40:
				e.take_damage(attack_damage)

func _on_animation_finished():
	# Volta para Idle após Attack
	if sprite.animation == "Attack":
		is_attacking = false
		sprite.play("Idle")

func take_damage(damage: int):
	health -= damage
	print("Player HP:", health)
	if health <= 0:
		print("Player morreu!")
		queue_free()
