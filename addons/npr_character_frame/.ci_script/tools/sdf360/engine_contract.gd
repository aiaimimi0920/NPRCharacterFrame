extends SceneTree
const SDF = preload("res://addons/npr_character_frame/shaders/face/sdf360/sdf_materials.gd")
var failures := []
var checks := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func texture(w: int, h: int) -> Texture2D:
	return ImageTexture.create_from_image(Image.create(w, h, false, Image.FORMAT_RGBA8))


func _init() -> void:
	var loaded = load(
		"res://addons/npr_character_frame/.ci_script/tools/sdf360/install_fixture.tres"
	)
	check(loaded != null, "generated definition loads")
	check(loaded.material_set is SDF, "generated material uses plugin script")
	check(loaded.material_set.face_sdf360 != null, "generated atlas bound")
	check(loaded.material_set.validate_optional().is_empty(), "generated inputs valid")
	var m := SDF.new()
	check(m.validate_optional().is_empty(), "null atlas optional valid")
	check(m.validate_source_materials().is_empty(), "null atlas source valid")
	m.face_sdf360 = texture(3168, 924)
	check(not m.validate_optional().is_empty(), "UV2 false rejected")
	m.sdf_on_uv2 = true
	check(m.validate_optional().is_empty(), "128 core valid")
	check(not m.validate_source_materials().is_empty(), "source materials rejected")
	check(not m.apply_optional_to([]), "source apply rejects")
	m.face_sdf360 = texture(6240, 1820)
	check(m.validate_optional().is_empty(), "256 core valid")
	m.face_sdf360 = texture(100, 100)
	check(not m.validate_optional().is_empty(), "nondivisible rejected")
	m.face_sdf360 = texture(96, 28)
	check(not m.validate_optional().is_empty(), "padding-only rejected")
	m.face_sdf360 = texture(240, 140)
	check(m.validate_optional().is_empty(), "rectangular valid")
	m.face_sdf360 = null
	check(m.validate_optional().is_empty(), "null reset valid")
	print("SDF_CONTRACT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
