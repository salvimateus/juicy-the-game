class_name RigAction
extends RefCounted
## A one-shot animation the Adventurer plays on request. Time t runs from 0 to duration (s).
##
## events is a list of dictionaries sorted by "t", each with one of:
##   "signal": StringName          -> action_event(id, signal)
##   "footstep": &"front"/&"back"  -> footstep(foot, "strength")
##   "flip": true                  -> the rig inverts its facing
##   "fx": type, "params": {...}, and "anchor" (rig anchor) or "x"/"y" (character space, facing right)
##   "custom": name                -> custom_event(ev, host)

const B := preload("res://rig/rig_bone.gd")
const WAIST_FOLLOW := 0.7

var id: StringName
var duration := 1.0
var rig: RigData
var events: Array = []
## Facing when the action started (root motion and facing_sign are relative to it).
var start_facing := 1
## Loco phase to resume at when the action ends (-1 keeps the current one).
var exit_phase := -1.0
## State the rig enters when the action ends: "" free, "hanging", "wall", or "action:<id>" to
## chain straight into another action (e.g. a loop that the game ends with a cancel_by action).
var next_state := ""
## Where the action may start: "" anywhere free, "ground" or "air".
var requires := ""
## Ends (as finished) when the game reports landing; for open-ended air actions.
var ends_on_landing := false
## Action ids allowed to cancel this one while it plays.
var cancel_by: Array[StringName] = []
## Per-bone turn limit while displayed (degrees per 1/60 s, 0 = none), for actions played faster
## than their source keys.
var max_turn := 0.0


func _init(rig_data: RigData) -> void:
	rig = rig_data


## host is the Adventurer (entry speed, loco phase, gaits).
func begin(_host) -> void:
	pass


func sample(_t: float, _pose: RigPose, _juice: bool) -> void:
	pass


## Cumulative displacement since t = 0, x forward along start_facing, y down.
func root_motion(_t: float) -> Vector2:
	return Vector2.ZERO


## Facing multiplier relative to start_facing at time t.
func facing_sign(_t: float) -> int:
	return 1


func custom_event(_ev: Dictionary, _host) -> void:
	pass


## Called by the Adventurer every tick while playing, after the pose is sampled (state, extra
## events). Return true to finish the action now.
func tick(_host, _delta: float) -> bool:
	return false


func sort_events() -> void:
	events.sort_custom(func(a, b): return a.t < b.t)
