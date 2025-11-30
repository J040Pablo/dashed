extends CharacterBody2D

signal died(position)

@export var speed: float = 20
@export var min_distance: float = 24
@export var attack_damage: int = 10
@export var health: int = 50
@export var attack_cooldown: float = 1.0

var target: Node2D
var attack_timer: float = 0.0

@onready var sprite: AnimatedSprite2D = $Sprite

func _ensure_flash_shader(target_sprite: AnimatedSprite2D):
	if not target_sprite:
		return
	var mat = target_sprite.material
	if mat and mat is ShaderMaterial:
		return
	var sh = Shader.new()
	sh.code = """
		shader_type canvas_item;
		uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
		void fragment() {
			vec4 tex = texture(TEXTURE, UV);
			vec3 outcol = mix(tex.rgb, vec3(1.0), flash_amount);
			COLOR = vec4(outcol, tex.a);
		}
	"""
	var sm = ShaderMaterial.new()
	sm.shader = sh
	target_sprite.material = sm

func _flash_sprite(target_sprite: AnimatedSprite2D, duration := 0.12):
	if not target_sprite:
		return
	_ensure_flash_shader(target_sprite)
	var mat = target_sprite.material
	if not mat or not (mat is ShaderMaterial):
		return
	mat.set_shader_parameter("flash_amount", 1.0)
	# animação manual do flash para compatibilidade (reduz flash_amount até 0)
	var steps = int(max(1, duration / 0.016))
	var step_time = duration / steps
	for i in range(steps):
		await get_tree().create_timer(step_time).timeout
		var v = lerp(1.0, 0.0, float(i + 1) / steps)
		mat.set_shader_parameter("flash_amount", v)
	mat.set_shader_parameter("flash_amount", 0.0)

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
	# flash visual ao receber dano
	_flash_sprite(sprite)
	if health <= 0:
		# emit signal and use die() so other systems can react (drops, effects)
		die()

func die():
	# Morte imediata (usado por efeitos como dash/gancho)
	emit_signal("died", global_position)
	queue_free()
