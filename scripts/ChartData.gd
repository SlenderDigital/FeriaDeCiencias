class_name ChartData
extends RefCounted
## Loads analysis.json (musical metadata) + level_chart.json (authored gameplay).

var bpm: float = 0.0
var duration: float = 0.0
var beat_times: Array[float] = []
var sections: Array[Dictionary] = []   # {name,start,end,energy}
var level_sections: Array[Dictionary] = []  # authored {name,pattern_pool,density}
var setpieces: Array[Dictionary] = []  # authored event anchors

static func load_charts(analysis_path: String, level_path: String) -> ChartData:
	var cd := ChartData.new()
	var a := FileAccess.open(analysis_path, FileAccess.READ)
	var l := FileAccess.open(level_path, FileAccess.READ)
	if a == null or l == null:
		push_error("ChartData: cannot open chart files")
		return cd
	var analysis = JSON.parse_string(a.get_as_text())
	var level = JSON.parse_string(l.get_as_text())
	if analysis == null or level == null or analysis.is_empty() or level.is_empty():
		push_error("ChartData: malformed chart JSON")
		return cd
	cd.bpm = float(analysis.get("bpm", 0.0))
	cd.duration = float(analysis.get("duration", 0.0))
	cd.beat_times.assign(analysis.get("beats", []))
	cd.sections.assign(_to_dict_array(analysis.get("sections", [])))
	cd.level_sections.assign(_to_dict_array(level.get("sections", [])))
	cd.setpieces.assign(_to_dict_array(level.get("setpieces", [])))
	cd._validate()
	return cd

static func _to_dict_array(arr: Array) -> Array[Dictionary]:
	## Rebuilds an untyped JSON array into a typed Array[Dictionary], skipping
	## any non-Dictionary entries so malformed data cannot cause a runtime type error.
	var out: Array[Dictionary] = []
	for item in arr:
		if item is Dictionary:
			out.append(item)
	return out

func _validate() -> void:
	for i in range(1, beat_times.size()):
		if beat_times[i] <= beat_times[i - 1]:
			push_warning("ChartData: beats not strictly monotonic at %d" % i)
	for s in sections:
		if float(s["end"]) > duration + 0.5:
			push_warning("ChartData: section end %s beyond duration" % s["name"])

func beat_index_at_time(t: float) -> int:
	for i in range(beat_times.size()):
		if beat_times[i] >= t:
			return i
	return beat_times.size()