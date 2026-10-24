class_name DayManager
extends RefCounted
## Office clock 09:00 -> 18:00 compressed into a configurable real duration, with the
## scheduled meetings and lunch break from data/events.json.

signal meeting_changed(active: bool)
signal lunch_changed(active: bool)
signal finished

const START_MIN := 9 * 60
const END_MIN := 18 * 60

var real_duration := 540.0      # seconds of real time for the whole day
var minutes := float(START_MIN) # current game minute
var meeting_active := false
var lunch_active := false
var meeting_present: Dictionary = {}
var _schedule: Array = []       # [{start, end, event}] in game minutes
var _done := false
var paused := false


func setup(day_minutes_real: float) -> void:
	real_duration = maxf(60.0, day_minutes_real * 60.0)
	minutes = START_MIN
	_schedule.clear()
	for e in Data.schedule:
		var hm: PackedStringArray = String(e.time).split(":")
		var st := int(hm[0]) * 60 + int(hm[1])
		_schedule.append({"start": float(st), "end": float(st + int(e.duration_min)), "event": e.event})


## Game seconds elapsing per real second.
func time_scale() -> float:
	return float(END_MIN - START_MIN) * 60.0 / real_duration


func tick(dt: float) -> void:
	if _done or paused:
		return
	minutes += dt * time_scale() / 60.0
	var m := false
	var l := false
	for e in _schedule:
		if minutes >= e.start and minutes < e.end:
			if e.event == "meeting":
				m = true
			elif e.event == "lunch":
				l = true
	if m != meeting_active:
		meeting_active = m
		if m:
			meeting_present.clear()
		meeting_changed.emit(m)
	if l != lunch_active:
		lunch_active = l
		lunch_changed.emit(l)
	if minutes >= END_MIN:
		_done = true
		finished.emit()


func is_over() -> bool:
	return _done


func progress() -> float:
	return clampf((minutes - START_MIN) / float(END_MIN - START_MIN), 0.0, 1.0)


func clock_text() -> String:
	var m := int(minutes)
	return "%02d:%02d" % [m / 60, m % 60]


func minutes_to_next(event: String) -> float:
	var best := INF
	for e in _schedule:
		if e.event == event and e.start > minutes:
			best = minf(best, e.start - minutes)
	return best


## "Early meeting" event: the next meeting starts now.
func start_meeting_now(duration_min := 30.0) -> void:
	for e in _schedule:
		if e.event == "meeting" and e.start > minutes:
			e.start = minutes
			e.end = minutes + duration_min
			return


func mark_present(id: String) -> void:
	meeting_present[id] = true


func meeting_late(_id: String) -> bool:
	return meeting_active
