extends CharacterBody2D

@export var movement_speed: float = 500
@export var attack_damage: int = 20
@export var health: int = 100
@export var attack_cooldown: float = 0.5
@export var kunai_scene: PackedScene
@export var hook_scene: PackedScene
@export var rocket_scene: PackedScene
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
@export var shield_scale: Vector2 = Vector2(0.12, 0.12)
@export var debug_logs: bool = false

var is_shielding: bool = false
var has_shield: bool = true

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
		if debug_logs:
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
			# Ensure the shield sprite doesn't render at full texture resolution unexpectedly
			if _shield_sprite.texture and _shield_sprite.texture.get_size():
				var tex_size = _shield_sprite.texture.get_size()
				var desired_px = 24.0
				# compensate for parent/global scale and camera zoom so visual size matches desired_px on screen
				var parent_scale = get_global_transform().get_scale()
				var psx = max(0.000001, parent_scale.x)
				var psy = max(0.000001, parent_scale.y)
				var cam = get_viewport().get_camera_2d()
				var cam_zoom = cam.zoom if cam != null else Vector2(1, 1)
				var sx = desired_px / (max(1.0, tex_size.x) * psx * cam_zoom.x)
				var sy = desired_px / (max(1.0, tex_size.y) * psy * cam_zoom.y)
				var final_scale_ready = Vector2(sx, sy) * shield_scale
				_shield_sprite.set_deferred("scale", final_scale_ready)
		else:
			# tenta carregar recurso padrão se existir no projeto
			var p = "res://Dashed/Assets/Sprites/ShieldPlayer.png"
			if ResourceLoader.exists(p):
				_shield_sprite.texture = load(p)
		_shield_sprite.visible = false
		# aplica escala inicial do escudo (defensivo: garante textura e modulate)
		if not _shield_sprite.texture:
			var p = "res://Dashed/Assets/Sprites/ShieldPlayer.png"
			if ResourceLoader.exists(p):
				_shield_sprite.texture = load(p)
		# force safe visual defaults
		_shield_sprite.z_index = 10
		_shield_sprite.modulate = Color(1, 1, 1, 1)
		_shield_sprite.scale = shield_scale

	# garante que a action 'shield' exista no InputMap (mapeada para botão direito do mouse)
	if not InputMap.has_action("shield"):
		# Apenas cria a action; mapeie o botão no Editor (evita mensagens de enum entre versões)
		InputMap.add_action("shield")

	# garante que a action 'rocket' exista (atalho Q)
	if not InputMap.has_action("rocket"):
		# cria a action, não adiciona evento por script — prefira mapear no Editor
		InputMap.add_action("rocket")

	# garante que a action 'dash_key' exista (mapeada para Shift) para detectar Shift de forma cross-version
	if not InputMap.has_action("dash_key"):
		InputMap.add_action("dash_key")
		# Note: não adicionamos evento por script para evitar incompatibilidades entre versões
		# garante que a action 'dash_key' exista (opcional mapping no Editor)

