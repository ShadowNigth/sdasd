extends Node3D

const Arena = preload("res://scripts/arena.gd")
const Fighter = preload("res://scripts/fighter.gd")
const Arsenal = preload("res://scripts/arsenal.gd")
const MAPS := ["2000", "lego"]
const TEAMS := ["CT", "T"]
const TARGET_SCORE := 8
const ROUND_DURATION := 105.0
const CT_NAMES := ["Atlas", "Delta", "Nexo", "Vértice", "Faro"]
const T_NAMES := ["Rook", "Eco", "Sombra", "Cobre", "Spectre"]
enum Phase { MENU, BUY, LIVE, RESULT, FINISHED }
var phase := Phase.MENU
var arena: Arena
var roster: Node3D
var fighters: Array[Fighter] = []
var player: Fighter
var difficulty := 1
var team_size := 4
var side := 0
var scores := [0, 0]
var wallet := 800
var kills := 0
var deaths := 0
var round_index := 0
var time_left := 0.0
var sensitivity := 0.0024
var paused := false
var shopping := false
var hit_flash := 0.0
var feed_time := 0.0
var match_text := ""
var spectating: Fighter
var hud: CanvasLayer
var match_bar: Label
var status_bar: Label
var feed: Label
var reticle: Label
var title_card: PanelContainer
var content: VBoxContainer
var shop_hint: Label
var map_choice: OptionButton
var diff_choice: OptionButton
var team_choice: OptionButton
var count_choice: OptionButton
var volume: HSlider
var mouse_slider: HSlider

func _ready() -> void:
	for entry in [["forward", KEY_W], ["back", KEY_S], ["left", KEY_A], ["right", KEY_D],
		["jump", KEY_SPACE], ["crouch", KEY_CTRL], ["walk", KEY_SHIFT], ["reload", KEY_R],
		["primary", KEY_1], ["sidearm", KEY_2], ["shop", KEY_B], ["pause", KEY_ESCAPE], ["score", KEY_TAB]]:
		bind_action(entry[0], entry[1], false)
	bind_action("fire", MOUSE_BUTTON_LEFT, true)
	bind_action("zoom", MOUSE_BUTTON_RIGHT, true)
	process_priority = -10
	setup_ui()
	show_menu()

func bind_action(action: String, code: int, mouse: bool) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	if mouse:
		var event := InputEventMouseButton.new()
		event.button_index = code as MouseButton
		InputMap.action_add_event(action, event)
	else:
		var event := InputEventKey.new()
		event.physical_keycode = code as Key
		InputMap.action_add_event(action, event)

func controls_enabled() -> bool:
	return phase == Phase.LIVE and not paused

func start_match(map_id: String, bot_level: int, size: int, chosen_side: int) -> void:
	clear_world()
	scores = [0, 0]
	wallet = 800
	kills = 0
	deaths = 0
	round_index = 0
	difficulty = bot_level
	team_size = size
	side = chosen_side
	paused = false
	arena = Arena.new()
	arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(arena)
	arena.build(map_id)
	new_round()

func clear_world() -> void:
	if is_instance_valid(arena):
		remove_child(arena)
		arena.queue_free()
	arena = null
	roster = null
	player = null
	spectating = null
	fighters.clear()

func new_round() -> void:
	var keep: Array[int] = [0]
	if is_instance_valid(player) and player.alive():
		keep = player.owned.duplicate()
	if is_instance_valid(roster):
		arena.remove_child(roster)
		roster.queue_free()
	fighters.clear()
	spectating = null
	roster = Node3D.new()
	arena.add_child(roster)
	round_index += 1
	wallet = mini(16000, wallet)
	feed.text = ""
	for squad in range(2):
		for index in range(team_size):
			var is_player := squad == side and index == 0
			var actor := Fighter.new()
			var call: String = "Vos" if is_player else (CT_NAMES if squad == 0 else T_NAMES)[index]
			roster.add_child(actor)
			actor.position = arena.start_position(squad, index)
			actor.rotation.y = arena.facing(squad, actor.position)
			actor.setup(self, is_player, squad, call)
			fighters.append(actor)
			if is_player:
				player = actor
				actor.owned = keep
				actor.equip(keep.back())
			else:
				if round_index > 1:
					actor.owned.append(2 if index == 2 and round_index > 2 else 1)
					actor.equip(actor.owned.back())
	phase = Phase.BUY
	time_left = 6.0
	match_text = "Preparación · B para comprar"
	close_overlay()

func patrol_point(team: int) -> Vector3:
	# Targets are picked from the furthest half of each team's baked walkable area.
	var enemy: Vector3 = arena.spawns[1 - team].pick_random()
	var ally: Vector3 = arena.spawns[team].pick_random()
	var desired := ally.lerp(enemy, randf_range(0.5, 1.0))
	desired += Vector3(randf_range(-11.0, 11.0), 0, randf_range(-9.0, 9.0))
	if arena.nav_ready:
		return NavigationServer3D.region_get_closest_point(arena.region.get_rid(), desired)
	return enemy

