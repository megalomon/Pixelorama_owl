extends Control

## Needed because it is not possible to detect if a native file dialog is open or not.
signal save_file_dialog_opened(opened: bool)

const SPLASH_DIALOG_SCENE_PATH := "res://src/UI/Dialogs/SplashDialog.tscn"

var opensprite_file_selected := false
var redone := false
var is_quitting_on_save := false
var is_writing_text := false
var changed_projects_on_quit: Array[Project]
var cursor_image := preload("res://assets/graphics/cursor.png")
var splash_dialog: AcceptDialog:
	get:
		if not is_instance_valid(splash_dialog):
			splash_dialog = load(SPLASH_DIALOG_SCENE_PATH).instantiate()
			add_child(splash_dialog)
		return splash_dialog
var _last_session_last_project := ""

@onready var top_menu_container := $MenuAndUI/TopMenuContainer as Panel
@onready var main_ui := $MenuAndUI/UI/DockableContainer as DockableContainer
## Dialog used to open images and project (.pxo) files.
@onready var open_sprite_dialog := $Dialogs/OpenSprite as FileDialog
## Dialog used to save project (.pxo) files.
@onready var save_sprite_dialog := $Dialogs/SaveSprite as FileDialog
@onready var tile_mode_offsets_dialog: ConfirmationDialog = $Dialogs/TileModeOffsetsDialog
@onready var quit_dialog: ConfirmationDialog = $Dialogs/QuitDialog
@onready var quit_and_save_dialog: ConfirmationDialog = $Dialogs/QuitAndSaveDialog
@onready var restore_session_confirmation_dialog := (
	$Dialogs/RestoreSessionConfirmationDialog as ConfirmationDialog
)
@onready var left_cursor: Sprite2D = $LeftCursor
@onready var right_cursor: Sprite2D = $RightCursor


func _init() -> void:
	Global.project_switched.connect(_project_switched)
	if not DirAccess.dir_exists_absolute(OpenSave.BACKUPS_DIRECTORY):
		DirAccess.make_dir_recursive_absolute(OpenSave.BACKUPS_DIRECTORY)
	Global.shrink = _get_auto_display_scale()
	Global.auto_content_scale_factor = _get_auto_display_scale()
	_handle_layout_files()
	Applinks.data_received.connect(_on_applinks_data_received)
	# Load dither matrix images.
	var dither_matrices_path := "user://dither_matrices"
	if DirAccess.dir_exists_absolute(dither_matrices_path):
		for file_name in DirAccess.get_files_at(dither_matrices_path):
			var file_path := dither_matrices_path.path_join(file_name)
			ShaderLoader.load_dither_matrix_from_file(file_path)


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)

	get_window().title = tr("untitled") + " - Pixelorama " + Global.current_version

	Global.current_project.layers.append(PixelLayer.new(Global.current_project))
	Global.current_project.frames.append(Global.current_project.new_empty_frame())

	Import.import_brushes(Global.path_join_array(Global.data_directories, "Brushes"))
	Import.import_patterns(Global.path_join_array(Global.data_directories, "Patterns"))

	quit_and_save_dialog.add_button("Exit without saving", false, "ExitWithoutSaving")
	_last_session_last_project = get_last_project_path()
	if OS.get_name() == "Android":
		var intent_data := Applinks.get_data()
		if not intent_data.is_empty():
			_on_applinks_data_received(intent_data)
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE_EXTRA):
		save_sprite_dialog.option_count = 0

	# Detect if Pixelorama crashed last time.
	if Global.session_crashed_last_time() and OpenSave.had_backups_on_startup:
		restore_session_confirmation_dialog.popup_centered_clamped()
	await get_tree().process_frame
	if Global.open_last_project:
		load_last_project(true)
	_setup_application_window_size()
	_show_splash_screen()
	Global.pixelorama_has_loaded = true
	Global.pixelorama_opened.emit()
	print("Time Pixelorama took to open: %sms" % Time.get_ticks_msec())


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"layer_visibility"):
		for selected_cel in Global.current_project.selected_cels:
			var layer := Global.current_project.layers[selected_cel[1]]
			layer.visible = not layer.visible
		Global.canvas.update_all_layers = true
		Global.canvas.queue_redraw()
	if event.is_action_pressed(&"layer_lock"):
		for selected_cel in Global.current_project.selected_cels:
			var layer := Global.current_project.layers[selected_cel[1]]
			layer.locked = not layer.locked
		Global.canvas.update_all_layers = true
		Global.canvas.queue_redraw()
	if is_writing_text and event is InputEventKey and is_instance_valid(Global.main_viewport):
		Global.main_viewport.get_child(0).push_input(event)
	left_cursor.position = get_global_mouse_position() + Vector2(-32, 32)
	right_cursor.position = get_global_mouse_position() + Vector2(32, 32)


