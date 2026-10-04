extends Panel

@onready var dockable_container: DockableContainer = $DockableContainer
@onready var main_canvas_container := find_child("Main Canvas") as Container
@onready var right_tool_options: ScrollContainer = $"DockableContainer/Right Tool Options"
@onready var tiles: TileSetPanel = $DockableContainer/Tiles
@onready var object_tree_3d: PanelContainer = $"DockableContainer/3D Object Tree"


func _ready() -> void:
	Global.cel_switched.connect(_on_cel_switched)
	Global.single_tool_mode_changed.connect(_on_single_tool_mode_changed)
	await Global.pixelorama_opened
	if Global.single_tool_mode:
		dockable_container.set_control_hidden.call_deferred(right_tool_options, true)
	dockable_container.set_control_hidden.call_deferred(tiles, true)
	dockable_container.set_control_hidden.call_deferred(object_tree_3d, true)


func _on_cel_switched() -> void:
	var cel := Global.current_project.get_current_cel()
	dockable_container.set_control_hidden(tiles, cel is not CelTileMap)
	dockable_container.set_control_hidden(object_tree_3d, cel is not Cel3D)


func _on_single_tool_mode_changed(mode: bool) -> void:
	dockable_container.set_control_hidden(right_tool_options, mode)
