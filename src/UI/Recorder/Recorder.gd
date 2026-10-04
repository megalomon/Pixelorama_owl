class_name RecorderPanel
extends PanelContainer

enum CaptureMethod { ACTIONS, MOUSE_MOTION, SECONDS }

var capture_method := CaptureMethod.ACTIONS
var save_dir := ""
var chosen_dir := "":
	set(value):
		chosen_dir = value
		if chosen_dir.ends_with("/"):  # Remove end back-slashes if present
			chosen_dir[-1] = ""
var start_after_delay_seconds: int = 0
var action_interval: int = 1  ## Number of "do" actions after which a frame can be captured.
var mouse_displacement: int = 100  ## Mouse displacement after which a frame can be captured.
var seconds_interval: float = 1  ## Number of seconds after which a frame can be captured.
var scaling_enabled := true
var scale_percent := 100
var recorded_projects: Dictionary[Project, Recorder] = {}

var _path_dialog: FileDialog:
	get:
		if not is_instance_valid(_path_dialog):
			_path_dialog = FileDialog.new()
			_path_dialog.exclusive = false
			_path_dialog.popup_window = true
			_path_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
			_path_dialog.access = FileDialog.ACCESS_FILESYSTEM
			_path_dialog.use_native_dialog = Global.use_native_file_dialogs
			_path_dialog.add_to_group(&"FileDialogs")
			_path_dialog.dir_selected.connect(_on_path_dialog_dir_selected)
			add_child(_path_dialog)
		return _path_dialog

@onready var start_delay_slider: ValueSlider = %StartDelaySlider
# Interval options
@onready var capture_method_option: OptionButton = %CaptureMethodOption
@onready var capture_actions: ValueSlider = %CaptureActions
@onready var capture_mouse_distance: ValueSlider = %MouseDistance
@onready var capture_seconds: ValueSlider = %CaptureSconds
# Scaling
@onready var scale_output_checkbox: CheckBox = %ScaleOutputCheckbox
@onready var output_scale_container: HBoxContainer = %OutputScale
@onready var scale_value_slider: ValueSlider = %ScaleValueSlider
@onready var size_label := %SizePreviewLabel as Label
# Output
@onready var path_field := %Path as LineEdit
@onready var options_container := %OptionsContainer as VBoxContainer

# Panel elements
@onready var captured_label := %CapturedLabel as Label
@onready var start_button := %Start as Button
@onready var capture_timer: Timer = %CaptureTimer
@onready var options_dialog := $OptionsDialog as AcceptDialog