func _project_switched() -> void:
	if Global.current_project.export_profile.directory_path != "":
		open_sprite_dialog.current_dir = Global.current_project.export_profile.directory_path
		save_sprite_dialog.current_dir = Global.current_project.export_profile.directory_path


# Taken from
# https://github.com/godotengine/godot/blob/master/editor/settings/editor_settings.cpp#L1801
func _get_auto_display_scale() -> float:
	return DisplayServer.screen_get_max_scale()


func _handle_layout_files() -> void:
	if not DirAccess.dir_exists_absolute(Global.LAYOUT_DIR):
		DirAccess.make_dir_absolute(Global.LAYOUT_DIR)
	var dir := DirAccess.open(Global.LAYOUT_DIR)
	var files := dir.get_files()
	if files.size() == 0:
		for layout in Global.default_layouts:
			var file_name := layout.resource_path.get_basename().get_file() + ".tres"
			var new_layout := layout.clone()
			new_layout.layout_reset_path = layout.resource_path
			ResourceSaver.save(new_layout, Global.LAYOUT_DIR.path_join(file_name))
		files = dir.get_files()
	for file in files:
		var layout := ResourceLoader.load(Global.LAYOUT_DIR.path_join(file))
		if layout is DockableLayout:
			if layout.layout_reset_path.is_empty():
				if file == "Default.tres":
					layout.layout_reset_path = Global.default_layouts[0].resource_path
				elif file == "Tallscreen.tres":
					layout.layout_reset_path = Global.default_layouts[1].resource_path
			Global.layouts.append(layout)
			# Save the layout every time it changes
			layout.save_on_change = true


func _setup_application_window_size() -> void:
	if DisplayServer.get_name() == "headless":
		return
	set_display_scale()
	if Global.font_size != theme.default_font_size:
		theme.default_font_size = Global.font_size
		theme.set_font_size("font_size", "HeaderSmall", Global.font_size + 2)
	set_mobile_fullscreen_safe_area()


func set_display_scale() -> void:
	var root := get_window()
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	# Set a minimum window size to prevent UI elements from collapsing on each other.
	root.min_size = Vector2(320, 200)
	root.content_scale_factor = Global.shrink
	set_custom_cursor()


func set_mobile_fullscreen_safe_area() -> void:
	await get_tree().process_frame
	var is_fullscreen := (
		(get_window().mode == Window.MODE_EXCLUSIVE_FULLSCREEN)
		or (get_window().mode == Window.MODE_FULLSCREEN)
	)
	var menu_and_ui: VBoxContainer = $MenuAndUI
	if is_fullscreen:
		var safe_area := DisplayServer.get_display_safe_area()
		menu_and_ui.set_anchors_preset(Control.PRESET_TOP_LEFT)
		var pos := safe_area.position / get_window().content_scale_factor
		menu_and_ui.position = pos
		menu_and_ui.size = (safe_area.size / get_window().content_scale_factor)
	else:
		menu_and_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_custom_cursor() -> void:
	if Global.native_cursors:
		return
	if Global.shrink == 1.0:
		Input.set_custom_mouse_cursor(cursor_image, Input.CURSOR_CROSS, Vector2(15, 15))
	else:
		var cursor_data := cursor_image.get_image()
		var cursor_size := cursor_data.get_size() * Global.shrink
		cursor_data.resize(cursor_size.x, cursor_size.y, Image.INTERPOLATE_NEAREST)
		var cursor_tex := ImageTexture.create_from_image(cursor_data)
		Input.set_custom_mouse_cursor(
			cursor_tex, Input.CURSOR_CROSS, Vector2(15, 15) * Global.shrink
		)


