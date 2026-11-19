extends Node3D

static func show_shot(parent: Node3D, origin: Vector3, end: Vector3, wall_hit: bool) -> void:
	var fx := Node3D.new()
	parent.add_child(fx)
	fx.global_position = origin
	var gap := end - origin
	if gap.length_squared() < 0.002:
		fx.queue_free()
		return
	var flash := OmniLight3D.new()
	flash.light_color = Color("ffc17d")
	flash.light_energy = 1.4
	flash.omni_range = 3.0
	fx.add_child(flash)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("ffd691")
	var streak := MeshInstance3D.new()
	var box := BoxMesh.new()
	var length := minf(3.0, gap.length() * 0.85)
	box.size = Vector3(0.013, 0.013, length)
	streak.mesh = box
	streak.material_override = material
	fx.add_child(streak)
	streak.global_position = origin + gap.normalized() * minf(length, gap.length() * 0.5)
	streak.look_at(end, Vector3.RIGHT if absf(gap.normalized().y) > 0.99 else Vector3.UP)
	var fade := fx.create_tween()
	fade.tween_property(flash, "light_energy", 0.0, 0.055)
	fade.tween_callback(streak.hide)
	if wall_hit:
		for i in range(4):
			var spark := MeshInstance3D.new()
			var dot := BoxMesh.new()
			dot.size = Vector3.ONE * randf_range(0.022, 0.043)
			spark.mesh = dot
			spark.material_override = material
			fx.add_child(spark)
			spark.global_position = end - gap.normalized() * 0.015
			var scatter := Vector3(randf_range(-0.3, 0.3), randf_range(0.05, 0.35), randf_range(-0.3, 0.3))
			fade.parallel().tween_property(spark, "global_position", spark.global_position + scatter - gap.normalized() * 0.26, 0.12)
	fade.tween_callback(fx.queue_free)
