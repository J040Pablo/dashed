
extends Area2D

@export var lifetime: float = 20.0
@export var pickup_sound: AudioStream
@export var debug_logs: bool = false

var _timer: float = 0.0

func _ready():
	# Connection for 'body_entered' is declared in the scene file (`Scenes/Shield.tscn`).
	# No runtime connect here to avoid duplicate connections when the TSCN already defines it.
	# If you create Shield instances purely by code and need the connection, re-enable connecting here.
	_timer = lifetime

	# Ensure the pickup's Sprite2D has a safe visual scale (protect against very large textures)
	if has_node("Sprite2D"):
		var s = get_node("Sprite2D")
		if s and s.texture:
			var tex_size = s.texture.get_size()
			var vsize = get_viewport().get_visible_rect().size
			# desired visual size in pixels (clamped to 20% of min viewport)
			var desired_px = min(10.0, min(vsize.x, vsize.y) * 0.2)
			var sx = desired_px / max(1.0, tex_size.x)
			var sy = desired_px / max(1.0, tex_size.y)
			# apply small default cap to avoid extremely small scales
			s.scale = Vector2(sx, sy)
			if debug_logs:
				print("[DEBUG] Shield._ready applied safe scale:", s.scale, " tex_size=", tex_size)
	# Debug: log sprite (if any) on the Shield pickup itself when created
	if has_node("Sprite2D"):
		var s = get_node("Sprite2D")
		if s and s.texture:
			if debug_logs:
				print("[DEBUG] Shield pickup created: tex_size=", s.texture.get_size(), " scale=", s.scale)

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
