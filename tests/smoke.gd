extends SceneTree

const Game = preload("res://scripts/game.gd")
var failed := false

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func textured_mesh(mesh: ArrayMesh) -> bool:
	for i in range(mesh.get_surface_count()):
		var material := mesh.surface_get_material(i) as StandardMaterial3D
		if material and material.albedo_texture:
			var coords: PackedVector2Array = mesh.surface_get_arrays(i)[Mesh.ARRAY_TEX_UV]
			if not coords.is_empty():
				for uv in coords:
					if not uv.is_equal_approx(coords[0]):
						return true
	return false

func run() -> void:
	var game: Game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	for id in Game.MAPS:
		game.start_match(id, 1, 3, 0)
		await physics_frame
		await physics_frame
		var map_mesh: ArrayMesh = load("res://assets/maps/" + id + ".obj")
		expect(textured_mesh(map_mesh), id + " no tiene textura y UV funcionales")
		expect(textured_mesh(game.player.arms.mesh), "Los brazos o guantes no conservan la textura")
		var bot = game.fighters.back()
		expect(is_instance_valid(bot.rig) and bot.joints.has("bip01lthigh"), "No se importó el esqueleto del bot")
		expect(game.arena.nav_ready, id + " no pudo generar navegación")
		expect(game.fighters.size() == 6, "Plantel incorrecto")
		expect(game.phase == Game.Phase.BUY, "No se inició la fase de compra")
		game.show_shop()
		game.purchase(1)
		expect(game.player.weapon == 0 and game.wallet == 800, "Compra sin fondos aceptada")
		game.wallet = 3000
		game.purchase(1)
		expect(game.player.weapon == 1 and game.wallet == 300, "Compra de AK incorrecta")
		expect(textured_mesh(game.player.gun.mesh), "El arma equipada no recibió sus texturas")
		game.close_overlay()
		game.time_left = 0.0
		await process_frame
		await process_frame
		expect(game.phase == Game.Phase.LIVE, "La ronda no empezó")
		var target := game.fighters.back() as CharacterBody3D
		for frame in range(35):
			await physics_frame
		expect(target.is_on_floor(), "El bot no aterrizó en la colisión original")
		game.player.cooldown = 0.0
		var previous := game.player.rounds
		game.player.fire(-game.player.camera.global_transform.basis.z, 1.0)
		expect(game.player.rounds == previous - 1, "El disparo no consumió munición")
		var casing_count := 0
		for child in game.roster.get_children():
			if child is RigidBody3D:
				casing_count += 1
		expect(casing_count > 0, "El disparo no creó casquillo físico")
		if is_instance_valid(bot.rig) and bot.joints.has("bip01lthigh"):
			var thigh: int = bot.joints["bip01lthigh"]
			var rest: Quaternion = bot.rig.get_bone_rest(thigh).basis.get_rotation_quaternion()
			bot.movement_cycle = PI * 0.5
			bot.animate_bot(4.0)
			expect(not rest.is_equal_approx(bot.rig.get_bone_pose_rotation(thigh)), "La animación no movió el rig")
		for actor in game.fighters:
			if actor.team == 1:
				actor.hurt(100, game.player)
		await process_frame
		await process_frame
		expect(target.collision_layer == 0, "El bot eliminado sigue bloqueando disparos")
		expect(game.phase == Game.Phase.RESULT and game.scores[0] == 1, "No se anotó la victoria de CT")
		game.time_left = 0.0
		await process_frame
		await process_frame
		expect(game.round_index == 2 and game.player.weapon == 1, "No se conservó el arma en la siguiente ronda")
		game.show_menu()
		expect(game.fighters.is_empty(), "El menú dejó combatientes activos")
	game.start_match("lego", 1, 2, 0, true)
	game.show_shop()
	game.purchase_utility(2)
	expect(game.player.utility[2] == 1, "No se compró la granada de humo")
	game.close_overlay()
	game.time_left = 0.0
	await process_frame
	await process_frame
	game.throw_utility(game.player, 2, Vector3.FORWARD)
	var thrown := get_nodes_in_group("offline_utility")
	expect(thrown.size() == 1 and game.player.utility[2] == 0, "No se lanzó la granada")
	if thrown.size() == 1:
		thrown[0].call("detonate")
		var center: Vector3 = thrown[0].global_position + Vector3.UP
		expect(game.smoke_between(center - Vector3.RIGHT * 5, center + Vector3.RIGHT * 5), "El humo no obstruye a los bots")
	var victim = game.fighters.back()
	victim.hurt(100, game.player)
	expect(game.scores[0] == 1, "Deathmatch no registró la baja")
	victim.respawn_time = 0.0
	await process_frame
	await process_frame
	expect(victim.alive(), "Deathmatch no reaparició al bot")
	game.start_match("lego", 1, 2, 0, false, true)
	game.time_left = 0.0
	await process_frame
	await process_frame
	expect(is_instance_valid(game.objective), "Demolición no generó el objetivo")
	if is_instance_valid(game.objective):
		game.objective.carrier.global_position = game.objective.site
		game.objective.carrier.ready_to_fire = false
		game.objective.update(3.0)
		expect(game.objective.armed, "La C4 no se plantó")
		game.player.global_position = game.objective.site
		game.player.velocity = Vector3.ZERO
		Input.action_press("interact")
		expect(game.objective.update(5.0) == 0, "La C4 no se desactivó")
		Input.action_release("interact")
	game.free()
	call_deferred("quit", 1 if failed else 0)