class Recorder:
	var project: Project
	var recorder_panel: RecorderPanel
	var actions_done := -1
	var frames_captured := 0
	var save_directory := ""
	var _last_mouse_position := Vector2i.MAX
	var _start_size := Vector2i.ZERO

	func _init(_project: Project, _recorder_panel: RecorderPanel) -> void:
		project = _project
		recorder_panel = _recorder_panel
		# Create a new directory based on time
		var time_dict := Time.get_time_dict_from_system()
		var folder := str(
			project.name, time_dict.hour, "_", time_dict.minute, "_", time_dict.second
		)
		var dir := DirAccess.open(recorder_panel.chosen_dir)
		save_directory = recorder_panel.chosen_dir.path_join(folder)
		dir.make_dir_recursive(save_directory)
		project.removed.connect(recorder_panel.finalize_recording.bind(project))
		update_settings()
		recorder_panel.captured_label.text = ""
		_start_size = project.size

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			# Needed so that the project won't be forever remained in memory because of bind().
			project.removed.disconnect(recorder_panel.finalize_recording)

	func update_settings():
		if project.undo_redo.version_changed.is_connected(capture_frame):
			project.undo_redo.version_changed.disconnect(capture_frame)
		if recorder_panel.capture_timer.timeout.is_connected(capture_frame):
			recorder_panel.capture_timer.timeout.disconnect(capture_frame)
		match recorder_panel.capture_method:
			RecorderPanel.CaptureMethod.ACTIONS:
				project.undo_redo.version_changed.connect(capture_frame)
			RecorderPanel.CaptureMethod.MOUSE_MOTION:
				# _input() won't work properly, so i use wait_time with a low value
				recorder_panel.capture_timer.wait_time = 0.05
				recorder_panel.capture_timer.timeout.connect(capture_frame)
				recorder_panel.capture_timer.start()
			RecorderPanel.CaptureMethod.SECONDS:
				recorder_panel.capture_timer.wait_time = recorder_panel.seconds_interval
				recorder_panel.capture_timer.timeout.connect(capture_frame)
				recorder_panel.capture_timer.start()

	func capture_frame() -> void:
		if Global.current_project != project:
			return
		if not recorder_panel.get_window():
			return
		if recorder_panel.options_dialog.visible:
			return
		match recorder_panel.capture_method:
			RecorderPanel.CaptureMethod.ACTIONS:
				actions_done += 1
				if actions_done % recorder_panel.action_interval != 0:
					return
			RecorderPanel.CaptureMethod.MOUSE_MOTION:
				var mouse_pos := recorder_panel.get_global_mouse_position()
				var disp := _last_mouse_position.distance_to(mouse_pos)
				if disp < recorder_panel.mouse_displacement:
					return
				_last_mouse_position = recorder_panel.get_global_mouse_position()
		var frame := project.frames[project.current_frame]
		var image := project.new_empty_image()
		DrawingAlgos.blend_layers(image, frame, Vector2i.ZERO, project)
		if image.get_size() != _start_size:  # Resize image if it is different than intended
			image.resize(_start_size.x, _start_size.y, Image.INTERPOLATE_NEAREST)
		if recorder_panel.scaling_enabled:
			@warning_ignore("integer_division")
			var resize := recorder_panel.scale_percent / 100
			var new_width := image.get_width() * resize
			var new_height := image.get_height() * resize
			image.resize(new_width, new_height, Image.INTERPOLATE_NEAREST)
		var save_file := str(project.name, "_", frames_captured, ".png")
		image.save_png(save_directory.path_join(save_file))
		frames_captured += 1
		recorder_panel.captured_label.text = str("Saved: ", frames_captured)


func _ready() -> void:
	capture_method_option.add_item("By Actions", CaptureMethod.ACTIONS)
	capture_method_option.add_item("By Mouse Motion", CaptureMethod.MOUSE_MOTION)
	capture_method_option.add_item("By Seconds", CaptureMethod.SECONDS)
	Global.project_switched.connect(_on_project_switched)
	# Make a recordings folder if there isn't one
	chosen_dir = Global.home_data_directory.path_join("Recordings")
	DirAccess.make_dir_recursive_absolute(chosen_dir)
	path_field.text = chosen_dir
	# Temp assignment (remove later)
	var config = Global.config_cache.get_value("RecorderPanel", "settings", {})
	set_config(config)
	update_config()


func initialize_recording() -> void:
	# disable some options that are not required during recording
	captured_label.visible = true
	captured_label.text = "Initializing"
	var group_nodes := get_tree().get_nodes_in_group("hidden during recording")
	if group_nodes:
		for child: Control in group_nodes:
			child.visible = false


func finalize_recording(project := Global.current_project) -> void:
	recorded_projects.erase(project)
	if project == Global.current_project:
		captured_label.visible = false
		if get_tree():
			var group_nodes := get_tree().get_nodes_in_group("hidden during recording")
			if group_nodes:
				for child: Control in group_nodes:
					child.visible = true
			update_config()


func _on_settings_pressed() -> void:
	options_dialog.popup_centered_clamped(options_dialog.size)


func _on_open_folder_pressed() -> void:
	OS.shell_open(path_field.text)


func _on_start_recording_toggled(button_pressed: bool) -> void:
	if button_pressed and captured_label.visible == false:
		initialize_recording()
		if start_after_delay_seconds > 0:
			await get_tree().create_timer(start_after_delay_seconds).timeout
		recorded_projects[Global.current_project] = Recorder.new(Global.current_project, self)
		Global.change_button_texturerect(start_button.get_child(0), "stop.png")
	else:
		if recorded_projects.has(Global.current_project):  # prevents reaching here during await
			finalize_recording()
			Global.change_button_texturerect(start_button.get_child(0), "start.png")


