extends Node2D

@export var speed: float = 600
@export var max_distance: float = 600

var player: Node2D
var target_enemy: Node2D = null
var target_position: Vector2 = Vector2.ZERO
var returning: bool = false
var start_position: Vector2

@onready var line: Line2D = $Line2D

func _ready():
	start_position = global_position
	line.clear_points()
	# ponto 0 = posição do player em relação ao gancho, ponto 1 = origem do gancho
	line.add_point(player.global_position - global_position)
	line.add_point(Vector2.ZERO)

	# Conecta sinais para detectar colisões com inimigos (áreas e corpos)
	if has_signal("area_entered"):
		connect("area_entered", Callable(self, "_on_area_entered"))
	if has_signal("body_entered"):
		connect("body_entered", Callable(self, "_on_body_entered"))

func _physics_process(delta):
	if not player:
		queue_free()
		return

	if returning:
		# Volta para o player
		var dir = (player.global_position - global_position).normalized()
		global_position += dir * speed * delta
		if global_position.distance_to(player.global_position) < 10:
			# limpa referência no player antes de remover
			if player:
				player.hook = null
			queue_free()
	else:
		if target_enemy:
			# checa se o alvo ainda é válido (pode ter sido destruído)
			if not is_instance_valid(target_enemy):
				start_return()
				return
			# Gancho preso no inimigo, aguarda input do player
			global_position = target_enemy.global_position
			
			# Se apertar Ctrl (ou tecla de cancelar), retorna o gancho
			var cancel_pressed = Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_ESCAPE)
			if cancel_pressed:
				start_return()
			# Se segurar E, puxa o player para o inimigo
			elif Input.is_action_pressed("hook"):
				if player and not player.is_pulled:
					player.start_pull(target_enemy)
		else:
			# Vai para a posição alvo (capturada quando o gancho foi lançado)
			if target_position == Vector2.ZERO:
				# fallback: captura a posição atual do mouse caso não tenha sido passada
				target_position = get_global_mouse_position()
			var to_target = target_position - global_position
			var dist = to_target.length()
			if dist < 8:
				# chegou no ponto alvo -> inicia retorno
				start_return()
			else:
				var dir = to_target.normalized()
				global_position += dir * speed * delta
				if global_position.distance_to(start_position) > max_distance:
					start_return()

	# Atualiza linha
	line.set_point_position(0, player.global_position - global_position)
	line.set_point_position(1, Vector2.ZERO)

func _on_area_entered(area):
	if area.is_in_group("Enemies"):
		target_enemy = area
		return

func _on_body_entered(body):
	if body.is_in_group("Enemies"):
		target_enemy = body

func is_connected_to_enemy() -> bool:
	return target_enemy != null

func start_return():
	returning = true
	target_enemy = null
