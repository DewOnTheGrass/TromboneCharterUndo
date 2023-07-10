extends Node

signal tmb_updated
const SEMITONE := 13.75
const TWELFTH_ROOT_2 : float = pow( 2, (1.0 / 12.0) )
static func pitch_to_scale(pitch:float) -> float: return pow(TWELFTH_ROOT_2,pitch)
# range goes from -13 to 13, c3 to c5
const BLACK_KEYS = [
	-11, -9, -6,
	-4, -2,
	1, 3,
	6, 8, 10,
	13
]
const NUM_KEYS = 27
@onready var working_tmb = TMBInfo.new()
var settings : Settings
enum {
	END_IS_TOUCHING,
	START_IS_TOUCHING,
}
###Dew's variables###
var UR := [0,0]
	# 0   => normal operation
	# 1   => undo last action
	# 2   => redo last action
	#  ,0 => fix w/ drag
	#  ,1 => fix w/ addition
	#  ,2 => fix w/ deletion
var starting_note : Array
var ratio := ["L","L","L","L","L"]
var respects := ["F","F","F","F","F"]
var revision = -1
var active_revision = -1

var a_array := []
var d_array := []

# shamelessly copied from wikiped https://en.wikipedia.org/wiki/Smoothstep#Variations
static func smootherstep(from:float, to:float, x:float) -> float:
	x = clamp((x - from) / (to - from), 0.0, 1.0)
	return x * x * x * (x * (x * 6 - 15) + 10)


func overlaps_any_note(time:float, exclude : Array = []) -> bool:
	var bar : float
	var note_end : float
	for note in working_tmb.notes:
		bar = note[TMBInfo.NOTE_BAR]
		if bar in exclude:
			continue
		note_end = bar + note[TMBInfo.NOTE_LENGTH]
		var bar_difference = abs(time - bar)
		var end_difference = abs(time - note_end)
		
		if (time > bar && time < note_end) \
				&& !(bar_difference < 0.01 || end_difference < 0.01):
#			print("start: +/-%.9f -- end: +/-%.9f" % [bar_difference, end_difference])
			return true
	return false


func _ready(): pass


func _on_tmb_updated(value,key:String):
	if key == "title": key = "name" # fix collision
	working_tmb.set(key,value)
	emit_signal("tmb_updated")