func _on_project_switched() -> void:
	if recorded_projects.has(Global.current_project):
		initialize_recording()
		start_button.set_pressed_no_signal(true)
		Global.change_button_texturerect(start_button.get_child(0), "stop.png")
		captured_label.text = str(
			"Saved: ", recorded_projects[Global.current_project].frames_captured
		)
	else:
		finalize_recording()
		start_button.set_pressed_no_signal(false)
		Global.change_button_texturerect(start_button.get_child(0), "start.png")


# Option Dialog methods & Signals


func save_config() -> void:
	Global.config_cache.set_value("RecorderPanel", "settings", get_config())


func get_config() -> Dictionary:
	return {
		"start_after_delay_seconds": start_after_delay_seconds,
		"capture_method": capture_method,
		"action_interval": action_interval,
		"mouse_displacement": mouse_displacement,
		"seconds_interval": seconds_interval,
		"scaling_enabled": scaling_enabled,
		"scale_percent": scale_percent,
	}


func set_config(config: Dictionary) -> void:
	start_after_delay_seconds = config.get("start_after_delay_seconds", start_after_delay_seconds)
	capture_method = config.get("capture_method", capture_method)
	action_interval = config.get("action_interval", action_interval)
	mouse_displacement = config.get("mouse_displacement", mouse_displacement)
	seconds_interval = config.get("seconds_interval", seconds_interval)
	scaling_enabled = config.get("scaling_enabled", scaling_enabled)
	scale_percent = config.get("scale_percent", scale_percent)


func update_config():
	start_delay_slider.set_value_no_signal(start_after_delay_seconds)
	capture_method_option.selected = capture_method_option.get_item_index(capture_method)
	capture_actions.set_value_no_signal(action_interval)
	capture_mouse_distance.set_value_no_signal(mouse_displacement)
	capture_seconds.set_value_no_signal(seconds_interval)

	scale_output_checkbox.set_pressed_no_signal(scaling_enabled)
	scale_value_slider.set_value_no_signal(scale_percent)
	var new_size: Vector2i = Global.current_project.size * (scale_percent / 100.0)
	size_label.text = str("(", new_size.x, "×", new_size.y, ")")

	capture_actions.visible = capture_method == CaptureMethod.ACTIONS
	capture_mouse_distance.visible = capture_method == CaptureMethod.MOUSE_MOTION
	capture_seconds.visible = capture_method == CaptureMethod.SECONDS
	output_scale_container.visible = scaling_enabled
	scale_value_slider.visible = scaling_enabled

	for recorder: Recorder in recorded_projects.values():
		recorder.update_settings()


func _on_options_dialog_visibility_changed() -> void:
	if visible:
		options_dialog.size.y = 0


func _on_start_delay_slider_value_changed(value: int) -> void:
	start_after_delay_seconds = value
	update_config()
	save_config()


func _on_capture_method_option_item_selected(index: int) -> void:
	capture_method = capture_method_option.get_item_id(index) as CaptureMethod
	update_config()
	save_config()


func _on_action_interval_value_changed(value: int) -> void:
	action_interval = value
	update_config()
	save_config()


func _on_mouse_distance_value_changed(value: int) -> void:
	mouse_displacement = value
	update_config()
	save_config()


func _on_seconds_interval_value_changed(value: float) -> void:
	seconds_interval = value
	update_config()
	save_config()


func _on_scale_output_checkbox_toggled(toggled_on: bool) -> void:
	scaling_enabled = toggled_on
	update_config()
	save_config()


func _on_output_scale_value_changed(value: int) -> void:
	scale_percent = value
	update_config()
	save_config()


func _on_Choose_pressed() -> void:
	_path_dialog.popup_centered_clamped()
	_path_dialog.current_dir = chosen_dir


func _on_path_dialog_dir_selected(dir: String) -> void:
	chosen_dir = dir
	path_field.text = chosen_dir
	start_button.disabled = false
