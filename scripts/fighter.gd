extends CharacterBody3D

const Arsenal = preload("res://scripts/arsenal.gd")
const PLAYER_HEIGHT := 1.74
var game
var human := false
var team := 0
var callsign := ""
var health := 100
var weapon := 0
var rounds := 7
var reserve := 35
var cooldown := 0.0
var reloading := 0.0
var pitch := 0.0
var blind := 0.0
var respawn_time := 0.0
var utility: Array[int] = [0, 0, 0]
var camera: Camera3D
var visuals: MeshInstance3D
var view_weapon: Node3D
var sound
var agent: NavigationAgent3D
var crouched := false
var zoomed := false
var trigger := false
var magazine: Dictionary = {}
var owned: Array[int] = [0]
var target
var last_seen := Vector3.ZERO
var memory := 0.0
var next_think := 0.0
var reaction := 0.0
var strafe := 1.0
var route_age := 0.0
var patrol := Vector3.ZERO
var ready_to_fire := false
var sensor_visible := false

func setup(owner_game: Node3D, is_human: bool, side: int, label: String) -> void:
	game = owner_game
	human = is_human
	team = side
	callsign = label
	collision_layer = 2
	collision_mask = 1 if not human else 3
	floor_snap_length = 0.28
	var shape := CollisionShape3D.new()
	shape.name = "BodyShape"
	var capsule := CapsuleShape3D.new()
	capsule.height = PLAYER_HEIGHT
	capsule.radius = 0.32
	shape.shape = capsule
	shape.position.y = PLAYER_HEIGHT * 0.5
	add_child(shape)
	if human:
		camera = Camera3D.new()
		camera.fov = 80
		camera.near = 0.04
		camera.position.y = 1.58
		add_child(camera)
		camera.current = true
		view_weapon = Node3D.new()
		camera.add_child(view_weapon)
		sound = AudioStreamPlayer.new()
	else:
		visuals = MeshInstance3D.new()
		visuals.mesh = load("res://assets/models/" + ("ctm_idf" if team == 0 else "tm_leet_variantA") + ".obj")
		visuals.rotation_degrees.x = 90
		visuals.scale = Vector3.ONE * 2.45
		var tint := StandardMaterial3D.new()
		tint.albedo_color = Color("477fba") if team == 0 else Color("b16b3d")
		visuals.material_override = tint
		add_child(visuals)
		agent = NavigationAgent3D.new()
		agent.path_desired_distance = 0.48
		agent.target_desired_distance = 0.85
		add_child(agent)
		sound = AudioStreamPlayer3D.new()
		sound.position.y = 1.3
		sound.max_distance = 65
		sound.unit_size = 8
	add_child(sound)
	equip(0)

func equip(index: int) -> void:
	if not owned.has(index):
		return
	magazine[weapon] = Vector2i(rounds, reserve)
	weapon = index
	var w: Dictionary = Arsenal.WEAPONS[weapon]
	var ammo: Vector2i = magazine.get(weapon, Vector2i(w.mag, w.reserve))
	rounds = ammo.x
	reserve = ammo.y
	reloading = 0.0
	cooldown = maxf(cooldown, 0.2)
	zoomed = false
	if human:
		for part in view_weapon.get_children():
			view_weapon.remove_child(part)
			part.queue_free()
		var model := MeshInstance3D.new()
		model.mesh = load("res://assets/models/" + w.mesh + ".obj")
		model.rotation_degrees.x = 90
		model.position = Vector3(0.20, -0.17, -0.26 if weapon == 0 else -0.13)
		view_weapon.add_child(model)

func alive() -> bool:
	return health > 0

func eye() -> Vector3:
	return global_position + Vector3.UP * (1.0 if crouched else 1.58)

func hurt(amount: int, attacker: CharacterBody3D) -> void:
	if not alive():
		return
	health = maxi(0, health - amount)
	if not alive():
		collision_layer = 0
		if visuals:
			visuals.hide()
		if view_weapon:
			view_weapon.hide()
		game.report_kill(attacker, self)

func respawn(point: Vector3, facing: float) -> void:
	global_position = point
	rotation.y = facing
	velocity = Vector3.ZERO
	health = 100
	collision_layer = 2
	blind = 0.0
	pitch = 0.0
	crouched = false
	zoomed = false
	trigger = false
	magazine.clear()
	var w: Dictionary = Arsenal.WEAPONS[weapon]
	rounds = w.mag
	reserve = w.reserve
	cooldown = 0.4
	reloading = 0.0
	target = null
	memory = 0.0
	sensor_visible = false
	route_age = 0.0
	patrol = Vector3.ZERO
	if visuals:
		visuals.show()
	if camera:
		camera.position = Vector3.UP * 1.58
		camera.rotation = Vector3.ZERO
		view_weapon.show()

