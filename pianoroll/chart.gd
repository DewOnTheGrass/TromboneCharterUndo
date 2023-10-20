extends Control

const scrollbar_height : float = 8
var scroll_position : float:
	get: return %ChartView.scroll_horizontal
var scroll_end : float:
	get: return scroll_position + %ChartView.size.x
var bar_spacing : float = 1.0
#	get: return tmb.savednotespacing * %ZoomLevel.value
var middle_c_y : float:
	get: return (key_height * 13.0) + (key_height / 2.0)
var key_height : float:
	get: return (size.y + scrollbar_height) / Global.NUM_KEYS
var current_subdiv : float:
	get: return 1.0 / %TimingSnap.value
var note_scn = preload("res://note/note.tscn")
var settings : Settings:
	get: return Global.settings
var bar_font : Font
var draw_targets : bool:
	get: return %ShowMouseTargets.button_pressed
var doot_enabled : bool = true
var _update_queued := false
var clearing_notes := false
func height_to_pitch(height:float):
	return ((height - middle_c_y) / key_height) * Global.SEMITONE
func pitch_to_height(pitch:float):
	return middle_c_y - ((pitch / Global.SEMITONE) * key_height)
func x_to_bar(x:float): return x / bar_spacing
func bar_to_x(bar:float): return bar * bar_spacing
@onready var main = get_tree().get_current_scene()
@onready var player : AudioStreamPlayer = %TrombPlayer
@onready var measure_font : Font = ThemeDB.get_fallback_font()
@onready var tmb : TMBInfo:
	get: return Global.working_tmb

###Dew's variables###
var new_array := []
var target_note := []
var dumb_copy := []
var bar_array := [] #list of bars
var drag_available := false
var short_stack = 0
var prev_bar #bar of clearable note
var reappearing_note = false
###

func doot(pitch:float):
	if !doot_enabled || %PreviewController.is_playing: return
	player.pitch_scale = Global.pitch_to_scale(pitch / Global.SEMITONE)
	player.play()
	await(get_tree().create_timer(0.1).timeout)
	player.stop()


func _ready():
	
	bar_font = measure_font.duplicate()
	main.chart_loaded.connect(_on_tmb_loaded)
	Global.tmb_updated.connect(_on_tmb_updated)
	%TimingSnap.value_changed.connect(timing_snap_changed)


func _process(_delta):
	if _update_queued: _do_tmb_update()
	if %PreviewController.is_playing: queue_redraw()


func _on_scroll_change():
	await(get_tree().process_frame)
	queue_redraw()
	redraw_notes()
	%WavePreview.calculate_width()

#Dew: Please come back from _exit_tree after removing child note from chart! I added a condition there and everything...
func filicide(child):
	Global.please_come_back = true
	%Chart.remove_child(child)
	Global.please_come_back = false
###

#Dew undo/redo-input handler
func _unhandled_key_input(event):
	var shift = event as InputEventWithModifiers
	if !shift.shift_pressed && Input.is_action_just_pressed("ui_undo") && Global.revision > 0:
		short_stack = Global.a_array.size() + Global.initial_size - Global.main_stack.size()
		Global.UR[0] = 1
		print("undo!")
		update_note_array()
	if Input.is_action_just_pressed("ui_redo") && Global.UR[2] > 0:
		Global.UR[0] = 2
		Global.UR[1] = 2
		short_stack = Global.a_array.size() + Global.initial_size - Global.main_stack.size()
		print("redo!")
		if short_stack == 1 :
			Global.UR[1] = 1
		update_note_array()
###

func redraw_notes():
	for child in get_children():
		if !(child is Note): continue
		if child.is_in_view:
			child.show()
			child.queue_redraw()
		else: child.hide()


func _on_tmb_updated():
	bar_spacing = tmb.savednotespacing * %ZoomLevel.value
	_update_queued = true

func _do_tmb_update():
	custom_minimum_size.x = (tmb.endpoint + 1) * bar_spacing
	%SectionStart.max_value = tmb.endpoint - 1
	%SectionLength.max_value = max(1, tmb.endpoint - %SectionStart.value)
	%CopyTarget.max_value = tmb.endpoint - 1
	%LyricBar.max_value = tmb.endpoint - 1
	%LyricsEditor._update_lyrics()
	%Settings._update_handles()
	for note in get_children():
		if !(note is Note) || note.is_queued_for_deletion():
			continue
		note.position.x = note.bar * bar_spacing
	queue_redraw()
	redraw_notes()
	_update_queued = false


