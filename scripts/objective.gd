extends Node3D

const ObjectiveTime := 38.0
const Radius := 2.25
var match_game
var carrier
var operator
var progress := 0.0
var remaining := 0.0
var armed := false
var marker: Label3D
var site := Vector3.ZERO
var device: MeshInstance3D

func setup(game, node: Node3D, map_id: String) -> void:
	match_game = game
	# These are offline sites placed on the recovered arenas, not Unity triggers.
	var proposed := Vector3(17, -4.6, 13.5) if map_id == "2000" else Vector3(0.5, -8.0, 11.0)
	site = NavigationServer3D.map_get_closest_point(node.get_world_3d().navigation_map, proposed)
	if site == Vector3.ZERO or site.distance_to(proposed) > 8.0:
		site = proposed
	global_position = site
	for fighter in game.fighters:
		if fighter.team == 1:
			carrier = fighter
			break
	marker = Label3D.new()
	marker.position.y = 2.25
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.modulate = Color("ffd06c")
	marker.font_size = 48
	marker.outline_size = 12
	marker.text = "A"
	add_child(marker)
	var circle := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = Radius
	cylinder.bottom_radius = Radius
	cylinder.height = 0.018
	circle.mesh = cylinder
	var floor_mark := StandardMaterial3D.new()
	floor_mark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	floor_mark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mark.albedo_color = Color(1.0, 0.72, 0.24, 0.19)
	circle.material_override = floor_mark
	circle.position.y = 0.06
	add_child(circle)
	device = MeshInstance3D.new()
	device.mesh = load("res://assets/models/w_ied_w_eq_c4.obj")
	var bounds := device.mesh.get_aabb()
	device.scale = Vector3.ONE * (0.44 / bounds.size.length())
	device.position = Vector3.UP * 0.19 - bounds.get_center() * device.scale
	device.hide()
	add_child(device)

func near_site(actor) -> bool:
	return actor.global_position.distance_squared_to(site) < Radius * Radius

func eligible(actor) -> bool:
	return (actor.team == 0 if armed else actor == carrier) and near_site(actor) and actor.alive()

func update(delta: float) -> int:
	if armed:
		remaining -= delta
		if remaining <= 0.0:
			return 1
	elif not is_instance_valid(carrier) or not carrier.alive():
		carrier = null
		for fighter in match_game.fighters:
			if fighter.alive() and fighter.team == 1:
				carrier = fighter
				break
	var active = null
	for actor in match_game.fighters:
		if eligible(actor):
			if actor.human and Input.is_action_pressed("interact") and actor.velocity.length_squared() < 0.64:
				active = actor
				break
			if not actor.human and not actor.ready_to_fire and active == null:
				active = actor
	if active != operator or active == null:
		progress = 0.0
	operator = active
	if active == null:
		return -1
	progress += delta
	if armed and progress >= 4.5:
		return 0
	if not armed and progress >= 2.8:
		armed = true
		remaining = ObjectiveTime
		progress = 0.0
		operator = null
		marker.text = "A · C4"
		marker.modulate = Color("ff7c59")
		device.show()
	return -1

func status(player) -> String:
	var label := "C4 activa en A · %ds" % ceili(remaining) if armed else "Objetivo A · %s" % ("Llevás la C4" if carrier == player else "CT defiende · T planta")
	if player.alive() and eligible(player):
		label += " · Mantener E para " + ("desactivar" if armed else "plantar")
	if is_instance_valid(operator):
		label += " · %d%%" % mini(100, roundi(100.0 * progress / (4.5 if armed else 2.8)))
	return label
