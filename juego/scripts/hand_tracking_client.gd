extends Node

signal tracking_state_changed(new_state: int, label_text: String)
signal fist_closed_triggered

enum TrackingState {
	OFFLINE = 0,
	NO_HAND = 1,
	TRACKING = 2,
}

const UDP_HOST: String = "127.0.0.1"
const UDP_PORT: int = 5005
const LANDMARK_COUNT: int = 21
const FLOATS_PER_LANDMARK: int = 3
const FULL_PACKET_BYTES: int = 4 + LANDMARK_COUNT * FLOATS_PER_LANDMARK * 4
const EMPTY_PACKET_BYTES: int = 4
const PACKET_TIMEOUT: float = 0.5
const HEARTBEAT_MAX_AGE_SEC: int = 5

const PALM_LANDMARK_INDICES: Array[int] = [0, 5, 9, 13, 17]
const FIST_FINGER_TRIPLETS: Array[Array] = [
	[5, 6, 8],
	[9, 10, 12],
	[13, 14, 16],
	[17, 18, 20],
]

var udp_port: int = UDP_PORT
var udp_bound: bool = false
var tracker_pid: int = -1
var tracking_state: int = TrackingState.OFFLINE
var has_hand: bool = false
var is_fist: bool = false
var fist_just_closed: bool = false
var landmark_revision: int = 0
var landmarks: Array[Vector3] = []
var last_status_text: String = ""
var status_file_override: String = ""

var _udp: PacketPeerUDP = PacketPeerUDP.new()
var _time_since_last_packet: float = 999.0
var _has_received_packet: bool = false
var _was_fist: bool = false
var _has_seen_open_hand: bool = false
var _status_check_timer: float = 0.0
var _cached_heartbeat_ready: bool = false
var _cached_heartbeat_error: bool = false


func _ready() -> void:
	bind_udp(udp_port)
	start_tracker_process()