func to_snapped(pos:Vector2):
	var new_bar = x_to_bar( pos.x )
	var timing_snap = 1.0 / settings.timing_snap
	var pitch = -height_to_pitch( pos.y )
	var pitch_snap = Global.SEMITONE / settings.pitch_snap
	return Vector2(
		clamp(
			snapped( new_bar, timing_snap ),
			0, tmb.endpoint
			),
		clamp(
			snapped( pitch, pitch_snap, ),
			Global.SEMITONE * -13, Global.SEMITONE * 13
			)
		)
func to_unsnapped(pos:Vector2):
	return Vector2(
		x_to_bar(pos.x),
		-height_to_pitch(pos.y)
	)


func timing_snap_changed(_value:float): queue_redraw()


func _on_tmb_loaded():
	var children := get_children()
	clearing_notes = true
	for i in children.size():
		var child = children[-(i + 1)]
		if child is Note: child.queue_free()
	await(get_tree().process_frame)
	clearing_notes = false
	
	doot_enabled = false
	for note in tmb.notes:
		add_note(false,
				note[TMBInfo.NOTE_BAR],
				note[TMBInfo.NOTE_LENGTH],
				note[TMBInfo.NOTE_PITCH_START],
				note[TMBInfo.NOTE_PITCH_DELTA]
		)
	doot_enabled = %DootToggle.button_pressed
	_on_tmb_updated()


func add_note(start_drag:bool, bar:float, length:float, pitch:float, pitch_delta:float = 0.0):
	
	#Dew remove overwritten future undo/redo chain
	if Global.UR[2] > 0 && reappearing_note == false :
		Global.history = Global.history.slice(0,Global.revision,1,true)
		Global.a_array = Global.a_array.slice(0,Global.revision,1,true)
		Global.d_array = Global.d_array.slice(0,Global.revision,1,true)
	###
	var new_note : Note = note_scn.instantiate()
	new_note.bar = bar
	new_note.length = length
	new_note.pitch_start = pitch
	new_note.pitch_delta = pitch_delta
	new_note.position.x = bar_to_x(bar)
	new_note.position.y = pitch_to_height(pitch)
	new_note.dragging = Note.DRAG_INITIAL if start_drag else Note.DRAG_NONE
	
	if doot_enabled: doot(pitch)
	add_child(new_note)
	#new_note.grab_focus()
	if reappearing_note == true: return

# !! unused
func stepped_note_overlaps(time:float, length:float, exclude : Array = []) -> bool:
	var steps : int = ceil(length) * 8
	var step_length : float = length / steps
	for step in steps + 1:
		var step_time = step_length * step
		if Global.overlaps_any_note(time + step_time, exclude): return true
	return false

# move to ???
func continuous_note_overlaps(time:float, length:float, exclude : Array = []) -> bool:
	var is_in_range := func(value: float, range_start:float, range_end:float):
		return value > range_start && value < range_end
	
	for note in Global.working_tmb.notes:
		var bar = note[TMBInfo.NOTE_BAR]
		var end = note[TMBInfo.NOTE_BAR] + note[TMBInfo.NOTE_LENGTH]
		if bar in exclude: continue
		for value in [bar, end]:
			if is_in_range.call(value,time,time+length): return true
		# we need to test the middle of the note so that notes of the same length
		# don't think it's fine if they start and end at the same time
		for value in [time, time + length, time + (length / 2.0)]:
			if is_in_range.call(value,bar,end): return true
	
	return false