func _show_splash_screen() -> void:
	if not Global.config_cache.has_section_key("preferences", "startup"):
		Global.config_cache.set_value("preferences", "startup", true)

	if Global.config_cache.get_value("preferences", "startup"):
		# Wait for the window to adjust itself, so the popup is correctly centered
		await get_tree().process_frame

		splash_dialog.popup_centered_clamped()  # Splash screen
		modulate = Color(0.5, 0.5, 0.5)


func _on_applinks_data_received(uri: String) -> void:
	if uri.begins_with("lospec-palette://"):
		Palettes.import_lospec_palette(uri)
	elif uri.begins_with("content://"):
		var path = Applinks.get_file_from_content_uri(uri)
		if path:
			OpenSave.handle_loading_file(path)
	elif uri.begins_with("file://"):
		var path := uri.trim_prefix("file://")
		OpenSave.handle_loading_file(path)


func _notification(what: int) -> void:
	if not is_inside_tree():
		return
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			show_quit_dialog()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			var subwindows := get_window().get_embedded_subwindows()
			if subwindows.is_empty():
				show_quit_dialog()
			else:
				if subwindows[-1] == save_sprite_dialog:
					_on_save_sprite_canceled()
				subwindows[-1].hide()
		# If the mouse exits the window and another application has the focus,
		# pause the application
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			if Global.pause_when_unfocused:
				get_tree().paused = true
		NOTIFICATION_WM_MOUSE_EXIT:
			# Do not pause the application if the mouse leaves the main window
			# but there are child subwindows opened, because that makes them unresponsive.
			var window_count := DisplayServer.get_window_list().size()
			if not get_window().has_focus() and window_count == 1 and Global.pause_when_unfocused:
				get_tree().paused = true
		# Unpause it when the mouse enters the window or when it gains focus
		NOTIFICATION_WM_MOUSE_ENTER:
			get_tree().paused = false
		NOTIFICATION_APPLICATION_FOCUS_IN:
			get_tree().paused = false
			Tools.quick_assign_tool_revert(MOUSE_BUTTON_RIGHT)
			Tools.quick_assign_tool_revert(MOUSE_BUTTON_LEFT)


func get_last_project_path() -> String:
	# Check if any project was saved or opened last time
	if Global.config_cache.has_section_key("data", "last_project_path"):
		# Check if file still exists on disk
		return Global.config_cache.get_value("data", "last_project_path")
	return ""


func load_last_project(using_previous_session := false) -> void:
	# Check if any project was saved or opened last time
	var last_project_path := get_last_project_path()
	if using_previous_session:
		last_project_path = _last_session_last_project
	if not last_project_path.is_empty():
		load_recent_project_file(last_project_path)
		(func(): Global.cel_switched.emit()).call_deferred()


func load_recent_project_file(path: String) -> void:
	# Check if file still exists on disk
	if FileAccess.file_exists(path):  # If yes then load the file
		OpenSave.handle_loading_file(path)
	else:
		# If file doesn't exist on disk then warn user about this
		Global.popup_error("Cannot find project file.")


func _on_OpenSprite_files_selected(paths: PackedStringArray) -> void:
	# Wait for file dialog to close otherwise an "Attempting to make child window exclusive"
	# error will appear
	await get_tree().process_frame
	for path in paths:
		OpenSave.handle_loading_file(path, true)
	save_sprite_dialog.current_dir = paths[0].get_base_dir()


func show_save_dialog(project := Global.current_project) -> void:
	Global.dialog_open(true, true)
	save_sprite_dialog.current_file = project.name + ".pxo"
	save_sprite_dialog.popup_centered_clamped()
	save_file_dialog_opened.emit(true)


func _on_SaveSprite_file_selected(path: String) -> void:
	save_project(path)
	save_file_dialog_opened.emit(false)


func _on_save_sprite_canceled() -> void:
	save_file_dialog_opened.emit(false)
	is_quitting_on_save = false


