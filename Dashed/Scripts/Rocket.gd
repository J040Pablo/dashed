extends Area2D

@export var speed: float = 140.0
@export var turn_speed: float = 6.0
@export var explode_distance: float = 24.0
@export var arm_time: float = 0.18
@export var explosion_scene: PackedScene
@export var damage: int = 50
@export var sprite_rotation_offset_deg: float = 90.0
@export var sprite_flip_h: bool = false

@export var debug_logs: bool = false

var target: Node2D = null
var _armed: bool = false
@onready var _sprite: Sprite2D = $Sprite2D

func set_target(t: Node2D) -> void:
	target = t
	if t and is_instance_valid(t):
		if debug_logs:
			print("Rocket: target set to", t, "at", t.global_position)
	else:
		if debug_logs:
			print("Rocket: target set to", t)

func _ready():
	# fallback explosion scene
	if not explosion_scene and ResourceLoader.exists("res://Dashed/Scenes/Explosion.tscn"):
		explosion_scene = load("res://Dashed/Scenes/Explosion.tscn")

	# start arming timer so the rocket doesn't explode immediately when spawned near a target
	_armed = false
	if arm_time > 0.0:
		# run timer deferred so ready/adding sequence is complete
		call_deferred("_start_arm_timer")
	else:
		_armed = true

	# apply sprite rotation offset if needed (art may point up)
	if _sprite:
		_sprite.rotation_degrees = sprite_rotation_offset_deg
		_sprite.flip_h = sprite_flip_h

func _start_arm_timer() -> void:
	await get_tree().create_timer(arm_time).timeout
	_armed = true
	if debug_logs:
		print("Rocket armed after", arm_time, "s")

func _physics_process(delta: float) -> void:
	if not target or not is_instance_valid(target):
		# fly forward without a target
		global_position += Vector2.RIGHT.rotated(rotation) * speed * delta
		return

	var to_target = (target.global_position - global_position)

	var dir = to_target.normalized()
	# smooth rotate toward target
	var desired_angle = dir.angle()
	var turn_factor = min(1.0, turn_speed * delta)
	rotation = lerp_angle(rotation, desired_angle, turn_factor)
	# move forward in the direction we're facing
	var forward = Vector2.RIGHT.rotated(rotation)
	global_position += forward * speed * delta

	# check proximity only if armed
	if _armed and to_target.length() <= explode_distance:
		explode()

	# also explode if overlapping a damageable body (safety check)
	# If we have a specific target, only explode on that target to avoid
	# accidentally detonating when touching other damageable bodies (e.g. the Player).
	# If there is no target (target == null), keep the old behavior and explode
	# on any damageable body overlap.
	if _armed:
		if target and is_instance_valid(target):
			for b in get_overlapping_bodies():
				if b == target:
					if debug_logs:
						print("Rocket: overlapping target, exploding")
					explode()
					break
		else:
			for b in get_overlapping_bodies():
				if b and b.has_method("take_damage"):
					if debug_logs:
						print("Rocket: overlapping damageable body, exploding")
					explode()
					break

func _on_body_entered(body: Node) -> void:
	# ignore collisions until armed to avoid instant explosion on spawn
	if not _armed:
		return
	# If we have a specific target, only explode when the target collides.
	# If no target is set, explode on any damageable body.
	if target and is_instance_valid(target):
		if body == target:
			explode()
	else:
		if body and body.has_method("take_damage"):
			explode()

func explode() -> void:
	# Defer the actual explosion/queue_free to avoid changing physics state during query flush
	call_deferred("_explode_deferred")


func _explode_deferred() -> void:
	if explosion_scene:
		var ex = explosion_scene.instantiate()
		ex.global_position = global_position
		if get_parent():
			get_parent().add_child(ex)
	else:
		# fallback: try to load and instantiate
		if ResourceLoader.exists("res://Dashed/Scenes/Explosion.tscn"):
			var ex2 = load("res://Dashed/Scenes/Explosion.tscn").instantiate()
			ex2.global_position = global_position
			if get_parent():
				get_parent().add_child(ex2)

	# direct damage fallback: if target still valid, apply direct damage
	if target and is_instance_valid(target) and target.has_method("take_damage"):
		target.take_damage(damage)

	queue_free()