func update_note_array():
	new_array = []
	print("Hi, I'm Tom Scott, and today I'm here in func update_note_array()")
	for note in get_children():
		
		#Dew add check for undo/redo
		if !(note is Note) || note.is_queued_for_deletion() || (Global.UR[0] > 0):
		###
			
			continue
		var note_array := [
			note.bar, note.length, note.pitch_start, note.pitch_delta,
			note.pitch_start + note.pitch_delta
		]
		print(note_array)
		new_array.append(note_array)
	#Dew debug and list of note starts with changes(bar_array) 
		#bar_array.append(note_array[0])
		#bar_array.sort()
		bar_array = [note_array[0]]
		Global.main_stack = new_array
	if false:
		print("Notes Dictionary: ", Global.history)
		print(Global.revision)
		var da_note = Global.relevant_notes.find_key(bar_array[0])
		print(da_note)
		print("da_note type: ",typeof(da_note))
		print("%Chart type: ",typeof(%Chart))
		print(%Chart.get_children())
		filicide(da_note)
		print("bar_array: ",bar_array)
		print(%Chart.get_children())
	
	###
	
	new_array.sort_custom(func(a,b): return a[TMBInfo.NOTE_BAR] < b[TMBInfo.NOTE_BAR])
	tmb.notes = new_array
	
	#Dew direct to undo/redo
	print("tmb.notes: ",tmb.notes)
	
	if Global.UR[0] > 0 :
		UR_handler()
	else :
		_do_tmb_update()
	###
	
#Dew's closest he will ever get to yandev levels of if/then incompetence
#Also Dew's undo/redo handler.
func UR_handler():
	print("UR!!! ",Global.UR[0])
	print("pre-history: ",Global.history)
	var passed_note = []
	var drag_UR = false
	var old_note : Note
	if Global.UR[0] == 1 :
		print("UR Undo! ")
		if Global.revision > 1:
			if Global.a_array[Global.revision-2] == Global.respects :
				print("undo dragged")
				passed_note = Global.d_array[Global.revision-2]
				Global.main_stack.remove_at(Global.main_stack.bsearch(Global.a_array[Global.revision-1]))
				filicide(Global.history[Global.revision-1])
				Global.main_stack.append(passed_note)
				
				reappearing_note = true
				add_note(false, passed_note[0], passed_note[1], passed_note[2], passed_note[3])
				reappearing_note = false
				
				Global.revision -= 2
				Global.UR[0] = 0
				Global.UR[2] += 1
				drag_UR = true
		if !drag_UR :
			if Global.d_array[Global.revision-1] == Global.ratio:
				print("undo added")
				Global.main_stack.remove_at(Global.main_stack.bsearch(Global.a_array[Global.revision-1]))
				filicide(Global.history[Global.revision-1])
				Global.revision -= 1
				Global.UR[0] = 0
				Global.UR[2] += 1
			
			elif Global.a_array[Global.revision-1] == Global.ratio:
				print("undo deleted")
				passed_note = Global.d_array[Global.revision-1]
				
				reappearing_note = true
				add_note(false, passed_note[0], passed_note[1], passed_note[2], passed_note[3])
				reappearing_note = false
				
				Global.revision -= 1
				Global.UR[0] = 0
				Global.UR[2] += 1
		dumb_copy = Global.main_stack
		dumb_copy.sort_custom(func(a,b): return a[TMBInfo.NOTE_BAR] < b[TMBInfo.NOTE_BAR])
		tmb.notes = dumb_copy
		
	if Global.UR[0] == 2 :
		print("UR Redo! ",Global.UR[1])
		if Global.UR[1] == 2 :
			if Global.a_array[Global.revision] == Global.respects :
				print("redo dragged")
				passed_note = Global.a_array[Global.revision+1]
				Global.main_stack.remove_at(Global.main_stack.bsearch(Global.d_array[Global.revision]))
				filicide(Global.history[Global.revision])
				Global.main_stack.append(passed_note)
				
				reappearing_note = true
				add_note(false, passed_note[0], passed_note[1], passed_note[2], passed_note[3])
				reappearing_note = false
				
				Global.revision += 2
				Global.UR[2] -= 1
				drag_UR = true
			
		if Global.UR[1] != 0 && !drag_UR :
			if Global.d_array[Global.revision] == Global.ratio :
				print("redo added")
				passed_note = Global.a_array[Global.revision]
				Global.main_stack.append(passed_note)
				
				reappearing_note = true
				add_note(false, passed_note[0], passed_note[1], passed_note[2], passed_note[3])
				reappearing_note = false
				
				Global.revision += 1
				Global.UR[2] -= 1
		
			elif Global.a_array[Global.revision] == Global.ratio :
				print("redo deleted")
				
				Global.main_stack.remove_at(Global.main_stack.bsearch(Global.d_array[Global.revision]))
				filicide(Global.history[Global.revision])
				Global.revision += 1
				Global.UR[2] -= 1
				

		Global.UR[1] = 0
		dumb_copy = Global.main_stack.slice(0,Global.revision)
		dumb_copy.sort_custom(func(a,b): return a[TMBInfo.NOTE_BAR] < b[TMBInfo.NOTE_BAR])
		tmb.notes = dumb_copy
	
	print("post-history: ",Global.history)
	print("final note: ",%Chart.get_child(%Chart.get_child_count()-1))
	print("revision post-UR: ",Global.revision)
	
	Global.UR[0] = 0
	_on_tmb_updated()
