extends Node
## Session (autoload). Player-to-player communication for the phone:
##  - roster of players in the current session (Godot high-level multiplayer peers)
##  - direct text messages (reliable RPC) with per-player threads
##  - voice calls: ring / accept / decline / end signalling plus microphone streaming
##    (AudioEffectCapture -> 16 kHz 16-bit PCM over unreliable-ordered RPC -> generator)
## With no multiplayer peer attached (single player, tests) a simulated roster answers
## texts and calls so the whole phone flow works offline. Attach a real peer with
## multiplayer.multiplayer_peer = ENetMultiplayerPeer / WebRTC and the same code talks
## to real players.

signal players_changed
signal message_received(player_id: int, text: String)
signal message_sent(player_id: int, text: String)
signal call_state_changed(player_id: int, state: String)   # calling, ringing, active, ended, declined, busy
signal voice_level(level: float)                             # local microphone level 0..1 during a call

const VOICE_RATE := 16000
const VOICE_FRAME := 320            # 20 ms at 16 kHz
const SIMULATED_PLAYERS := [
	{"name": "Juno Hale", "class": "Sniper", "rank": "D"},
	{"name": "Teo Varga", "class": "Engineer", "rank": "D"},
	{"name": "Ilse Moor", "class": "Archer", "rank": "C"},
]
const SIM_REPLIES := [
	"On my way to the Hub, meet at the portal?",
	"Copy that. Rank D bracket opens in ten.",
	"Need a hand with that delivery? I've got the van.",
	"Haha fair. Clan war tonight, you in?",
	"Send me the GPS pin and I'll be there.",
]

var local_name := "Operative"
var players: Dictionary = {}        # id -> {"name", "class", "rank", "simulated"}
var threads: Dictionary = {}        # id -> Array of {"from_me": bool, "text": String, "time": String}
var unread: Dictionary = {}         # id -> int
var active_call_id := -1
var call_state := "idle"            # idle, calling, ringing, active
var call_started_at := 0.0
var mic_muted := false

var _next_sim_id := 1000
var _mic_player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _voice_player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _sim_level_phase := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not is_online():
		_spawn_simulated_roster()
	_setup_voice_buses()


# ============================================================ roster
func is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer)


func local_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


func player_name(id: int) -> String:
	return str(players.get(id, {}).get("name", "Player %d" % id))


func player_ids() -> Array:
	var ids := players.keys()
	ids.sort()
	return ids


func _spawn_simulated_roster() -> void:
	for p in SIMULATED_PLAYERS:
		players[_next_sim_id] = {"name": p["name"], "class": p["class"], "rank": p["rank"], "simulated": true}
		_next_sim_id += 1
	players_changed.emit()


func _on_peer_connected(id: int) -> void:
	players[id] = {"name": "Player %d" % id, "class": "?", "rank": "?", "simulated": false}
	_rpc_hello.rpc_id(id, local_name, Globalvar.current_class, Globalvar.current_rank)
	players_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	if active_call_id == id:
		_set_call(id, "ended")
	players.erase(id)
	players_changed.emit()