func report_kill(attacker: Fighter, victim: Fighter) -> void:
	if attacker == player and attacker != victim:
		kills += 1
		wallet = mini(16000, wallet + 300)
	if victim == player:
		deaths += 1
	feed.text = (attacker.callsign + "  ›  " + victim.callsign) if attacker != victim else victim.callsign + " quedó fuera"
	feed_time = 4.0

func finish_round(winner: int, reason: String) -> void:
	scores[winner] += 1
	wallet = mini(16000, wallet + (3250 if winner == side else 1900))
	phase = Phase.RESULT
	time_left = 3.25
	match_text = "%s gana · %s" % [TEAMS[winner], reason]

func _process(delta: float) -> void:
	if phase == Phase.MENU or phase == Phase.FINISHED or paused or shopping:
		return
	time_left -= delta
	if phase == Phase.BUY and time_left <= 0.0:
		phase = Phase.LIVE
		time_left = ROUND_DURATION
		match_text = ""
	elif phase == Phase.LIVE:
		var alive_counts := [0, 0]
		for actor in fighters:
			if actor.alive():
				alive_counts[actor.team] += 1
		if alive_counts[0] == 0:
			finish_round(1, "equipo eliminado")
		elif alive_counts[1] == 0:
			finish_round(0, "equipo eliminado")
		elif time_left <= 0.0:
			finish_round(0, "tiempo agotado")
	elif phase == Phase.RESULT and time_left <= 0.0:
		if scores.max() >= TARGET_SCORE:
			show_result()
			return
		new_round()
	if not player.alive():
		update_spectator(delta)
	hit_flash = maxf(0.0, hit_flash - delta)
	feed_time -= delta
	if feed_time <= 0.0:
		feed.text = ""
	update_hud()

func update_spectator(delta: float) -> void:
	if not is_instance_valid(spectating) or not spectating.alive():
		spectating = null
		for actor in fighters:
			if actor.team == side and actor.alive():
				spectating = actor
				break
	if not is_instance_valid(spectating):
		return
	var viewpoint := spectating.eye() + Vector3.UP * 0.27
	player.camera.global_position = player.camera.global_position.lerp(viewpoint, minf(1.0, delta * 14.0))
	player.camera.global_rotation = Vector3(0, spectating.rotation.y, 0)
	player.camera.fov = 80.0

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and phase not in [Phase.MENU, Phase.FINISHED]:
		if paused or shopping:
			close_overlay()
		else:
			show_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("shop") and phase == Phase.BUY and not paused:
		if shopping:
			close_overlay()
		else:
			show_shop()
		get_viewport().set_input_as_handled()

func setup_ui() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	match_bar = make_label(hud, 24, Color("dfecfa"))
	match_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	match_bar.offset_left = -375
	match_bar.offset_right = 375
	match_bar.offset_top = 23
	match_bar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_bar = make_label(hud, 25, Color("e4f2ff"))
	status_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	status_bar.offset_left = -430
	status_bar.offset_right = 430
	status_bar.offset_top = -72
	status_bar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feed = make_label(hud, 18, Color("e8ab67"))
	feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	feed.offset_left = -340
	feed.offset_right = -30
	feed.offset_top = 23
	feed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	reticle = make_label(hud, 24, Color("b7ffd0"))
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	reticle.offset_left = -25
	reticle.offset_right = 25
	reticle.offset_top = -19
	reticle.offset_bottom = 19
	reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reticle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_card = PanelContainer.new()
	hud.add_child(title_card)
	title_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	title_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	title_card.offset_left = -300
	title_card.offset_right = 300
	var background := StyleBoxFlat.new()
	background.bg_color = Color("121d2cf8")
	background.border_color = Color("598abd")
	background.border_width_top = 3
	background.set_corner_radius_all(10)
	background.content_margin_top = 25
	background.content_margin_bottom = 25
	background.content_margin_left = 30
	background.content_margin_right = 30
	title_card.add_theme_stylebox_override("panel", background)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	title_card.add_child(content)

func make_label(parent: Node, size: int, color: Color, text := "") -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("0b1018"))
	label.add_theme_constant_override("outline_size", 5)
	parent.add_child(label)
	return label

func panel(heading: String, caption: String) -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	title_card.show()
	reticle.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	make_label(content, 15, Color("6ad6c4"), caption)
	make_label(content, 29, Color("f3f7fc"), heading)

func button(text: String, action: Callable) -> Button:
	var entry := Button.new()
	entry.text = text
	entry.custom_minimum_size.y = 39
	entry.pressed.connect(action)
	content.add_child(entry)
	return entry

func option(caption: String, items: Array, selected: int) -> OptionButton:
	var row := HBoxContainer.new()
	content.add_child(row)
	var label := make_label(row, 17, Color("c1d2df"), caption)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var selection := OptionButton.new()
	selection.custom_minimum_size.x = 235
	for item in items:
		selection.add_item(item)
	selection.select(selected)
	row.add_child(selection)
	return selection

