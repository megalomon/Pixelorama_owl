@tool
class_name TransparentChecker
extends ColorRect

const TRANSPARENT_CHECKER := preload("uid://c50kmfvf635kb")


func _init() -> void:
	material = ShaderMaterial.new()
	material.shader = TRANSPARENT_CHECKER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	resized.connect(_on_resized)


func _ready() -> void:
	update_rect()


func update_rect() -> void:
	if Engine.is_editor_hint():
		return
	if not get_parent() is Control:
		# Set the size to be the same as the project size if the parent is a SubViewport
		set_bounds(Global.current_project.size)
	if self == Global.transparent_checker:
		fit_rect(Global.current_project.tiles.get_bounding_rect())
		for canvas_preview in get_tree().get_nodes_in_group("CanvasPreviews"):
			canvas_preview.get_viewport().get_node("TransparentChecker").update_rect()
	material.set_shader_parameter(&"size", Global.checker_size)
	material.set_shader_parameter(&"color1", Global.checker_color_1)
	material.set_shader_parameter(&"color2", Global.checker_color_2)
	material.set_shader_parameter(&"follow_movement", Global.checker_follow_movement)
	material.set_shader_parameter(&"follow_scale", Global.checker_follow_scale)


func update_offset(offset: Vector2, canvas_scale: Vector2) -> void:
	material.set_shader_parameter(&"offset", offset)
	material.set_shader_parameter(&"scale", canvas_scale)


func _on_resized() -> void:
	material.set_shader_parameter(&"rect_size", size)


func set_bounds(bounds: Vector2) -> void:
	offset_right = bounds.x
	offset_bottom = bounds.y


func fit_rect(rect: Rect2) -> void:
	offset_left = rect.position.x
	offset_right = rect.position.x + rect.size.x
	offset_top = rect.position.y
	offset_bottom = rect.position.y + rect.size.y