func give_shield():
	# Called when the player picks up a shield pickup in the world
	if has_shield:
		return
	has_shield = true
	if debug_logs:
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
			# Clamp visual size so it never becomes fullscreen
			if _shield_sprite.texture and _shield_sprite.texture.get_size():
					var tex_size2 = _shield_sprite.texture.get_size()
					var desired_px2 = 16.0
					# compensate for parent/global scale and camera zoom when assigning texture
					var parent_scale2 = get_global_transform().get_scale()
					var psx2 = max(0.000001, parent_scale2.x)
					var psy2 = max(0.000001, parent_scale2.y)
					var cam2 = get_viewport().get_camera_2d()
					var cam_zoom2 = cam2.zoom if cam2 != null else Vector2(1, 1)
					var sx2 = desired_px2 / (max(1.0, tex_size2.x) * psx2 * cam_zoom2.x)
					var sy2 = desired_px2 / (max(1.0, tex_size2.y) * psy2 * cam_zoom2.y)
					var final_scale_give = Vector2(sx2, sy2) * shield_scale
					_shield_sprite.set_deferred("scale", final_scale_give)

		# Ensure the player starts with shield visible (player always has shield)
		has_shield = true
		if _shield_sprite:
			# debug: log shield texture size and visible state before forcing visible
			if debug_logs:
				print("[DEBUG] Player._shield_sprite assigned texture size=", _shield_sprite.texture.get_size(), " scale=", _shield_sprite.scale, " visible(before)=", _shield_sprite.visible)
			_shield_sprite.set_deferred("visible", true)

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
		# Debug: log when shield branch is entered
		if debug_logs:
			print("[DEBUG] Shield branch entered: has_shield=", has_shield, " action_shield=", Input.is_action_pressed("shield"), " is_pulled=", is_pulled, " is_dashing=", is_dashing)
		is_shielding = true
		# (removed temporary FORCE) — leave computed scale/visibility to normal logic
		if _shield_sprite:
			_shield_sprite.visible = true
			_shield_sprite.position = shield_offset
			# Compute a pixel-clamped scale so the shield sprite never becomes visually huge.
			if _shield_sprite and _shield_sprite.texture:
				var tex = _shield_sprite.texture
				var tex_size = tex.get_size()
				var desired_px = 16.0
				# consider viewport size: don't exceed 20% of min(viewport)
				var vsize = get_viewport().get_visible_rect().size
				var max_px = min(vsize.x, vsize.y) * 0.2
				desired_px = min(desired_px, max_px)
				# compensate for parent/global scale so visual size matches desired_px on screen
				var parent_scale3 = get_global_transform().get_scale()
				var psx3 = max(0.0001, parent_scale3.x)
				var psy3 = max(0.0001, parent_scale3.y)
				var cam3 = get_viewport().get_camera_2d()
				var cam_zoom3 = cam3.zoom if cam3 != null else Vector2(1, 1)
				var sx = desired_px / (max(1.0, tex_size.x) * psx3 * cam_zoom3.x)
				var sy = desired_px / (max(1.0, tex_size.y) * psy3 * cam_zoom3.y)
				var final_scale = Vector2(sx, sy) * shield_scale
				# clamp to avoid invisible/tiny or fullscreen scales
				var min_scale = 0.000001
				var max_scale = 0.3
				final_scale.x = clamp(final_scale.x, min_scale, max_scale)
				final_scale.y = clamp(final_scale.y, min_scale, max_scale)
				# Debug: print detailed values to help diagnose oversized visuals
				if debug_logs:
					print("[DEBUG] Shield compute: tex_size=", tex_size, " parent_scale=", parent_scale3, " camera_zoom=", cam_zoom3, " desired_px=", desired_px, " sx=", sx, " sy=", sy, " shield_scale=", shield_scale, " final_scale=", final_scale)
				# Apply deferred to avoid immediate override by other engine steps
				_shield_sprite.set_deferred("scale", final_scale)
				_shield_sprite.set_deferred("visible", true)
			else:
				_shield_sprite.scale = shield_scale
				# debug: when showing shield, log texture size and global scale
				if _shield_sprite and _shield_sprite.texture:
					if debug_logs:
						print("[DEBUG] Showing shield: tex_size=", _shield_sprite.texture.get_size(), " local_scale=", _shield_sprite.scale, " global_scale=", _shield_sprite.get_global_transform().get_scale())
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
	# Detecta Shift via InputMap action criada (`dash_key`) para evitar warnings de enum/cast
	# Prefira mapear 'dash_key' no Project Settings -> Input Map
	# Allow dash via InputMap action or fallback to KEY_SHIFT (attempt to support older/newer Godot)
	var shift_pressed := Input.is_action_pressed("dash_key") or Input.is_key_pressed(KEY_SHIFT)
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

	# Disparar foguetes teleguiados (Q) — dispara até 2 foguetes para os inimigos mais próximos
	if Input.is_action_just_pressed("rocket"):
		_fire_rockets(2)


func _fire_rockets(count: int = 2) -> void:
	if not enemies_node:
		return
	# coleta inimigos válidos
	var enemies := []
	for e in enemies_node.get_children():
		if e and is_instance_valid(e):
			enemies.append(e)
	if enemies.size() == 0:
		return
	# dispara para os N inimigos mais próximos (encontra incrementalmente)
	var spawned = 0
	var used := []
	while spawned < count:
		var nearest = null
		var nearest_d = 1e9
		for e in enemies:
			if e in used:
				continue
			var d = global_position.distance_to(e.global_position)
			if d < nearest_d:
				nearest = e
				nearest_d = d
		if nearest == null:
			break
		# instancia foguete
		var rscene := rocket_scene
		if not rscene and ResourceLoader.exists("res://Dashed/Scenes/Rocket.tscn"):
			rscene = load("res://Dashed/Scenes/Rocket.tscn")
		if rscene:
			var r = rscene.instantiate()
			# spawn slightly offset so it doesn't overlap the player
			r.global_position = global_position + Vector2(0, -12)
			# disable monitoring before adding so it won't immediately trigger collision
			r.monitoring = false
			if r.has_method("set_target"):
				r.set_target(nearest)
			elif r.has_variable("target"):
				r.target = nearest
			# adiciona ao nó de projectiles se existir
			if get_parent() and get_parent().has_node("Projectiles"):
				get_parent().get_node("Projectiles").add_child(r)
			else:
				get_parent().add_child(r)
			# re-enable monitoring deferred (safe after current physics/frame)
			r.set_deferred("monitoring", true)
			spawned += 1
			used.append(nearest)
		else:
			if debug_logs:
				print("Rocket scene not found: cannot spawn rocket")
			break
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
	if debug_logs:
		print("Player HP:", health)
	# flash visual ao receber dano
	_flash_sprite(sprite)
	if health <= 0:
		if debug_logs:
			print("Player morreu!")
		queue_free()