func show_menu() -> void:
	get_tree().paused = false
	paused = false
	shopping = false
	clear_world()
	phase = Phase.MENU
	match_bar.hide()
	status_bar.hide()
	feed.hide()
	panel("Strike Port Destruction", "SPD  /  PARTIDA LOCAL  /  GODOT")
	map_choice = option("Mapa", ["$2000$", "AWP Lego 2"], 0)
	diff_choice = option("Dificultad de bots", ["Recluta", "Veterano", "Experto"], difficulty)
	team_choice = option("Tu equipo", ["CT · Defensa", "T · Asalto"], side)
	count_choice = option("Jugadores por equipo", ["2 vs 2", "3 vs 3", "4 vs 4", "5 vs 5"], team_size - 2)
	button("Iniciar partida", func() -> void:
		start_match(MAPS[map_choice.selected], diff_choice.selected, count_choice.selected + 2, team_choice.selected))
	make_label(content, 14, Color("a0b6cb"), "WASD mover · ratón apuntar · R recargar · B comprar\nEspacio saltar · Ctrl agacharse · Shift caminar · Esc pausa")
	button("Salir", get_tree().quit)

func close_overlay() -> void:
	paused = false
	shopping = false
	get_tree().paused = false
	title_card.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	match_bar.show()
	status_bar.show()
	feed.show()
	update_hud()

func show_pause() -> void:
	paused = true
	get_tree().paused = true
	panel("Partida en pausa", "SPD  /  AJUSTES LOCALES")
	make_label(content, 16, Color("c1d2df"), "Sensibilidad del ratón")
	mouse_slider = HSlider.new()
	mouse_slider.min_value = 0.0005
	mouse_slider.max_value = 0.007
	mouse_slider.step = 0.0001
	mouse_slider.value = sensitivity
	mouse_slider.value_changed.connect(func(value: float) -> void: sensitivity = value)
	content.add_child(mouse_slider)
	make_label(content, 16, Color("c1d2df"), "Volumen general")
	volume = HSlider.new()
	volume.max_value = 1.0
	volume.step = 0.01
	volume.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	volume.value_changed.connect(func(value: float) -> void:
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, value))))
	content.add_child(volume)
	button("Continuar", close_overlay)
	button("Volver al menú", show_menu)

func show_shop() -> void:
	shopping = true
	panel("Compra de equipamiento", "SPD  /  PREPARACIÓN")
	shop_hint = make_label(content, 17, Color("e9bb78"), "$%d disponibles" % wallet)
	for index in range(1, Arsenal.WEAPONS.size()):
		var w: Dictionary = Arsenal.WEAPONS[index]
		var entry := button("%s · $%d" % [w.name, w.price], purchase.bind(index))
		if player.owned.has(index):
			entry.text = "%s · equipar" % w.name
	button("Volver a la ronda", close_overlay)

func purchase(index: int) -> void:
	if phase != Phase.BUY or not shopping or not player.alive():
		return
	var cost: int = Arsenal.WEAPONS[index].price
	if not player.owned.has(index):
		if wallet < cost:
			shop_hint.text = "Saldo insuficiente · $%d" % wallet
			return
		wallet -= cost
		player.owned.append(index)
	player.equip(index)
	shop_hint.text = "%s equipada · $%d" % [Arsenal.WEAPONS[index].name, wallet]

func show_result() -> void:
	phase = Phase.FINISHED
	panel("Victoria" if scores[side] > scores[1 - side] else "Derrota", "SPD  /  PARTIDA TERMINADA")
	make_label(content, 22, Color("c1d2df"), "CT %d  :  %d T   ·   Bajas %d / Muertes %d" % [scores[0], scores[1], kills, deaths])
	button("Volver al menú", show_menu)

func update_hud() -> void:
	var seconds := maxi(0, ceili(time_left))
	match_bar.text = "CT %02d    ·    %02d:%02d    ·    %02d T\n%s" % [scores[0], seconds / 60, seconds % 60, scores[1], match_text]
	var w: Dictionary = Arsenal.WEAPONS[player.weapon]
	if not player.alive():
		status_bar.text = "Espectador · " + (spectating.callsign if is_instance_valid(spectating) else "Esperando próxima ronda")
	else:
		status_bar.text = "♥ %03d      $%d      %s    %02d / %02d" % [player.health, wallet, w.name, player.rounds, player.reserve]
		if player.reloading > 0.0:
			status_bar.text += "  ·  Recargando"
	if Input.is_action_pressed("score"):
		match_bar.text += "\nRONDA %d   ·   BAJAS %d   ·   MUERTES %d" % [round_index, kills, deaths]
	reticle.visible = phase == Phase.LIVE and player.alive() and not paused
	reticle.text = "×" if hit_flash > 0.0 else ("⊕" if player.zoomed else "+")
