extends CharacterBody2D

@export var movement_speed: float = 500
@export var attack_damage: int = 20
@export var health: int = 100
@export var attack_cooldown: float = 0.5
@export var kunai_scene: PackedScene
@export var hook_scene: PackedScene
@export var pull_speed: float = 800 # velocidade do player sendo puxado pelo gancho
@export var pull_arrive_distance: float = 16
@export var sliding_speed: float = 400 # velocidade reduzida quando o player está sendo puxado (Sliding)
@export var dash_speed: float = 500
@export var dash_duration: float = 1
@export var dash_cooldown: float = 0.5
@export var dash_distance: float = 80.0
@export var shield_texture: Texture2D
@export var shield_offset: Vector2 = Vector2(0, 0)
@export var shield_move_multiplier: float = 0.5
@export var shield_scale: Vector2 = Vector2(0.6, 0.6)

var is_shielding: bool = false
var has_shield: bool = false

var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_direction: Vector2 = Vector2.ZERO
var last_move_dir: Vector2 = Vector2.RIGHT
var prev_shift_pressed: bool = false
var dash_start_position: Vector2 = Vector2.ZERO

var character_direction: Vector2 = Vector2.ZERO
var hook: Node = null
var attack_timer: float = 0.0
var is_attacking: bool = false
var is_pulled: bool = false
var pull_target: Node2D = null

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var enemies_node: Node2D = null
@onready var _shield_sprite: Sprite2D = null

func _ensure_flash_shader(target_sprite: AnimatedSprite2D):
	# Ensure the sprite has a ShaderMaterial with a 'flash_amount' uniform
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
	# set flash to 1 then tween back to 0
	mat.set_shader_parameter("flash_amount", 1.0)
	# animação manual do flash para compatibilidade (reduz flash_amount até 0)
	var steps = int(max(1, duration / 0.016))
	var step_time = duration / steps
	for i in range(steps):
		await get_tree().create_timer(step_time).timeout
		var v = lerp(1.0, 0.0, float(i + 1) / steps)
		mat.set_shader_parameter("flash_amount", v)
	mat.set_shader_parameter("flash_amount", 0.0)

func _ready():
	if get_parent().has_node("Enemies"):
		enemies_node = get_parent().get_node("Enemies")
	else:
		print("Atenção: nó 'Enemies' não encontrado!")

	sprite.connect("animation_finished", Callable(self, "_on_animation_finished"))

	# cria o Sprite2D do escudo (se não existir) e atribui textura exportada
	if not has_node("ShieldSprite"):
		var s = Sprite2D.new()
		s.name = "ShieldSprite"
		s.z_index = 10
		add_child(s)
		_shield_sprite = s
	else:
		_shield_sprite = get_node("ShieldSprite")

	if _shield_sprite and not _shield_sprite.texture:
		if shield_texture:
			_shield_sprite.texture = shield_texture
		else:
			# tenta carregar recurso padrão se existir no projeto
			var p = "res://Dashed/Assets/Sprites/ShieldPlayer.png"
			if ResourceLoader.exists(p):
				_shield_sprite.texture = load(p)
		_shield_sprite.visible = false
		# aplica escala inicial do escudo
		_shield_sprite.scale = shield_scale

	# garante que a action 'shield' exista no InputMap (mapeada para botão direito do mouse)
	if not InputMap.has_action("shield"):
		InputMap.add_action("shield")
		var ev := InputEventMouseButton.new()
		# use explicit button index for right mouse (2) to avoid enum name differences
		ev.button_index = 2
		InputMap.action_add_event("shield", ev)

func give_shield():
	# Called when the player picks up a shield pickup in the world
	if has_shield:
		return
	has_shield = true
	print("Shield obtained!")
	# small flash to indicate pickup
	_flash_sprite(sprite, 0.18)
	# play Sliding animation briefly to show pickup
	var pickup_anim := "Sliding"
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(pickup_anim):
		sprite.animation = pickup_anim
		sprite.play()
		await get_tree().create_timer(0.28).timeout
		# after the brief sliding, return to Idle if exists
		if sprite.sprite_frames and sprite.sprite_frames.has_animation("Idle"):
			sprite.play("Idle")
	# ensure the shield sprite texture is set (so when player holds shield it shows)
	if _shield_sprite and not _shield_sprite.texture:
		var p = "res://Dashed/Assets/Sprites/ShieldPlayer.png"
		if ResourceLoader.exists(p):
			_shield_sprite.texture = load(p)