###


func _draw():
	var font : Font = ThemeDB.get_fallback_font()
	if tmb == null: return
	var section_rect = Rect2(bar_to_x(settings.section_start), 1,
			bar_to_x(settings.section_length), size.y)
	draw_rect(section_rect, Color(0.3, 0.9, 1.0, 0.1))
	draw_rect(section_rect, Color.CORNFLOWER_BLUE, false, 3.0)
	if %PreviewController.is_playing:
		draw_line(Vector2(bar_to_x(%PreviewController.song_position),0),
				Vector2(bar_to_x(%PreviewController.song_position),size.y),
				Color.CORNFLOWER_BLUE, 2 )
	for i in tmb.endpoint + 1:
		var line_x = i * bar_spacing
		var next_line_x = (i + 1) * bar_spacing
		if (line_x < scroll_position) && (next_line_x < scroll_position): continue
		if line_x > scroll_end: break
		draw_line(Vector2(line_x, 0), Vector2(line_x, size.y),
				Color.WHITE if !(i % tmb.timesig)
				else Color(1,1,1,0.33) if bar_spacing > 20.0
				else Color(1,1,1,0.15), 2
			)
		var subdiv = %TimingSnap.value
		for j in subdiv:
			if i == tmb.endpoint || bar_spacing < 20.0: break
			if j == 0.0: continue
			var k = 1.0 / subdiv
			var line = i + (k * j)
			draw_line(Vector2(line * bar_spacing, 0), Vector2(line * bar_spacing, size.y),
					Color(0.7,1,1,0.2) if bar_spacing > 20.0
					else Color(0.7,1,1,0.1),
					1 )
		if !(i % tmb.timesig):
			draw_string(font, Vector2(i * bar_spacing, 0) + Vector2(8, 16),
					str(i / tmb.timesig), HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
			draw_string(font, Vector2(i * bar_spacing, 0) + Vector2(8, 32),
					str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		draw_line(Vector2(bar_to_x(%CopyTarget.value), 0),
				Vector2(bar_to_x(%CopyTarget.value), size.y),
				Color.ORANGE_RED, 2.0)


func _gui_input(event):
	if event is InputEventPanGesture:
		# Used for two finger scrolling on trackpads
		_on_scroll_change()
	event = event as InputEventMouseButton
	if event == null || !event.pressed: return
	if event.button_index == MOUSE_BUTTON_LEFT && !%PreviewController.is_playing:
		@warning_ignore("unassigned_variable")
		var new_note_pos : Vector2
		
		if settings.snap_time: new_note_pos.x = to_snapped(event.position).x
		else: new_note_pos.x = to_unsnapped(event.position).x
		
		# Current length of tap notes
		var note_length = 0.0625 if settings.tap_notes else current_subdiv
		
		if new_note_pos.x == tmb.endpoint: new_note_pos.x -= (1.0 / settings.timing_snap)
		if continuous_note_overlaps(new_note_pos.x, note_length): return
		
		if settings.snap_pitch: new_note_pos.y = to_snapped(event.position).y
		else: new_note_pos.y = clamp(to_unsnapped(event.position).y,
				Global.SEMITONE * -13, Global.SEMITONE * 13)
		
		add_note(true, new_note_pos.x, note_length, new_note_pos.y)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN \
			|| event.button_index == MOUSE_BUTTON_WHEEL_UP \
			|| event.button_index == MOUSE_BUTTON_WHEEL_LEFT \
			|| event.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
		_on_scroll_change()


func _notification(what):
	match what:
		NOTIFICATION_RESIZED:
			for note in get_children():
				if note is Note && !note.is_queued_for_deletion():
					note._update()


func _on_doot_toggle_toggled(toggle): doot_enabled = toggle


func _on_show_targets_toggled(toggle):
	draw_targets = toggle
	for note in get_children(): note.queue_redraw()