@rpc("any_peer", "reliable")
func _rpc_hello(name: String, cls: String, rank: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	players[id] = {"name": name, "class": cls, "rank": rank, "simulated": false}
	players_changed.emit()


# ============================================================ text
func send_text(player_id: int, text: String) -> bool:
	text = text.strip_edges()
	if text == "" or not players.has(player_id):
		return false
	_append(player_id, true, text)
	message_sent.emit(player_id, text)
	if players[player_id]["simulated"]:
		_simulate_reply(player_id, text)
	else:
		_rpc_text.rpc_id(player_id, text)
	return true


@rpc("any_peer", "reliable")
func _rpc_text(text: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	_receive_text(id, text)


func _receive_text(id: int, text: String) -> void:
	_append(id, false, text)
	unread[id] = int(unread.get(id, 0)) + 1
	message_received.emit(id, text)


func _append(id: int, from_me: bool, text: String) -> void:
	if not threads.has(id):
		threads[id] = []
	threads[id].append({"from_me": from_me, "text": text, "time": Time.get_time_string_from_system().substr(0, 5)})


func mark_read(id: int) -> void:
	unread[id] = 0


func unread_total() -> int:
	var n := 0
	for id in unread:
		n += int(unread[id])
	return n


func _simulate_reply(id: int, text: String) -> void:
	var reply: String = SIM_REPLIES[randi() % SIM_REPLIES.size()]
	var lower := text.to_lower()
	if "where" in lower:
		reply = "I'm at the Hub by the job board. Come find me."
	elif "car" in lower or "ride" in lower:
		reply = "Call Rook, he'll valet it to you faster than I can drive."
	elif "war" in lower or "clan" in lower:
		reply = "Ashfall is in. Ruins Arena, tonight."
	get_tree().create_timer(randf_range(1.2, 2.5), true).timeout.connect(func() -> void: _receive_text(id, reply))


# ============================================================ voice calls
func start_call(player_id: int) -> bool:
	if call_state != "idle" or not players.has(player_id):
		return false
	active_call_id = player_id
	_set_call(player_id, "calling")
	if players[player_id]["simulated"]:
		get_tree().create_timer(1.4, true).timeout.connect(func() -> void:
			if active_call_id == player_id and call_state == "calling":
				_begin_active())
	else:
		_rpc_call.rpc_id(player_id, "ring")
	return true


func accept_call() -> void:
	if call_state != "ringing":
		return
	if not players[active_call_id]["simulated"]:
		_rpc_call.rpc_id(active_call_id, "accept")
	_begin_active()


func decline_call() -> void:
	if call_state != "ringing":
		return
	if not players[active_call_id]["simulated"]:
		_rpc_call.rpc_id(active_call_id, "decline")
	_set_call(active_call_id, "declined")
	_reset_call()


func end_call() -> void:
	if call_state == "idle":
		return
	if players.has(active_call_id) and not players[active_call_id]["simulated"]:
		_rpc_call.rpc_id(active_call_id, "end")
	_stop_voice()
	_set_call(active_call_id, "ended")
	_reset_call()


func toggle_mute() -> bool:
	mic_muted = not mic_muted
	return mic_muted


func call_duration() -> float:
	return (Time.get_ticks_msec() / 1000.0 - call_started_at) if call_state == "active" else 0.0


## Testing / demo hook: a simulated player rings you.
func simulate_incoming_call(player_id: int) -> void:
	if call_state != "idle" or not players.has(player_id):
		return
	active_call_id = player_id
	_set_call(player_id, "ringing")


@rpc("any_peer", "reliable")
func _rpc_call(action: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	match action:
		"ring":
			if call_state != "idle":
				_rpc_call.rpc_id(id, "busy")
				return
			active_call_id = id
			_set_call(id, "ringing")
		"accept":
			if active_call_id == id and call_state == "calling":
				_begin_active()
		"decline", "busy":
			if active_call_id == id:
				_set_call(id, action)
				_reset_call()
		"end":
			if active_call_id == id:
				_stop_voice()
				_set_call(id, "ended")
				_reset_call()


func _begin_active() -> void:
	call_started_at = Time.get_ticks_msec() / 1000.0
	_set_call(active_call_id, "active")
	_start_voice()


func _set_call(id: int, state: String) -> void:
	call_state = state if state in ["calling", "ringing", "active"] else "idle"
	call_state_changed.emit(id, state)


func _reset_call() -> void:
	active_call_id = -1
	call_state = "idle"
	mic_muted = false


# ---- microphone capture and playback -------------------------------------------
func _setup_voice_buses() -> void:
	if AudioServer.get_bus_index("VoiceMic") == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "VoiceMic")
		AudioServer.set_bus_mute(idx, true)                # never play your own mic locally
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 0.5
		AudioServer.add_bus_effect(idx, _capture)
	else:
		_capture = AudioServer.get_bus_effect(AudioServer.get_bus_index("VoiceMic"), 0) as AudioEffectCapture
	_voice_player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = VOICE_RATE
	gen.buffer_length = 0.3
	_voice_player.stream = gen
	add_child(_voice_player)


func _mic_available() -> bool:
	return bool(ProjectSettings.get_setting("audio/driver/enable_input", false)) and DisplayServer.get_name() != "headless"


func _start_voice() -> void:
	if _mic_available() and _mic_player == null:
		_mic_player = AudioStreamPlayer.new()
		_mic_player.stream = AudioStreamMicrophone.new()
		_mic_player.bus = "VoiceMic"
		add_child(_mic_player)
		_mic_player.play()
	if not _voice_player.playing:
		_voice_player.play()
	_playback = _voice_player.get_stream_playback() as AudioStreamGeneratorPlayback


func _stop_voice() -> void:
	if _mic_player:
		_mic_player.stop()
		_mic_player.queue_free()
		_mic_player = null
	if _voice_player.playing:
		_voice_player.stop()
	_playback = null


func _process(delta: float) -> void:
	if call_state != "active":
		return
	if _capture != null and _mic_player != null and _capture.can_get_buffer(VOICE_FRAME):
		var frames := _capture.get_buffer(VOICE_FRAME)
		var rms := 0.0
		for f in frames:
			rms += f.x * f.x
		rms = sqrt(rms / maxf(1.0, frames.size()))
		voice_level.emit(0.0 if mic_muted else clampf(rms * 6.0, 0.0, 1.0))
		if not mic_muted and players.has(active_call_id) and not players[active_call_id]["simulated"]:
			_rpc_voice.rpc_id(active_call_id, _encode(frames))
	elif _mic_player == null:
		# no microphone (headless / input disabled): animate a plausible level for the UI
		_sim_level_phase += delta * 4.0
		voice_level.emit(0.0 if mic_muted else 0.25 + 0.2 * absf(sin(_sim_level_phase)))


func _encode(frames: PackedVector2Array) -> PackedByteArray:
	# stereo float -> mono 16-bit at the engine mix rate; receivers play it back at VOICE_RATE,
	# so downsample by the ratio first.
	var ratio := maxi(1, int(round(AudioServer.get_mix_rate() / VOICE_RATE)))
	var out := PackedByteArray()
	var i := 0
	while i < frames.size():
		var s := clampf((frames[i].x + frames[i].y) * 0.5, -1.0, 1.0)
		var v := int(s * 32767.0)
		out.append(v & 0xFF)
		out.append((v >> 8) & 0xFF)
		i += ratio
	return out


@rpc("any_peer", "unreliable_ordered")
func _rpc_voice(data: PackedByteArray) -> void:
	if _playback == null or multiplayer.get_remote_sender_id() != active_call_id:
		return
	var n := data.size() / 2
	for i in range(n):
		var v := data[i * 2] | (data[i * 2 + 1] << 8)
		if v >= 32768:
			v -= 65536
		var s := float(v) / 32767.0
		if _playback.can_push_buffer(1):
			_playback.push_frame(Vector2(s, s))