func _physics_process(delta):
	if attack_timer > 0:
		attack_timer -= delta

	# atualiza cooldown do dash
	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer -= delta

	if is_pulled and pull_target:
		# Player sendo puxado pelo gancho — animação de sliding
		var pulled_anim := "Sliding"
		if sprite.sprite_frames and sprite.sprite_frames.has_animation(pulled_anim):
			if sprite.animation != pulled_anim:
				sprite.animation = pulled_anim
				sprite.play()
		else:
			# fallback caso a animação não exista
			if sprite.sprite_frames and sprite.sprite_frames.has_animation("Idle"):
				if sprite.animation != "Idle":
					sprite.animation = "Idle"
					sprite.play()

		var to_target = pull_target.global_position - global_position
		var dist = to_target.length()
		if dist == 0:
			# já chegou
			if pull_target.has_method("die"):
				pull_target.die()
			elif pull_target.has_method("take_damage"):
				pull_target.take_damage(attack_damage)
			is_pulled = false
			pull_target = null
			if hook:
				hook.start_return()
			return

		var dir = to_target.normalized()
		# vira o sprite para a direção do pull (horizontal)
		if dir.x > 0:
			sprite.flip_h = false
		elif dir.x < 0:
			sprite.flip_h = true
		# calcula próxima posição baseada na velocidade reduzida (sliding) e no delta
		var next_pos = global_position + dir * sliding_speed * delta
		var next_dist = next_pos.distance_to(pull_target.global_position)
		# se chegar próximo o suficiente ou ultrapassar o alvo, considera chegada
		if next_dist <= pull_arrive_distance or next_dist > dist:
			global_position = pull_target.global_position
			if pull_target.has_method("die"):
				pull_target.die()
			elif pull_target.has_method("take_damage"):
				pull_target.take_damage(attack_damage)
			is_pulled = false
			pull_target = null
			if hook:
				hook.start_return()
			velocity = Vector2.ZERO
			return

		velocity = dir * sliding_speed
		move_and_slide()
		return

	# Movimentação normal
	character_direction.x = Input.get_axis("move_left", "move_right")
	character_direction.y = Input.get_axis("move_up", "move_down")

	# atualiza última direção de movimento (usada quando dash só com Shift)
	if character_direction.length() > 0:
		last_move_dir = character_direction.normalized()

	# Shield: checa a action 'shield' (mapeada para botão direito ou customizada no InputMap)
	# Só permite usar o escudo se o jogador já tiver pego (has_shield)
	if has_shield and Input.is_action_pressed("shield") and not is_pulled and not is_dashing:
		is_shielding = true
		if _shield_sprite:
			_shield_sprite.visible = true
			_shield_sprite.position = shield_offset
			_shield_sprite.scale = shield_scale
			# acompanha flip do jogador
			_shield_sprite.flip_h = sprite.flip_h
	else:
		is_shielding = false
		if _shield_sprite:
			_shield_sprite.visible = false

	# Flip do sprite
	if character_direction.x > 0:
		sprite.flip_h = false
	elif character_direction.x < 0:
		sprite.flip_h = true

	# Dash: Shift + direção => dash; Shift sozinho => dash na última direção
	# Uso de tecla direta para Shift (KEY_SHIFT) para aceitar Shift esquerdo/direito
	var shift_pressed := Input.is_key_pressed(KEY_SHIFT)
	var shift_just_pressed := shift_pressed and not prev_shift_pressed
	if shift_pressed and not is_dashing and dash_cooldown_timer <= 0.0 and not is_pulled and not is_shielding:
		# checa se alguma direção foi apertada agora
		var dir_input := Vector2.ZERO
		if Input.is_action_just_pressed("move_left"):
			dir_input.x = -1
		elif Input.is_action_just_pressed("move_right"):
			dir_input.x = 1
		if Input.is_action_just_pressed("move_up"):
			dir_input.y = -1
		elif Input.is_action_just_pressed("move_down"):
			dir_input.y = 1
		# decide direção do dash
		if dir_input != Vector2.ZERO:
			dash_direction = dir_input.normalized()
			is_dashing = true
			dash_timer = dash_duration
			dash_cooldown_timer = dash_cooldown
			dash_start_position = global_position
			# toca animação Sliding se existir
			if sprite.sprite_frames and sprite.sprite_frames.has_animation("Sliding"):
				sprite.animation = "Sliding"
				sprite.play()
			# vira o sprite para a direção do dash
			if dash_direction.x > 0:
				sprite.flip_h = false
			elif dash_direction.x < 0:
				sprite.flip_h = true
		elif shift_just_pressed and last_move_dir != Vector2.ZERO:
			dash_direction = last_move_dir
			is_dashing = true
			dash_timer = dash_duration
			dash_cooldown_timer = dash_cooldown
			dash_start_position = global_position
			# toca animação Sliding se existir
			if sprite.sprite_frames and sprite.sprite_frames.has_animation("Sliding"):
				sprite.animation = "Sliding"
				sprite.play()
			# vira o sprite para a direção do dash
			if dash_direction.x > 0:
				sprite.flip_h = false
			elif dash_direction.x < 0:
				sprite.flip_h = true

	# Se estiver puxando o player pelo gancho, não aplica a movimentação normal
	if not is_pulled and not is_dashing:
		# movimento com normalização para velocidade constante em diagonais
		if character_direction.length() > 0:
			var move_speed := movement_speed
			if is_shielding:
				move_speed *= shield_move_multiplier
			velocity = character_direction.normalized() * move_speed
			# toca animação de caminhada se existir e não estiver atacando
			if not is_attacking and sprite.sprite_frames and sprite.sprite_frames.has_animation("Walking"):
				if sprite.animation != "Walking":
					sprite.play("Walking")
		else:
			# desacelera suavemente
			velocity = velocity.move_toward(Vector2.ZERO, movement_speed)
			# volta para Idle se existir e não estiver atacando
			if not is_attacking and sprite.sprite_frames and sprite.sprite_frames.has_animation("Idle"):
				if sprite.animation != "Idle":
					sprite.play("Idle")

		move_and_slide()

	# Processa dash em andamento (override de movimento)
	if is_dashing:
		dash_timer -= delta
		# se passou da distância máxima, encerra o dash
		var traveled = dash_start_position.distance_to(global_position)
		if traveled >= dash_distance:
			is_dashing = false
			velocity = Vector2.ZERO
			# volta para Idle (se existir)
			if sprite.sprite_frames and sprite.sprite_frames.has_animation("Idle"):
				sprite.play("Idle")
			return
		# aplica movimento do dash
		velocity = dash_direction.normalized() * dash_speed
		move_and_slide()
		if dash_timer <= 0.0:
			is_dashing = false
			velocity = Vector2.ZERO
			# volta para Idle (se existir)
			if sprite.sprite_frames and sprite.sprite_frames.has_animation("Idle"):
				sprite.play("Idle")
		return

	# atualiza estado anterior da tecla Shift (usado para detectar press)
	prev_shift_pressed = shift_pressed

	# Ataque corpo a corpo
	if Input.is_action_just_pressed("attack") and attack_timer <= 0 and not is_shielding:
		attack()
		attack_timer = attack_cooldown

	# Lançar kunai
	if Input.is_action_just_pressed("kunai") and kunai_scene and not is_shielding:
		var k = kunai_scene.instantiate()
		k.global_position = global_position
		get_parent().get_node("Projectiles").add_child(k)

	# Lançar gancho
	if Input.is_action_just_pressed("hook") and not hook and hook_scene and not is_shielding:
		hook = hook_scene.instantiate()
		hook.global_position = global_position
		hook.player = self
		# captura a posição do cursor no momento do lançamento (para o gancho não seguir o cursor)
		if hook.has_method("set"):
			# se o nó aceitar atribuição direta
			hook.target_position = get_global_mouse_position()
		else:
			# fallback
			hook.target_position = get_global_mouse_position()
		get_parent().add_child(hook)

	# Soltar gancho
	if hook and Input.is_action_just_pressed("hook_release") and not is_shielding:
		hook.start_return()
		# se o jogador estiver sendo puxado, cancela o pull imediatamente
		if is_pulled:
			is_pulled = false
			pull_target = null

func start_pull(target: Node2D):
	is_pulled = true
	pull_target = target

func attack():
	sprite.stop()
	sprite.animation = "Attack"
	sprite.play()
	is_attacking = true

	if enemies_node:
		for e in enemies_node.get_children():
			if e and global_position.distance_to(e.global_position) < 40:
				e.take_damage(attack_damage)

func _on_animation_finished():
	if sprite.animation == "Attack":
		is_attacking = false
		sprite.play("Idle")

func take_damage(damage: int):
	# Ignora dano enquanto está sendo puxado pelo gancho
	# Ignora dano enquanto está sendo puxado pelo gancho ou segurando o escudo
	if is_pulled or is_shielding:
		return

	health -= damage
	print("Player HP:", health)
	# flash visual ao receber dano
	_flash_sprite(sprite)
	if health <= 0:
		print("Player morreu!")
		queue_free()