func _unhandled_input(event: InputEvent) -> void:
	if not human or not alive() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not game.controls_enabled():
		return
	if event is InputEventMouseMotion:
		var sensitivity: float = game.sensitivity * (0.38 if zoomed else 1.0)
		rotate_y(-event.relative.x * sensitivity)
		pitch = clampf(pitch - event.relative.y * sensitivity, -1.48, 1.48)
	elif event.is_action_pressed("fire"):
		trigger = true
	elif event.is_action_pressed("zoom") and (weapon == 2 or Arsenal.WEAPONS[weapon].get("scope", false)):
		zoomed = not zoomed
	elif event.is_action_pressed("frag"):
		game.throw_utility(self, 0, -camera.global_transform.basis.z)
	elif event.is_action_pressed("flash"):
		game.throw_utility(self, 1, -camera.global_transform.basis.z)
	elif event.is_action_pressed("smoke"):
		game.throw_utility(self, 2, -camera.global_transform.basis.z)
	elif event.is_action_pressed("reload"):
		start_reload()
	elif event.is_action_pressed("sidearm"):
		equip(0)
	elif event.is_action_pressed("primary"):
		equip(owned.back())

func start_reload() -> void:
	var w: Dictionary = Arsenal.WEAPONS[weapon]
	if rounds < w.mag and reserve > 0 and reloading <= 0.0:
		reloading = w.reload
		zoomed = false
		play("ak47_clipin")

func play(clip: String) -> void:
	sound.stream = load("res://assets/audio/" + clip + ".ogg")
	sound.play()

func fire(direction: Vector3, accuracy: float) -> void:
	if reloading > 0.0 or cooldown > 0.0:
		return
	if rounds <= 0:
		start_reload()
		return
	var w: Dictionary = Arsenal.WEAPONS[weapon]
	rounds -= 1
	cooldown = w.delay
	play(w.sound)
	var spread: float = w.spread * accuracy
	var damage_by_target := {}
	for pellet in range(w.get("pellets", 1)):
		var shot := (direction + Vector3(randfn(0.0, spread), randfn(0.0, spread), randfn(0.0, spread))).normalized()
		var origin := eye()
		var hit := ray(origin, origin + shot * (35.0 if w.has("pellets") else 150.0))
		if hit.is_empty():
			continue
		var enemy = hit.collider
		if enemy.has_method("hurt") and enemy.team != team:
			var head: bool = hit.position.y - enemy.global_position.y > (1.08 if enemy.crouched else 1.43)
			damage_by_target[enemy] = damage_by_target.get(enemy, 0) + int(w.damage * (2.7 if head else 1.0))
	if human:
		pitch = minf(1.47, pitch + (0.008 if weapon == 0 else 0.016))
		if not damage_by_target.is_empty():
			game.hit_flash = 0.15
	for enemy in damage_by_target:
		enemy.hurt(damage_by_target[enemy], self)

func ray(from: Vector3, to: Vector3, mask: int = 3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, [get_rid()])
	query.hit_back_faces = true
	return get_world_3d().direct_space_state.intersect_ray(query)

func _physics_process(delta: float) -> void:
	if not alive() or not game.controls_enabled():
		trigger = false
		return
	blind = maxf(0.0, blind - delta)
	cooldown = maxf(0.0, cooldown - delta)
	if reloading > 0.0:
		reloading -= delta
		if reloading <= 0.0:
			var needed := mini(Arsenal.WEAPONS[weapon].mag - rounds, reserve)
			rounds += needed
			reserve -= needed
	if not is_on_floor():
		velocity.y -= 19.0 * delta
	if human:
		player_move(delta)
	else:
		bot_move(delta)
	move_and_slide()
	if global_position.y < -60:
		hurt(100, self)

func player_move(delta: float) -> void:
	var shape: CollisionShape3D = $BodyShape
	var wants_crouch := Input.is_action_pressed("crouch")
	if crouched and not wants_crouch:
		wants_crouch = test_move(global_transform, Vector3.UP * 0.57)
	crouched = wants_crouch
	shape.shape.height = 1.17 if crouched else PLAYER_HEIGHT
	shape.position.y = shape.shape.height * 0.5
	var axis := Input.get_vector("left", "right", "forward", "back")
	var direction := transform.basis * Vector3(axis.x, 0, axis.y)
	var ladder: bool = game.arena.near_ladder(global_position + Vector3.UP * 0.55)
	var speed := 2.25 if crouched or Input.is_action_pressed("walk") else 5.35
	velocity.x = move_toward(velocity.x, direction.x * speed, delta * (34.0 if is_on_floor() else 10.0))
	velocity.z = move_toward(velocity.z, direction.z * speed, delta * (34.0 if is_on_floor() else 10.0))
	if ladder and not crouched:
		velocity.y = -axis.y * 3.75
	if Input.is_action_just_pressed("jump") and (is_on_floor() or ladder) and not crouched:
		velocity.y = 5.4
	camera.position.y = lerpf(camera.position.y, 1.0 if crouched else 1.58, minf(1.0, delta * 14.0))
	camera.rotation.x = pitch
	camera.fov = lerpf(camera.fov, 31.0 if zoomed else 80.0, minf(1.0, delta * 20.0))
	view_weapon.visible = not zoomed
	view_weapon.position.z = maxf(0.0, cooldown - 0.02) * 0.065
	view_weapon.rotation.x = -0.6 * clampf(reloading, 0.0, 1.0)
	if trigger or (Arsenal.WEAPONS[weapon].auto and Input.is_action_pressed("fire")):
		var motion := Vector2(velocity.x, velocity.z).length()
		fire(-camera.global_transform.basis.z, (0.35 if zoomed else 1.0) + motion * 0.32 + (0.0 if is_on_floor() else 2.0))
	trigger = false

