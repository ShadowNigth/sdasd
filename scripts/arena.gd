extends Node3D

var spawns: Array = [[], []]
var region: NavigationRegion3D
var nav_ready := false
var ladders: Array[AABB] = []

func build(id: String) -> void:
	var path := "res://assets/maps/" + id
	var world := MeshInstance3D.new()
	world.mesh = load(path + ".obj")
	add_child(world)
	var collision := MeshInstance3D.new()
	collision.mesh = load(path + "_solid.obj")
	add_child(collision)
	collision.hide()
	collision.create_trimesh_collision()
	var body: StaticBody3D = collision.get_child(0)
	var shape: CollisionShape3D = body.get_child(0)
	shape.shape.backface_collision = true
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path + ".json"))
	for side in range(2):
		for p in data[["ct", "t"][side]]:
			spawns[side].append(Vector3(p[0], p[1], p[2]))
	for pair in data.get("ladders", []):
		var low := Vector3(pair[0][0], pair[0][1], pair[0][2])
		var high := Vector3(pair[1][0], pair[1][1], pair[1][2])
		ladders.append(AABB(low, high - low).grow(0.65))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("9bb8c9")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("dceaf5")
	env.environment.ambient_light_energy = 0.65
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -32, 0)
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	add_child(sun)
	region = NavigationRegion3D.new()
	var nav := NavigationMesh.new()
	nav.cell_size = 0.25
	nav.cell_height = 0.25
	nav.agent_radius = 0.4
	nav.agent_height = 1.65
	nav.agent_max_climb = 0.35
	nav.agent_max_slope = 45.0
	nav.filter_baking_aabb = world.mesh.get_aabb().grow(0.5)
	region.navigation_mesh = nav
	add_child(region)
	var source := NavigationMeshSourceGeometryData3D.new()
	source.add_mesh(collision.mesh, Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data(nav, source)
	region.navigation_mesh = nav
	nav_ready = nav.get_polygon_count() > 0

func start_position(side: int, index: int) -> Vector3:
	return spawns[side][index % spawns[side].size()] + Vector3.UP * 0.12

func facing(side: int, point: Vector3) -> float:
	var center := Vector3.ZERO
	for p in spawns[1 - side]:
		center += p
	center /= spawns[1 - side].size()
	return atan2(point.x - center.x, point.z - center.z)

func near_ladder(point: Vector3) -> bool:
	for bounds in ladders:
		if bounds.has_point(point):
			return true
	return false
