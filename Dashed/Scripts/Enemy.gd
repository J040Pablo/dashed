extends CharacterBody2D

@export var speed: float = 120       # Velocidade do inimigo
@export var min_distance: float = 24 # Distância mínima para parar antes do player
var target: Node2D                   # Referência ao player

# Referência ao AnimatedSprite2D
@onready var sprite: AnimatedSprite2D = $Sprite

func _physics_process(delta):
	if not target:
		return

	# Vetor direção para o player
	var direction = (target.global_position - global_position).normalized()
	var distance_to_player = global_position.distance_to(target.global_position)

	if distance_to_player > min_distance:
		# Move o inimigo em direção ao player
		velocity = direction * speed
		move_and_slide()
		
		# Flip horizontal
		if direction.x > 0:
			sprite.flip_h = false
		elif direction.x < 0:
			sprite.flip_h = true
		
		# Toca animação de andar
		if sprite.animation != "Walking":
			sprite.play("Walking")
	else:
		# Para quando próximo do player
		velocity = Vector2.ZERO
		move_and_slide()
		
		# Toca animação de idle
		if sprite.animation != "Idle":
			sprite.play("Idle")
