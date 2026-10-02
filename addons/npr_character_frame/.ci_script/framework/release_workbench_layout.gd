extends SceneTree
## 仅测真实 UI 布局；不冻结动态标签，不作为 Release 功能验收。

const SCENE = preload("res://addons/npr_character_frame/showcase/wardrobe.tscn")

var _host: Control
var _output: String
var _layout := {"viewport": [1440, 900], "globals": {}, "pages": {}}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_output = args[1] if args.size() > 1 else "res://.temp/release_workbench_layout"
	DirAccess.make_dir_recursive_absolute(_output)
	_run.call_deferred()


func _run() -> void:
	_host = SCENE.instantiate()
	root.add_child(_host)
	await create_timer(1.0).timeout
	if root.size != Vector2i(1440, 900):
		push_error("Layout requires a 1440x900 client")
		quit(1)
		return
	for widget in _host.find_children("*", "BaseButton", true, false):
		if (
			str(widget.name).begins_with("Section")
			or (
				str(widget.name)
				in [
					"Save",
					"Reset",
					"FaceView",
					"FullView",
					"HalfView",
					"ResetView",
					"DisplayRender",
					"DisplayWhite",
					"DisplaySkeleton"
				]
			)
		):
			_layout.globals[str(widget.name)] = _rect(widget.get_global_rect())
	for page in range(9):
		_host.select_section(page)
		await create_timer(0.4).timeout
		await _measure(str(page))
	_host.framework.set_diagnostic(1)
	await create_timer(0.4).timeout
	await _measure("8_diagnostic_1")
	FileAccess.open(_output.path_join("layout.json"), FileAccess.WRITE).store_string(
		JSON.stringify(_layout, "  ")
	)
	_host.queue_free()
	await process_frame
	print("RELEASE_LAYOUT_REGRESSION_OK")
	quit()


func _measure(key: String) -> void:
	var scroll: ScrollContainer = _host._options_scroll
	scroll.scroll_vertical = 0
	await process_frame
	var view := scroll.get_global_rect()
	var motion := InputEventMouseMotion.new()
	var wheel_point := Vector2(view.end.x - 3, view.get_center().y)
	motion.position = wheel_point
	motion.global_position = motion.position
	root.push_input(motion, true)
	var wheel := InputEventMouseButton.new()
	wheel.position = motion.position
	wheel.global_position = motion.position
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	root.push_input(wheel, true)
	await process_frame
	var step := scroll.scroll_vertical
	var maximum := maxf(0.0, scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page)
	if step <= 0 and maximum > 0:
		push_error("Real wheel input did not scroll page " + key)
		quit(1)
		return
	var controls := {}
	scroll.scroll_vertical = 0
	for count in ceili(maximum / maxi(step, 1)) + 1:
		if count > 0:
			root.push_input(wheel, true)
		await process_frame
		for widget: Control in _host._content.find_children("*", "Control", true, false):
			if not (widget is BaseButton or widget is HSlider):
				continue
			var rect := widget.get_global_rect()
			if not view.encloses(rect):
				continue
			var id := str(widget.name)
			if id.begins_with("@") and widget is BaseButton:
				id = "text:" + widget.text
			var score := absf(rect.get_center().y - view.get_center().y)
			if controls.has(id) and score >= controls[id].score:
				continue
			var entry := {"rect": _rect(rect), "wheel": count, "score": score}
			if widget is HSlider and widget.has_meta("debug_title"):
				var label: Control = widget.get_parent().get_parent().get_child(0)
				entry.label_rect = _rect(label.get_global_rect())
			if widget is BaseButton:
				entry.text = widget.text
			if widget is OptionButton:
				entry.items = []
				for index in widget.item_count:
					entry.items.append(widget.get_item_text(index))
			controls[id] = entry
	for id in controls:
		if not controls[id].has("items"):
			continue
		scroll.scroll_vertical = 0
		for count in controls[id].wheel:
			root.push_input(wheel, true)
			await process_frame
		await process_frame
		var picker: OptionButton = _host._content.find_child(id, true, false)
		# 布局探针直接打开真实菜单测位置；包内验证另走外部鼠标，不调用此方法。
		picker.show_popup()
		await create_timer(0.2).timeout
		var popup := picker.get_popup()
		if not popup.visible or not popup.is_embedded():
			var details := {
				"id": id,
				"visible": popup.visible,
				"embedded": popup.is_embedded(),
				"position": str(popup.position),
				"size": str(popup.size),
				"scroll": scroll.scroll_vertical,
				"root_embedded": root.gui_embed_subwindows
			}
			FileAccess.open(_output.path_join("popup_failure.json"), FileAccess.WRITE).store_string(
				JSON.stringify(details, "  ")
			)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(_output.path_join("popup_failure.png"))
			push_error("Expected an embedded visible menu: " + str(details))
			quit(1)
			return
		controls[id].popup = _rect(Rect2(popup.position, popup.size))
		popup.hide()
		motion.position = wheel_point
		motion.global_position = motion.position
		root.push_input(motion, true)
	_layout.pages[key] = {
		"controls": controls, "wheel_step": step, "scroll": _rect(view), "maximum": maximum
	}
	scroll.scroll_vertical = 0
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_output.path_join("page_" + key + ".png"))


func _rect(value: Rect2) -> Array:
	return [value.position.x, value.position.y, value.end.x, value.end.y]
