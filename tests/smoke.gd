extends SceneTree

const Game = preload("res://scripts/game.gd")
var failed := false

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func run() -> void:
	var game: Game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	for id in Game.MAPS:
		game.start_match(id, 1, 3, 0)
		await physics_frame
		await physics_frame
		expect(game.arena.nav_ready, id + " no pudo generar navegación")
		expect(game.fighters.size() == 6, "Plantel incorrecto")
		expect(game.phase == Game.Phase.BUY, "No se inició la fase de compra")
		game.show_shop()
		game.purchase(1)
		expect(game.player.weapon == 0 and game.wallet == 800, "Compra sin fondos aceptada")
		game.wallet = 3000
		game.purchase(1)
		expect(game.player.weapon == 1 and game.wallet == 300, "Compra de AK incorrecta")
		game.close_overlay()
		game.time_left = 0.0
		await process_frame
		await process_frame
		expect(game.phase == Game.Phase.LIVE, "La ronda no empezó")
		var target := game.fighters.back() as CharacterBody3D
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
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