func can_see(candidate) -> bool:
	var offset: Vector3 = candidate.eye() - eye()
	if offset.length_squared() > 3600.0:
		return false
	if offset.length_squared() > 36.0 and (-global_transform.basis.z).dot(offset.normalized()) < -0.1:
		return false
	return blind < 0.15 and not game.smoke_between(eye(), candidate.eye()) and ray(eye(), candidate.eye()).get("collider") == candidate

func bot_move(delta: float) -> void:
	next_think -= delta
	reaction -= delta
	memory -= delta
	route_age -= delta
	if next_think <= 0.0:
		next_think = randf_range(0.12, 0.23)
		var best = null
		var best_dist := INF
		for candidate in game.fighters:
			if not candidate.alive() or candidate.team == team:
				continue
			var distance: float = global_position.distance_squared_to(candidate.global_position)
			if distance < best_dist and can_see(candidate):
				best = candidate
				best_dist = distance
		sensor_visible = best != null
		if sensor_visible:
			if target != best or memory <= 0.0:
				reaction = [0.72, 0.43, 0.24][game.difficulty] + randf_range(0.0, 0.2)
			target = best
			last_seen = best.global_position
			memory = 3.1
			if randf() < 0.15:
				strafe *= -1.0
	ready_to_fire = sensor_visible and is_instance_valid(target) and target.alive()
	var direction := Vector3.ZERO
	if ready_to_fire:
		var offset: Vector3 = target.eye() - eye() - Vector3.UP * 0.22
		look_toward(offset, delta)
		var distance := offset.length()
		if distance > 16.0:
			direction = Vector3(offset.x, 0, offset.z).normalized() * 0.65
		elif cooldown > 0.025 or reloading > 0.0:
			direction = strafe_direction(offset.normalized())
		if reaction <= 0.0 and blind < 0.15 and (-global_transform.basis.z).dot(Vector3(offset.x, 0, offset.z).normalized()) > 0.94:
			var before := rounds
			fire(offset.normalized(), [4.8, 2.7, 1.55][game.difficulty])
			if weapon == 1 and rounds < before and rounds % 4 == 0:
				cooldown += randf_range(0.22, 0.43)
	else:
		if rounds <= 3:
			start_reload()
		if route_age <= 0.0:
			route_age = randf_range(0.65, 1.05)
			if patrol == Vector3.ZERO or global_position.distance_to(patrol) < 2.0 or agent.is_navigation_finished():
				patrol = game.patrol_point(team)
			agent.target_position = last_seen if memory > 0.0 else patrol
		if game.arena.nav_ready:
			var step := agent.get_next_path_position() - global_position
			step.y = 0
			if step.length() > 0.1:
				direction = step.normalized()
		else:
			var step := patrol - global_position
			step.y = 0
			direction = step.normalized()
		look_toward(direction, delta)
	velocity.x = move_toward(velocity.x, direction.x * 4.1, delta * 24.0)
	velocity.z = move_toward(velocity.z, direction.z * 4.1, delta * 24.0)

func look_toward(direction: Vector3, delta: float) -> void:
	if absf(direction.x) + absf(direction.z) > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(1.0, 9.0 * delta))

func strafe_direction(enemy_direction: Vector3) -> Vector3:
	var lateral := global_transform.basis.x * strafe
	if not ray(eye(), eye() + lateral * 1.35, 1).is_empty():
		strafe *= -1.0
		lateral *= -1.0
	if reloading > 0.0:
		# Prefer a nearby sidestep that breaks sight while the magazine is out.
		for sign_value in [1.0, -1.0]:
			var candidate: Vector3 = eye() + lateral * sign_value * 2.1
			if ray(eye(), candidate, 1).is_empty() and not ray(candidate, candidate + enemy_direction * 8.0, 1).is_empty():
				return lateral * sign_value * 0.85
	return lateral * 0.48
