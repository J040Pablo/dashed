extends Area2D

@export var lifetime: float = 20.0
@export var pickup_sound: AudioStream

var _timer: float = 0.0

func _ready():
	# Collision body_entered via signal
	connect("body_entered", Callable(self, "_on_body_entered"))
	_timer = lifetime

func _process(delta):
	_timer -= delta
	if _timer <= 0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	# Quando o player entra em contato, concede o escudo e remove o pickup
	if not body:
		return
	if body.has_method("give_shield"):
		body.give_shield()
		if pickup_sound:
			var p = AudioStreamPlayer2D.new()
			p.stream = pickup_sound
			p.global_position = global_position
			get_tree().current_scene.add_child(p)
			p.play()
			# schedule removal of the player so sound can play
			p.connect("finished", Callable(p, "queue_free"))
		queue_free()
 
