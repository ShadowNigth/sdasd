extends Node3D

const MODELS := ["w_eq_fraggrenade_combine", "w_eq_flashbang", "w_eq_smokegrenade_combine"]
const SOUNDS := ["explode3", "flashbang_explode1", "smoke_emit"]
var kind := 0
var source
var game
var velocity := Vector3.ZERO
var remaining := 1.45
var smoke := false
var visual: MeshInstance3D

func launch(match_game, fighter, index: int, direction: Vector3) -> void:
	game = match_game
	source = fighter
	kind = index
	global_position = fighter.eye() + direction * 0.18
	velocity = direction * 12.0 + Vector3.UP * 3.4
	visual = MeshInstance3D.new()
	visual.mesh = load("res://assets/models/" + MODELS[kind] + ".obj")
	var bounds := visual.mesh.get_aabb()
	visual.scale = Vector3.ONE * (0.18 / bounds.size.length())
	visual.position = -bounds.get_center() * visual.scale
	add_child(visual)

func _physics_process(delta: float) -> void:
	if not game.controls_enabled():
		return
	remaining -= delta
	if smoke:
		if remaining <= 0.0:
			queue_free()
		return
	if remaining <= 0.0:
		detonate()
		return
	velocity.y -= 15.0 * delta
	var destination := global_position + velocity * delta
	var hit: Dictionary = source.ray(global_position, destination, 1)
	if hit.is_empty():
		global_position = destination
	else:
		global_position = hit.position + hit.normal * 0.055
		velocity = velocity.bounce(hit.normal) * 0.48
	rotation.x += delta * 9.0

func detonate() -> void:
	visual.hide()
	var audio := AudioStreamPlayer3D.new()
	add_child(audio)
	audio.stream = load("res://assets/audio/" + SOUNDS[kind] + ".ogg")
	audio.unit_size = 10
	audio.play()
	if kind == 2:
		smoke = true
		remaining = 13.0
		for i in range(9):
			var cloud := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 1.35
			sphere.height = 2.7
			cloud.mesh = sphere
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color("86909a")
			cloud.material_override = mat
			cloud.position = Vector3(cos(i * TAU / 8.0) * 1.35, 0.8, sin(i * TAU / 8.0) * 1.35) if i < 8 else Vector3.UP
			add_child(cloud)
		return
	set_physics_process(false)
	for actor in game.fighters:
		if not actor.alive():
			continue
		var radius := 7.0 if kind == 0 else 14.0
		var distance: float = global_position.distance_to(actor.eye())
		if distance >= radius or not source.ray(global_position, actor.eye(), 1).is_empty():
			continue
		if kind == 0 and (actor.team != source.team or actor == source):
			actor.hurt(roundi(92.0 * (1.0 - distance / radius)), source)
		elif kind == 1:
			var facing: float = (-actor.global_transform.basis.z).dot((global_position - actor.eye()).normalized())
			actor.blind = maxf(actor.blind, (1.0 - distance / radius) * (3.4 if facing > 0.15 else 0.65))
	await audio.finished
	queue_free()