func save_project(path: String) -> void:
	var project_to_save := Global.current_project
	if is_quitting_on_save:
		project_to_save = changed_projects_on_quit[0]
	var include_blended := false
	if save_sprite_dialog.get_selected_options().size() > 0:
		include_blended = save_sprite_dialog.get_selected_options()[
			save_sprite_dialog.get_option_name(0)
		]
	var success := OpenSave.save_pxo_file(path, false, include_blended, project_to_save)
	if success:
		open_sprite_dialog.current_dir = path.get_base_dir()
	if is_quitting_on_save:
		changed_projects_on_quit.pop_front()
		_save_on_quit_confirmation()


func _on_open_sprite_visibility_changed() -> void:
	if !opensprite_file_selected:
		_can_draw_true()


func _can_draw_true() -> void:
	Global.dialog_open(false)


func _on_restore_session_confirmation_dialog_confirmed() -> void:
	$MenuAndUI/TopMenuContainer.backup_dialog.popup()


func show_quit_dialog() -> void:
	changed_projects_on_quit = []
	for project in Global.projects:
		if project.has_changed:
			changed_projects_on_quit.append(project)

	if not quit_dialog.visible:
		if changed_projects_on_quit.size() == 0:
			if Global.quit_confirmation:
				quit_dialog.popup_centered_clamped()
			else:
				_quit()
		else:
			quit_and_save_dialog.dialog_text = (
				tr("Project %s has unsaved progress. How do you wish to proceed?")
				% changed_projects_on_quit[0].name
			)
			quit_and_save_dialog.popup_centered_clamped()

	Global.dialog_open(true)


func _save_on_quit_confirmation() -> void:
	if changed_projects_on_quit.size() == 0:
		_quit()
	else:
		quit_and_save_dialog.dialog_text = (
			tr("Project %s has unsaved progress. How do you wish to proceed?")
			% changed_projects_on_quit[0].name
		)
		quit_and_save_dialog.popup_centered_clamped()
		Global.dialog_open(true)


func _on_QuitDialog_confirmed() -> void:
	_quit()


func _on_QuitAndSaveDialog_custom_action(action: String) -> void:
	if action == "ExitWithoutSaving":
		changed_projects_on_quit.pop_front()
		_save_on_quit_confirmation()


func _on_QuitAndSaveDialog_confirmed() -> void:
	is_quitting_on_save = true
	show_save_dialog(changed_projects_on_quit[0])


func _quit() -> void:
	# Darken the UI to denote that the application is currently exiting
	# (it won't respond to user input in this state).
	modulate = Color(0.5, 0.5, 0.5)
	get_tree().quit()


func _exit_tree() -> void:
	Global.pixelorama_about_to_close.emit()
	for project in Global.projects:
		project.remove()
	if DisplayServer.get_name() == "headless":
		return
	Global.config_cache.set_value("window", "layout", Global.layouts.find(main_ui.layout))
	Global.config_cache.set_value("view_menu", "draw_grid", Global.draw_grid)
	Global.config_cache.set_value("view_menu", "draw_pixel_grid", Global.draw_pixel_grid)
	Global.config_cache.set_value("view_menu", "show_pixel_indices", Global.show_pixel_indices)
	Global.config_cache.set_value("view_menu", "show_rulers", Global.show_rulers)
	Global.config_cache.set_value("view_menu", "show_guides", Global.show_guides)
	Global.config_cache.set_value("view_menu", "show_mouse_guides", Global.show_mouse_guides)
	Global.config_cache.set_value("view_menu", "lock_guides", Global.lock_guides)
	Global.config_cache.set_value(
		"view_menu", "display_layer_effects", Global.display_layer_effects
	)
	Global.config_cache.set_value(
		"view_menu", "snap_to_rectangular_grid_boundary", Global.snap_to_rectangular_grid_boundary
	)
	Global.config_cache.set_value(
		"view_menu", "snap_to_rectangular_grid_center", Global.snap_to_rectangular_grid_center
	)
	Global.config_cache.set_value("view_menu", "snap_to_guides", Global.snap_to_guides)
	Global.config_cache.set_value(
		"view_menu", "snap_to_perspective_guides", Global.snap_to_perspective_guides
	)
	Global.config_cache.set_value("FileDialog", "favourite_paths", FileDialog.get_favorite_list())
	Global.config_cache.set_value("FileDialog", "recent_paths", FileDialog.get_recent_list())
	Global.config_cache.save(Global.CONFIG_PATH)
