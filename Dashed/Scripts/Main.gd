extends Node2D

@onready var player = $Player
@onready var enemies_node = $Enemies

@export var enemy_scene: PackedScene
@export var spawn_interval: float = 3.0
@export var max_enemies: int = 8
@export var shield_drop_scene: PackedScene
@export var match_time_threshold: float = 30.0
@export var shield_drop_chance: float = 1.0

var _spawn_timer: float = 0.0
var _rng = RandomNumberGenerator.new()
var match_time: float = 0.0

func _ready():
	for e in enemies_node.get_children():
		if e and is_instance_valid(e) and is_instance_valid(player):
			e.target = player

	_rng.randomize()
	# fallback: se o packed scene não foi atribuído no editor, tenta carregar a cena criada
	if not shield_drop_scene and ResourceLoader.exists("res://Dashed/Scenes/Shield.tscn"):
		shield_drop_scene = load("res://Dashed/Scenes/Shield.tscn")

	# Inicia timer para spawn imediato após _ready
	_spawn_timer = spawn_interval

func _process(delta):
	# tempo de partida (usado para habilitar droppings de itens mais tarde)
	match_time += delta
	# spawn timer
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = spawn_interval
		if enemies_node.get_child_count() < max_enemies and enemy_scene and is_instance_valid(player):
			_spawn_enemy()

func _spawn_enemy():
	# instancia inimigo em posição aleatória dentro da viewport
	var e = enemy_scene.instantiate()
	var vr = get_viewport().get_visible_rect()
	var x = _rng.randi_range(0, int(vr.size.x))
	var y = _rng.randi_range(0, int(vr.size.y))
	e.global_position = Vector2(x, y)
	enemies_node.add_child(e)
	if e and is_instance_valid(e) and is_instance_valid(player):
		e.target = player
		# conecta sinal de morte para dropar itens
		if e.has_signal("died"):
			e.connect("died", Callable(self, "_on_enemy_died"))


func _on_enemy_died(position: Vector2) -> void:
	# checa se já passou do tempo necessário para dropar shields
	if match_time < match_time_threshold:
		return
	# sorteio probabilístico para dropar um escudo
	if shield_drop_scene and _rng.randf() <= shield_drop_chance:
		var s = shield_drop_scene.instantiate()
		s.global_position = position
		add_child(s)