func _process(delta: float) -> void:
	poll_and_update(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		stop_tracker_process()
		close_udp()


func _exit_tree() -> void:
	stop_tracker_process()
	close_udp()


func bind_udp(port: int = UDP_PORT) -> Error:
	if udp_bound and udp_port == port:
		return OK
	close_udp()
	udp_port = port
	var err: Error = _udp.bind(udp_port, UDP_HOST)
	udp_bound = (err == OK)
	return err


func close_udp() -> void:
	if udp_bound:
		_udp.close()
		udp_bound = false


func get_tracker_server_dir() -> String:
	if not OS.has_feature("editor"):
		var exe_dir: String = OS.get_executable_path().get_base_dir()
		var bundled_dir: String = exe_dir.path_join("tracker_server").simplify_path()
		if DirAccess.dir_exists_absolute(bundled_dir):
			return bundled_dir
		var sibling_dir: String = exe_dir.path_join("../tracker_server").simplify_path()
		if DirAccess.dir_exists_absolute(sibling_dir):
			return sibling_dir
	return ProjectSettings.globalize_path("res://../tracker_server").simplify_path()


func resolve_tracker_launch_command() -> Dictionary:
	var tracker_dir: String = get_tracker_server_dir()
	var is_windows: bool = OS.get_name() == "Windows"
	var parent_pid_str: String = str(OS.get_process_id())
	var module_args: PackedStringArray = PackedStringArray(["-m", "mediapipe_py.main", "--headless", "--parent-pid", parent_pid_str])
	var script_args: PackedStringArray = PackedStringArray(["--headless", "--parent-pid", parent_pid_str])

	var bundled_candidates: Array[String] = []
	if is_windows:
		bundled_candidates = [tracker_dir.path_join("python/pythonw.exe"), tracker_dir.path_join("python/python.exe")]
	else:
		bundled_candidates = [tracker_dir.path_join("python/bin/python3"), tracker_dir.path_join("python/bin/python")]
	for bundled_py: String in bundled_candidates:
		if FileAccess.file_exists(bundled_py):
			return {"executable": bundled_py, "args": module_args}

	if is_windows:
		var venv_pythonw: String = tracker_dir.path_join(".venv/Scripts/pythonw.exe")
		if FileAccess.file_exists(venv_pythonw):
			return {"executable": venv_pythonw, "args": module_args}

	var venv_entry: String = tracker_dir.path_join(".venv/Scripts/mediapipe-py.exe" if is_windows else ".venv/bin/mediapipe-py")
	if FileAccess.file_exists(venv_entry):
		return {"executable": venv_entry, "args": script_args}

	var venv_python: String = tracker_dir.path_join(".venv/Scripts/python.exe" if is_windows else ".venv/bin/python")
	if FileAccess.file_exists(venv_python):
		return {"executable": venv_python, "args": module_args}

	return {
		"executable": "uv",
		"args": PackedStringArray(["run", "--directory", tracker_dir, "mediapipe-py", "--headless", "--parent-pid", parent_pid_str]),
	}


func start_tracker_process() -> bool:
	if DisplayServer.get_name() == "headless" or is_tracker_process_alive():
		return false
	_refresh_heartbeat_cache()
	if _cached_heartbeat_ready or (_has_received_packet and _time_since_last_packet <= PACKET_TIMEOUT):
		return false

	_clear_stale_status_files()
	var tracker_dir: String = get_tracker_server_dir()
	OS.set_environment("TRACKER_HEADLESS", "1")
	OS.set_environment("TRACKER_PARENT_PID", str(OS.get_process_id()))
	OS.set_environment("TRACKER_STATUS_FILE", tracker_dir.path_join(".tracker.status"))

	var cmd: Dictionary = resolve_tracker_launch_command()
	var executable: String = str(cmd.get("executable", ""))
	var args: PackedStringArray = cmd.get("args", PackedStringArray()) as PackedStringArray
	if executable.is_empty():
		return false

	var spawned_pid: int = OS.create_process(executable, args, false)
	tracker_pid = spawned_pid if spawned_pid > 0 else -1
	return tracker_pid > 0


func stop_tracker_process() -> void:
	if tracker_pid <= 0:
		return
	if OS.is_process_running(tracker_pid):
		OS.kill(tracker_pid)
	tracker_pid = -1


func is_tracker_process_alive() -> bool:
	return tracker_pid > 0 and OS.is_process_running(tracker_pid)


func ingest_packet_batch(packets: Array[PackedByteArray]) -> bool:
	var latest_valid: Dictionary = {}
	for pkt: PackedByteArray in packets:
		var decoded: Dictionary = decode_packet(pkt)
		if bool(decoded.get("valid", false)):
			latest_valid = decoded
	if latest_valid.is_empty():
		return false
	_apply_decoded_packet(latest_valid)
	return true


func ingest_packet(packet: PackedByteArray) -> bool:
	var decoded: Dictionary = decode_packet(packet)
	if not bool(decoded.get("valid", false)):
		return false
	_apply_decoded_packet(decoded)
	return true


func decode_packet(packet: PackedByteArray) -> Dictionary:
	if packet.size() < EMPTY_PACKET_BYTES:
		return {"valid": false, "count": 0, "landmarks": []}

	var count: int = packet.decode_s32(0)
	if count == 0:
		return {"valid": true, "count": 0, "landmarks": []}
	if count != LANDMARK_COUNT or packet.size() < FULL_PACKET_BYTES:
		return {"valid": false, "count": count, "landmarks": []}

	var parsed: Array[Vector3] = []
	parsed.resize(LANDMARK_COUNT)
	var offset: int = 4
	for i: int in range(LANDMARK_COUNT):
		parsed[i] = Vector3(
			packet.decode_float(offset),
			packet.decode_float(offset + 4),
			packet.decode_float(offset + 8)
		)
		offset += 12
	return {"valid": true, "count": LANDMARK_COUNT, "landmarks": parsed}


static func encode_landmarks_packet(points: Array[Vector3]) -> PackedByteArray:
	if points.size() != LANDMARK_COUNT:
		return encode_empty_packet()
	var buf: PackedByteArray = PackedByteArray()
	buf.resize(FULL_PACKET_BYTES)
	buf.encode_s32(0, LANDMARK_COUNT)
	var offset: int = 4
	for pt: Vector3 in points:
		buf.encode_float(offset, pt.x)
		buf.encode_float(offset + 4, pt.y)
		buf.encode_float(offset + 8, pt.z)
		offset += 12
	return buf


static func encode_empty_packet() -> PackedByteArray:
	var buf: PackedByteArray = PackedByteArray()
	buf.resize(EMPTY_PACKET_BYTES)
	buf.encode_s32(0, 0)
	return buf


func poll_and_update(delta: float) -> void:
	var drained: Array[PackedByteArray] = []
	if udp_bound:
		while _udp.get_available_packet_count() > 0:
			var pkt: PackedByteArray = _udp.get_packet()
			if _udp.get_packet_error() == OK and pkt.size() >= EMPTY_PACKET_BYTES:
				drained.append(pkt)

	if not drained.is_empty():
		ingest_packet_batch(drained)
	else:
		_time_since_last_packet += maxf(0.0, delta)

	_status_check_timer -= delta
	if _status_check_timer <= 0.0:
		_status_check_timer = 0.15 if not _cached_heartbeat_ready and not _cached_heartbeat_error else 0.5
		_refresh_heartbeat_cache()

	_refresh_tracking_state()


func get_mirrored_palm_center() -> Vector2:
	if landmarks.size() < LANDMARK_COUNT:
		return Vector2(0.5, 0.5)
	var sum: Vector2 = Vector2.ZERO
	for idx: int in PALM_LANDMARK_INDICES:
		sum += Vector2(landmarks[idx].x, landmarks[idx].y)
	var avg: Vector2 = sum / float(PALM_LANDMARK_INDICES.size())
	return Vector2(clampf(1.0 - avg.x, 0.0, 1.0), clampf(avg.y, 0.0, 1.0))


func get_mirrored_landmarks_2d() -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	if landmarks.size() < LANDMARK_COUNT:
		return result
	result.resize(LANDMARK_COUNT)
	for i: int in range(LANDMARK_COUNT):
		var lm: Vector3 = landmarks[i]
		result[i] = Vector2(clampf(1.0 - lm.x, 0.0, 1.0), clampf(lm.y, 0.0, 1.0))
	return result


func get_status_label_text() -> String:
	match tracking_state:
		TrackingState.TRACKING:
			return "HAND: TRACKING"
		TrackingState.NO_HAND:
			return "HAND: NO HAND"
		_:
			return "HAND: OFFLINE"


func get_startup_progress_info() -> Dictionary:
	var packet_fresh: bool = _has_received_packet and _time_since_last_packet <= PACKET_TIMEOUT
	if tracking_state == TrackingState.TRACKING or tracking_state == TrackingState.NO_HAND or _cached_heartbeat_ready or packet_fresh:
		return {"progress": 1.0, "text": "HAND TRACKER: READY", "done": true, "failed": false}
	if _cached_heartbeat_error or last_status_text.begins_with("error"):
		return {"progress": 1.0, "text": "HAND TRACKER: OFFLINE (MOUSE/KEYS)", "done": true, "failed": true}
	match last_status_text:
		"opening_camera":
			return {"progress": 0.72, "text": "HAND TRACKER: OPENING CAMERA...", "done": false, "failed": false}
		"loading_model":
			return {"progress": 0.42, "text": "HAND TRACKER: LOADING MODEL...", "done": false, "failed": false}
	if is_tracker_process_alive():
		return {"progress": 0.16, "text": "HAND TRACKER: STARTING SERVICE...", "done": false, "failed": false}
	return {"progress": 0.08, "text": "HAND TRACKER: STARTING...", "done": false, "failed": false}


static func evaluate_closed_fist(points: Array[Vector3]) -> bool:
	if points.size() < LANDMARK_COUNT:
		return false

	var wrist: Vector2 = Vector2(points[0].x, points[0].y)
	var palm_sum: Vector2 = Vector2.ZERO
	for idx: int in PALM_LANDMARK_INDICES:
		palm_sum += Vector2(points[idx].x, points[idx].y)
	var palm_center: Vector2 = palm_sum / float(PALM_LANDMARK_INDICES.size())

	var mcp_dist_sum: float = 0.0
	for mcp_idx: int in [5, 9, 13, 17]:
		mcp_dist_sum += Vector2(points[mcp_idx].x, points[mcp_idx].y).distance_to(palm_center)
	var palm_radius: float = maxf(0.015, mcp_dist_sum / 4.0)

	var curled_fingers: int = 0
	for triplet: Array in FIST_FINGER_TRIPLETS:
		var mcp_pt: Vector2 = Vector2(points[int(triplet[0])].x, points[int(triplet[0])].y)
		var pip_pt: Vector2 = Vector2(points[int(triplet[1])].x, points[int(triplet[1])].y)
		var tip_pt: Vector2 = Vector2(points[int(triplet[2])].x, points[int(triplet[2])].y)

		var tip_to_palm: float = tip_pt.distance_to(palm_center)
		var pip_to_palm: float = pip_pt.distance_to(palm_center)
		var mcp_to_palm: float = mcp_pt.distance_to(palm_center)
		var tip_to_wrist: float = tip_pt.distance_to(wrist)
		var pip_to_wrist: float = pip_pt.distance_to(wrist)

		var curled_into_palm: bool = tip_to_palm <= maxf(mcp_to_palm * 1.18, palm_radius * 1.18)
		var curled_past_pip: bool = tip_to_palm < pip_to_palm * 0.92 and tip_to_wrist < pip_to_wrist * 0.92
		if (curled_into_palm and tip_to_wrist < pip_to_wrist * 0.96) or curled_past_pip:
			curled_fingers += 1

	return curled_fingers >= 3


func _apply_decoded_packet(decoded: Dictionary) -> void:
	_has_received_packet = true
	_time_since_last_packet = 0.0
	var count: int = int(decoded.get("count", 0))
	if count == LANDMARK_COUNT:
		var pts: Array[Vector3] = []
		var raw_list: Array = decoded.get("landmarks", [])
		pts.resize(LANDMARK_COUNT)
		for i: int in range(LANDMARK_COUNT):
			pts[i] = raw_list[i] as Vector3
		landmarks = pts
		has_hand = true
		landmark_revision += 1

		var now_fist: bool = evaluate_closed_fist(landmarks)
		if not now_fist:
			_has_seen_open_hand = true
			fist_just_closed = false
		elif _has_seen_open_hand and not _was_fist:
			fist_just_closed = true
			fist_closed_triggered.emit()
		_was_fist = now_fist
		is_fist = now_fist
	else:
		_clear_hand_tracking_state()

	_refresh_tracking_state()


func _clear_hand_tracking_state() -> void:
	has_hand = false
	is_fist = false
	fist_just_closed = false
	_was_fist = false
	_has_seen_open_hand = false
	landmarks.clear()


func _refresh_tracking_state() -> void:
	var packet_fresh: bool = _has_received_packet and _time_since_last_packet <= PACKET_TIMEOUT
	if has_hand and not packet_fresh:
		_clear_hand_tracking_state()

	var next_state: int = TrackingState.OFFLINE
	if _cached_heartbeat_error and not packet_fresh:
		next_state = TrackingState.OFFLINE
	elif has_hand and packet_fresh:
		next_state = TrackingState.TRACKING
	elif packet_fresh or (_cached_heartbeat_ready and not _cached_heartbeat_error):
		next_state = TrackingState.NO_HAND

	if next_state != tracking_state:
		tracking_state = next_state
		tracking_state_changed.emit(tracking_state, get_status_label_text())


func set_status_file_override(path: String) -> void:
	status_file_override = path
	_status_check_timer = 0.0
	_refresh_heartbeat_cache()
	_refresh_tracking_state()


func reset_state() -> void:
	_clear_hand_tracking_state()
	_has_received_packet = false
	_time_since_last_packet = 999.0
	last_status_text = ""
	status_file_override = ""
	_cached_heartbeat_ready = false
	_cached_heartbeat_error = false
	tracking_state = TrackingState.OFFLINE


func _get_candidate_status_files() -> Array[String]:
	if not status_file_override.is_empty():
		return [status_file_override]
	return [
		get_tracker_server_dir().path_join(".tracker.status"),
		OS.get_executable_path().get_base_dir().path_join(".tracker.status").simplify_path(),
		ProjectSettings.globalize_path("res://.tracker.status").simplify_path(),
		ProjectSettings.globalize_path("res://../.tracker.status").simplify_path(),
	]


func _refresh_heartbeat_cache() -> void:
	_cached_heartbeat_ready = false
	_cached_heartbeat_error = false
	var now_unix: int = int(Time.get_unix_time_from_system())
	var newest_mtime: int = -1
	var newest_text: String = ""

	for path: String in _get_candidate_status_files():
		if not FileAccess.file_exists(path):
			continue
		var mtime: int = int(FileAccess.get_modified_time(path))
		if mtime >= newest_mtime:
			newest_mtime = mtime
			var file: FileAccess = FileAccess.open(path, FileAccess.READ)
			if file != null:
				newest_text = file.get_as_text().strip_edges()

	if newest_mtime < 0:
		return

	last_status_text = newest_text
	var age: int = maxi(0, now_unix - newest_mtime)
	if newest_text.begins_with("error") and age <= HEARTBEAT_MAX_AGE_SEC * 2:
		_cached_heartbeat_error = true
	elif newest_text == "ready" and age <= HEARTBEAT_MAX_AGE_SEC:
		_cached_heartbeat_ready = true


func _clear_stale_status_files() -> void:
	var now_unix: int = int(Time.get_unix_time_from_system())
	for path: String in _get_candidate_status_files():
		if FileAccess.file_exists(path) and now_unix - int(FileAccess.get_modified_time(path)) > HEARTBEAT_MAX_AGE_SEC:
			DirAccess.remove_absolute(path)
