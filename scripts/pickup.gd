extends Node3D

const Arsenal = preload("res://scripts/arsenal.gd")
const WeaponAliases := {"rif_awp": "snip_awp", "rif_m4a4": "rif_m4a1"}
const GrenadeData := {"eq_hegrenade": [0, "w_eq_fraggrenade_combine"], "eq_flashbang": [1, "w_eq_flashbang"]}
var game
var weapon := -1
var utility := -1
var visual: Node3D
var check_delay := 0.0

func setup(game_node: Node3D, original_name: String, point: Vector3) -> void:
	game = game_node
	global_position = point
	var mesh_name := ""
	if GrenadeData.has(original_name):
		utility = GrenadeData[original_name][0]
		mesh_name = GrenadeData[original_name][1]
	else:
		var search: String = "w_" + WeaponAliases.get(original_name, original_name)
		for index in range(Arsenal.KNIFE):
			if Arsenal.WEAPONS[index].mesh == search:
				weapon = index
				mesh_name = search
				break
	if mesh_name.is_empty():
		queue_free()
		return
	visual = Node3D.new()
	add_child(visual)
	var model := MeshInstance3D.new()
	model.mesh = load("res://assets/models/" + mesh_name + ".obj")
	var bounds := model.mesh.get_aabb()
	model.scale = Vector3.ONE * ((0.56 if utility < 0 else 0.21) / bounds.size.length())
	model.position = -bounds.get_center() * model.scale
	model.rotation_degrees.x = 90
	model.position = Basis(Vector3.RIGHT, PI * 0.5) * model.position
	visual.add_child(model)
	check_delay = randf_range(0.0, 0.15)

func _process(delta: float) -> void:
	if not game.controls_enabled():
		return
	visual.rotation.y += delta * 1.8
	check_delay -= delta
	if check_delay > 0.0:
		return
	check_delay = 0.17
	for actor in game.fighters:
		if not actor.alive() or actor.global_position.distance_squared_to(global_position) > 1.45:
			continue
		if utility >= 0:
			if actor.utility[utility] == 0:
				actor.utility[utility] = 1
				queue_free()
				return
		elif not actor.owned.has(weapon) and (actor.human or actor.owned.size() == 1):
			actor.owned.append(weapon)
			actor.equip(weapon)
			queue_free()
			return
