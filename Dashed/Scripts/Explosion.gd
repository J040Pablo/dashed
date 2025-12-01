extends Area2D

@export var damage: int = 50
@export var radius: float = 48.0
@export var lifetime: float = 0.3

func _ready() -> void:
	monitoring = true
	# ensure collision radius if a shape exists
	if has_node("CollisionShape2D"):
		var cs = get_node("CollisionShape2D")
		if cs.shape and cs.shape is CircleShape2D:
			cs.shape.radius = radius

	# wait one physics frame to ensure overlaps are detected
	await get_tree().process_frame
	_apply_damage()
	# schedule cleanup after lifetime
	# animate visual (if a Sprite2D is present) while waiting to free
	var sprite: Sprite2D = null
	if has_node("Sprite2D"):
		sprite = get_node("Sprite2D")
		# try to load the explosion texture at runtime if present
		var tex_path = "res://Dashed/Assets/Sprites/explosion.png"
		if not sprite.texture and ResourceLoader.exists(tex_path):
			sprite.texture = load(tex_path)
		# initial visual settings
		sprite.scale = Vector2(0.6, 0.6)
		sprite.modulate = Color(1,1,1,1)

	var elapsed = 0.0
	while elapsed < lifetime:
		# wait a short tick; the awaited signal does not return a delta value
		await get_tree().create_timer(0.016).timeout
		var dt = 0.016
		elapsed += dt
		var t = elapsed / lifetime
		if t > 1.0:
			t = 1.0
		# scale up and fade out
		if sprite:
			sprite.scale = Vector2(lerp(0.6, 1.3, t), lerp(0.6, 1.3, t))
			var a = lerp(1.0, 0.0, t)
			sprite.modulate = Color(1,1,1,a)

	# final cleanup
	queue_free()

func _apply_damage() -> void:
	for body in get_overlapping_bodies():
		if body and body.has_method("take_damage"):
			body.take_damage(damage)
	# optional: create a small visual effect here (left as exercise)
