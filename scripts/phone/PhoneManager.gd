extends CanvasLayer
## Phone (autoload). The in-game smartphone from the design document:
##  - toggles with the "phone" action (P) or the on-screen button, animated slide-up
##  - Home, Job Board, Property, Vehicle, Market, Clan Hub, GPS, Stats & Wallet, Notifications
##  - Contacts & Calls: outgoing calls to saved contacts, incoming calls with Answer / Ignore,
##    invitations (battle, tournament, clan war) accepted or declined from the phone
##  - GPS spawns a GpsMarker in the world and wires job arrival into JobManager
## Everything is built in code against Globalvar + JobManager so it drops into any scene.

signal phone_toggled(is_open: bool)
signal destination_set(position: Vector3, label: String)
signal destination_cleared
signal invitation_answered(kind: String, accepted: bool)
signal purchase_made(kind: String, id: String)

const PHONE_MAX_SIZE := Vector2(360, 640)
const DOCK_BOTTOM := 70.0
var PHONE_SIZE := PHONE_MAX_SIZE   # shrinks on small windows, see _layout()
const APPS := [
	["jobs", "JOBS", "Job Board", PhoneTheme.ACCENT],
	["property", "HOMES", "Property", PhoneTheme.GOLD],
	["vehicle", "CARS", "Vehicle", PhoneTheme.AMBER],
	["market", "SHOP", "Market", PhoneTheme.GREEN],
	["clan", "CLAN", "Clan Hub", PhoneTheme.ACCENT2],
	["gps", "GPS", "Navigate", PhoneTheme.ACCENT],
	["stats", "STATS", "Stats & Wallet", PhoneTheme.GOLD],
	["contacts", "CALLS", "Contacts", PhoneTheme.GREEN],
]

var is_open := false
var notifications: Array[Dictionary] = []
var unread := 0

var _dock: Control
var _phone: PanelContainer
var _screen: VBoxContainer
var _page_host: Control
var _pages: Dictionary = {}
var _status_time: Label
var _status_rank: Label
var _status_badge: Label
var _tween: Tween
var _phone_button: Button
var _toast_box: VBoxContainer
var _call_overlay: Control
var _call_name: Label
var _call_role: Label
var _call_state: Label
var _call_text: Label
var _call_actions: HBoxContainer
var _call_avatar: PanelContainer
var _call_typing: Tween
var _voice: AudioStreamPlayer          # Rook's recorded lines (audio/phone/rook_*.wav)
const VOICE_LINES := {
	"greeting": "res://audio/phone/rook_greeting.wav",
	"request": "res://audio/phone/rook_request.wav",
	"return": "res://audio/phone/rook_return.wav",
	"fix": "res://audio/phone/rook_fix.wav",
	"ready": "res://audio/phone/rook_ready.wav",
}
var _marker: GpsMarker
var _gps_job_id := ""
var _confirm_id := ""
var _market_category := "All"
var _job_sort := "pay"
var _job_type := "All"
var _vehicle_color: Dictionary = {}
var _pending_invites: Array[Dictionary] = []
var _active_call: Dictionary = {}     # {"kind": "npc"|"player", "contact", "player_id", "line", "action_label", "action_page", "incoming"}
var _call_panel: VBoxContainer        # sub-content on the call card (valet vehicle lists)
var _call_meter: ProgressBar          # microphone level during voice calls
var _call_timer: Label
var _valet_mode := ""
var _msg_player_id := -1
var _msg_input: LineEdit


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_input_action()
	_build()
	Globalvar.credits_changed.connect(func(_v: int) -> void: _refresh_if_open(["home", "stats", "property", "vehicle", "market"]))
	RankManager.renown_changed.connect(func(_v: int) -> void: _refresh_if_open(["home", "stats", "clan"]))
	Globalvar.points_changed.connect(func(_v: int) -> void: _refresh_if_open(["stats"]))
	Globalvar.reputation_changed.connect(func(_v: int) -> void: _refresh_if_open(["stats", "clan"]))
	RankManager.rank_changed.connect(_on_rank_changed)
	JobManager.job_accepted.connect(_on_job_accepted)
	JobManager.job_progress_updated.connect(func(_id: String, _p: int, _t: int) -> void: _refresh_if_open(["jobs"]))
	JobManager.job_completed.connect(_on_job_completed)
	Session.players_changed.connect(func() -> void: _refresh_if_open(["contacts", "home"]))
	Session.message_received.connect(_on_message_received)
	Session.call_state_changed.connect(_on_player_call_state)
	Session.voice_level.connect(func(level: float) -> void:
		if _call_meter and _call_meter.visible:
			_call_meter.value = level)
	Valet.driver_dispatched.connect(func(vid: String, eta: float) -> void:
		notify("Valet dispatched", "%s is on its way to you. ETA about %d seconds." % [PhoneData.vehicle(vid)["name"], int(eta)], "vehicle")
		_refresh_valet_views())
	Valet.vehicle_delivered.connect(func(vid: String, _car: Node3D) -> void:
		notify("Vehicle delivered", "%s is parked beside you. Press E to get in." % PhoneData.vehicle(vid)["name"], "vehicle")
		_refresh_valet_views())
	Valet.vehicle_returned.connect(func(vid: String) -> void:
		notify("Vehicle returned", "%s is back in the garage." % PhoneData.vehicle(vid)["name"], "vehicle")
		_refresh_valet_views())
	Valet.repair_started.connect(func(vid: String, secs: float) -> void:
		notify("Repair started", "%s is on the lift. Ready in %s." % [PhoneData.vehicle(vid)["name"], Valet._fmt(secs)], "vehicle")
		_refresh_valet_views())
	Valet.repair_finished.connect(func(vid: String) -> void:
		var vname: String = PhoneData.vehicle(vid)["name"]
		notify("Repair complete", "%s is fixed and back in the garage." % vname, "vehicle")
		_refresh_valet_views()
		incoming_call("mechanic", "Rook here. Your %s is fixed - good as new. Want me to send it over?" % vname, "Open Vehicle app", "vehicle"))
	Globalvar.add_contact("job_agent")
	Globalvar.add_contact("mechanic")
	notify("Welcome to Nova Aetheris", "Your phone is active. Press P or tap PHONE to open it.", "system")


func _process(_delta: float) -> void:
	if is_open:
		_status_time.text = Time.get_time_string_from_system().substr(0, 5)
	if _call_timer and _call_timer.visible and Session.call_state == "active":
		_call_timer.text = Valet._fmt(Session.call_duration())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("phone"):
		toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and is_open:
		close()
		get_viewport().set_input_as_handled()


func _ensure_input_action() -> void:
	if not InputMap.has_action("phone"):
		InputMap.add_action("phone")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_P
		InputMap.action_add_event("phone", ev)
		var ev2 := InputEventKey.new()
		ev2.keycode = KEY_P
		InputMap.action_add_event("phone", ev2)


# ============================================================ public API
func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open(page := "home") -> void:
	if not is_open:
		is_open = true
		_dock.visible = true
		_animate(true)
		phone_toggled.emit(true)
	show_page(page)


func close() -> void:
	if not is_open:
		return
	is_open = false
	_animate(false)
	phone_toggled.emit(false)


## Adds a notification. kind: system | job | property | vehicle | market | clan | rank | invite
func notify(title: String, body: String, kind := "system", actions: Array = []) -> void:
	var n := {"title": title, "body": body, "kind": kind, "time": Time.get_time_string_from_system().substr(0, 5), "actions": actions}
	notifications.push_front(n)
	if notifications.size() > 40:
		notifications.resize(40)
	unread += 1
	_toast(title, body, _kind_color(kind))
	_update_badges()
	_refresh_if_open(["home", "notifications"])


## Battle / tournament / clan-war invitations land on the phone and are answered there.
func invite(kind: String, title: String, body: String) -> void:
	var inv := {"kind": kind, "title": title, "body": body}
	_pending_invites.append(inv)
	notify(title, body + "  Open the phone to accept or decline.", "invite")


## Rings the phone. On answer the caller's line plays with a typewriter; action_label/action_page
## optionally adds a button that jumps straight into an app (e.g. "Open Job Board").
func incoming_call(contact_id: String, line: String, action_label := "", action_page := "") -> void:
	if not PhoneData.CONTACTS.has(contact_id):
		return
	Globalvar.add_contact(contact_id)
	_active_call = {"kind": "npc", "contact": contact_id, "line": line, "action_label": action_label, "action_page": action_page, "incoming": true}
	_show_call_overlay()


func set_destination(position: Vector3, label: String, job_id := "") -> void:
	clear_destination()
	Globalvar.set_destination(position, label)
	_gps_job_id = job_id
	var scene := get_tree().current_scene
	if scene:
		_marker = GpsMarker.new()
		_marker.label_text = label.to_upper()
		scene.add_child(_marker)
		_marker.global_position = position
		_marker.arrived.connect(_on_marker_arrived)
	destination_set.emit(position, label)
	_refresh_if_open(["gps", "jobs"])


func clear_destination() -> void:
	if is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null
	_gps_job_id = ""
	Globalvar.clear_destination()
	destination_cleared.emit()
	_refresh_if_open(["gps"])


# ============================================================ build
func _build() -> void:
	# On-screen phone button (bottom-right).
	_phone_button = PhoneTheme.button("PHONE  [P]", PhoneTheme.FRAME_BG, 15, 44)
	_phone_button.pressed.connect(toggle)
	add_child(_phone_button)
	_phone_button.anchor_left = 1.0
	_phone_button.anchor_right = 1.0
	_phone_button.anchor_top = 1.0
	_phone_button.anchor_bottom = 1.0
	_phone_button.offset_left = -160
	_phone_button.offset_right = -16
	_phone_button.offset_top = -60
	_phone_button.offset_bottom = -16
	_status_badge = PhoneTheme.label("", 11, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var badge := PhoneTheme.panel(PhoneTheme.RED, 10, PhoneTheme.RED, 3)
	badge.add_child(_status_badge)
	badge.name = "Badge"
	_phone_button.add_child(badge)
	badge.position = Vector2(118, -10)
	badge.visible = false

	# Toasts (top-centre).
	_toast_box = PhoneTheme.vbox(6)
	add_child(_toast_box)
	_toast_box.anchor_left = 0.5
	_toast_box.anchor_right = 0.5
	_toast_box.offset_left = -220
	_toast_box.offset_right = 220
	_toast_box.offset_top = 12
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Dock + phone frame.
	_dock = Control.new()
	_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock.visible = false
	add_child(_dock)
	_dock.anchor_left = 1.0
	_dock.anchor_right = 1.0
	_dock.anchor_top = 1.0
	_dock.anchor_bottom = 1.0
	_dock.offset_left = -PHONE_SIZE.x - 16
	_dock.offset_right = -16
	_dock.offset_top = -PHONE_SIZE.y - 70
	_dock.offset_bottom = -70
	_phone = PhoneTheme.panel(PhoneTheme.FRAME_BG, 32, Color(0.32, 0.32, 0.34, 1.0), 9)
	_phone.custom_minimum_size = PHONE_SIZE
	_phone.size = PHONE_SIZE
	_dock.add_child(_phone)
	var screen := PhoneTheme.panel(PhoneTheme.SCREEN_BG, 24, Color(0, 0, 0, 0.0), 0)
	screen.clip_contents = true
	_phone.add_child(screen)
	_screen = PhoneTheme.vbox(0)
	screen.add_child(_screen)

	# Status bar.
	var status_pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		status_pad.add_theme_constant_override(side, 16)
	status_pad.add_theme_constant_override("margin_top", 10)
	status_pad.add_theme_constant_override("margin_bottom", 4)
	_screen.add_child(status_pad)
	var status := PhoneTheme.hbox(8)
	status_pad.add_child(status)
	_status_time = PhoneTheme.label("00:00", 13)
	status.add_child(_status_time)
	status.add_child(PhoneTheme.spacer())
	status.add_child(PhoneTheme.label("AETHERIS NET", 11, PhoneTheme.TEXT_DIM))
	status.add_child(PhoneTheme.spacer())
	_status_rank = PhoneTheme.label("RANK D", 12, PhoneTheme.TEXT_DIM)
	status.add_child(_status_rank)

	_page_host = Control.new()
	_page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_host.clip_contents = true
	_screen.add_child(_page_host)
	for p in ["home", "jobs", "property", "vehicle", "market", "clan", "gps", "stats", "contacts", "messages", "notifications"]:
		var page := PhoneTheme.vbox(0)
		page.visible = false
		_page_host.add_child(page)
		PhoneTheme.full_rect(page)
		_pages[p] = page

	# Home bar.
	var home_wrap := Control.new()
	home_wrap.custom_minimum_size = Vector2(0, 30)
	var pill := ColorRect.new()
	pill.color = Color(0, 0, 0, 0.22)
	pill.custom_minimum_size = Vector2(100, 5)
	var centre := CenterContainer.new()
	centre.add_child(pill)
	home_wrap.add_child(centre)
	PhoneTheme.full_rect(centre)
	var home_btn := Button.new()
	home_btn.flat = true
	home_btn.focus_mode = Control.FOCUS_NONE
	home_btn.pressed.connect(func() -> void: show_page("home"))
	home_wrap.add_child(home_btn)
	PhoneTheme.full_rect(home_btn)
	_screen.add_child(home_wrap)

	_build_call_overlay()
	_layout()
	get_tree().root.size_changed.connect(_layout)
	_phone.position.y = PHONE_SIZE.y + 100
	_phone.modulate.a = 0.0


## Fits the phone to the window: full size on desktop, shorter on small viewports.
func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var h := minf(PHONE_MAX_SIZE.y, vp.y - DOCK_BOTTOM - 12.0)
	PHONE_SIZE = Vector2(PHONE_MAX_SIZE.x, maxf(h, 360.0))
	_phone.custom_minimum_size = PHONE_SIZE
	_phone.size = PHONE_SIZE
	_dock.offset_left = -PHONE_SIZE.x - 16
	_dock.offset_top = -PHONE_SIZE.y - DOCK_BOTTOM
	_dock.offset_bottom = -DOCK_BOTTOM


func _build_call_overlay() -> void:
	_call_overlay = Control.new()
	_call_overlay.visible = false
	add_child(_call_overlay)
	PhoneTheme.full_rect(_call_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	_call_overlay.add_child(dim)
	PhoneTheme.full_rect(dim)
	var centre := CenterContainer.new()
	_call_overlay.add_child(centre)
	PhoneTheme.full_rect(centre)
	var card := PhoneTheme.panel(PhoneTheme.CARD_BG, 28, Color(0, 0, 0, 0.12), 24)
	card.custom_minimum_size = Vector2(440, 0)
	centre.add_child(card)
	var v := PhoneTheme.vbox(10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(v)
	var avatar_centre := CenterContainer.new()
	_call_avatar = PhoneTheme.panel(Color(PhoneTheme.ACCENT.r, PhoneTheme.ACCENT.g, PhoneTheme.ACCENT.b, 0.2), 44, PhoneTheme.ACCENT, 0)
	_call_avatar.custom_minimum_size = Vector2(88, 88)
	var initials := PhoneTheme.label("", 32, PhoneTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	initials.name = "Initials"
	initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_call_avatar.add_child(initials)
	avatar_centre.add_child(_call_avatar)
	v.add_child(avatar_centre)
	_call_state = PhoneTheme.label("INCOMING CALL", 11, PhoneTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_call_state)
	_call_name = PhoneTheme.label("", 24, PhoneTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_call_name)
	_call_role = PhoneTheme.label("", 13, PhoneTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_call_role)
	_call_timer = PhoneTheme.label("0:00", 20, PhoneTheme.GREEN, HORIZONTAL_ALIGNMENT_CENTER)
	_call_timer.visible = false
	v.add_child(_call_timer)
	_call_meter = PhoneTheme.progress(0.0, PhoneTheme.GREEN, 8)
	_call_meter.custom_minimum_size = Vector2(260, 8)
	_call_meter.visible = false
	var meter_centre := CenterContainer.new()
	meter_centre.add_child(_call_meter)
	v.add_child(meter_centre)
	_call_text = PhoneTheme.wrapped("", 14, PhoneTheme.TEXT)
	_call_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_call_text.custom_minimum_size = Vector2(390, 0)
	v.add_child(_call_text)
	_call_panel = PhoneTheme.vbox(6)
	_call_panel.custom_minimum_size = Vector2(390, 0)
	v.add_child(_call_panel)
	_call_actions = PhoneTheme.hbox(10)
	_call_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(_call_actions)


# ============================================================ open/close animation
func _animate(opening: bool) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_phone, "position:y", 0.0 if opening else PHONE_SIZE.y + 100.0, 0.36).set_trans(Tween.TRANS_BACK if opening else Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT if opening else Tween.EASE_IN)
	_tween.tween_property(_phone, "modulate:a", 1.0 if opening else 0.0, 0.25)
	if not opening:
		_tween.chain().tween_callback(func() -> void: _dock.visible = false)


func _toast(title: String, body: String, color: Color) -> void:
	var p := PhoneTheme.panel(PhoneTheme.CARD_BG, 10, Color(color.r, color.g, color.b, 0.6), 10)
	var v := PhoneTheme.vbox(2)
	v.add_child(PhoneTheme.label(title, 14, color))
	v.add_child(PhoneTheme.wrapped(body, 12, PhoneTheme.TEXT))
	p.add_child(v)
	p.modulate.a = 0.0
	_toast_box.add_child(p)
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(3.5)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


func _update_badges() -> void:
	var badge := _phone_button.get_node("Badge") as PanelContainer
	badge.visible = unread > 0
	_status_badge.text = str(unread)


func _kind_color(kind: String) -> Color:
	match kind:
		"job": return PhoneTheme.ACCENT
		"property": return PhoneTheme.GOLD
		"vehicle": return PhoneTheme.AMBER
		"market": return PhoneTheme.GREEN
		"clan": return PhoneTheme.ACCENT2
		"rank": return PhoneTheme.GOLD
		"invite": return PhoneTheme.RED
		"message": return PhoneTheme.ACCENT2
		"call": return PhoneTheme.GREEN
	return PhoneTheme.TEXT_DIM


# ============================================================ pages
func show_page(page: String) -> void:
	for n in _pages:
		_pages[n].visible = n == page
	_rebuild(page)
	_status_rank.text = "RANK %s" % Globalvar.current_rank
	_status_rank.add_theme_color_override("font_color", PhoneTheme.rank_color(Globalvar.current_rank))
	if page == "notifications":
		unread = 0
		_update_badges()


func _refresh_if_open(pages: Array) -> void:
	if not is_open:
		return
	for p in pages:
		if _pages.has(p) and _pages[p].visible:
			_rebuild(p)


func _rebuild(page: String) -> void:
	var host: VBoxContainer = _pages[page]
	for c in host.get_children():
		host.remove_child(c)
		c.queue_free()
	match page:
		"home": _build_home(host)
		"jobs": _build_jobs(host)
		"property": _build_property(host)
		"vehicle": _build_vehicle(host)
		"market": _build_market(host)
		"clan": _build_clan(host)
		"gps": _build_gps(host)
		"stats": _build_stats(host)
		"contacts": _build_contacts(host)
		"messages": _build_messages(host)
		"notifications": _build_notifications(host)


func _header(page: VBoxContainer, title: String, subtitle: String) -> void:
	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 16)
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", 8)
	page.add_child(pad)
	var row := PhoneTheme.hbox(10)
	pad.add_child(row)
	var back := PhoneTheme.button("<", PhoneTheme.TEXT_DIM, 16, 34)
	back.custom_minimum_size = Vector2(40, 34)
	back.pressed.connect(func() -> void: show_page("home"))
	row.add_child(back)
	var col := PhoneTheme.vbox(0)
	col.add_child(PhoneTheme.label(title, 20))
	col.add_child(PhoneTheme.label(subtitle, 11, PhoneTheme.TEXT_DIM))
	row.add_child(col)


func _scroll(page: VBoxContainer) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(sc)
	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 14)
	pad.add_theme_constant_override("margin_bottom", 10)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(pad)
	var list := PhoneTheme.vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(list)
	return list


func _card(list: VBoxContainer, border: Color = PhoneTheme.LINE) -> VBoxContainer:
	var p := PhoneTheme.panel(PhoneTheme.CARD_BG, 14, border, 12)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := PhoneTheme.vbox(6)
	p.add_child(v)
	list.add_child(p)
	return v


func _chips(parent: VBoxContainer, options: Array, current: String, on_pick: Callable) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	for opt in options:
		var b := PhoneTheme.button(str(opt), PhoneTheme.ACCENT if str(opt) == current else PhoneTheme.TEXT_DIM, 12, 28)
		var value := str(opt)
		b.pressed.connect(func() -> void: on_pick.call(value))
		row.add_child(b)
	parent.add_child(row)


# ---- Home
func _build_home(page: VBoxContainer) -> void:
	var list := _scroll(page)
	var greet := _card(list, Color(PhoneTheme.ACCENT2.r, PhoneTheme.ACCENT2.g, PhoneTheme.ACCENT2.b, 0.45))
	greet.add_child(PhoneTheme.label("OBSIDIAN OS", 11, PhoneTheme.ACCENT2))
	greet.add_child(PhoneTheme.label("%s  -  Rank %s" % [Globalvar.player_name, Globalvar.current_rank], 20))
	greet.add_child(PhoneTheme.label("%s credits  |  %s renown  |  %s points" % [PhoneTheme.fmt_int(Globalvar.current_credits), PhoneTheme.fmt_int(Globalvar.current_renown), PhoneTheme.fmt_int(Globalvar.current_points)], 12, PhoneTheme.TEXT_DIM))
	if Globalvar.active_job_id != "":
		greet.add_child(PhoneTheme.label("Active job: %s  (%d/%d)" % [Globalvar.active_job_title, Globalvar.active_job_progress, Globalvar.active_job_target], 12, PhoneTheme.ACCENT))
	if Globalvar.has_destination:
		greet.add_child(PhoneTheme.label("GPS: %s" % Globalvar.destination_label, 12, PhoneTheme.GREEN))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	list.add_child(grid)
	for app in APPS:
		var col := PhoneTheme.vbox(4)
		var b := PhoneTheme.button(app[1], PhoneTheme.tile_color(app[0]), 14, 70)
		b.custom_minimum_size = Vector2(100, 70)
		var page_name: String = app[0]
		b.pressed.connect(func() -> void: show_page(page_name))
		col.add_child(b)
		col.add_child(PhoneTheme.label(app[2], 11, PhoneTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
		grid.add_child(col)
	var notif_btn := PhoneTheme.button("Notifications  (%d new)" % unread if unread > 0 else "Notifications", PhoneTheme.TEXT_DIM, 13, 36)
	if unread > 0:
		notif_btn.add_theme_color_override("font_color", PhoneTheme.RED)
		notif_btn.add_theme_color_override("font_hover_color", PhoneTheme.RED)
	notif_btn.pressed.connect(func() -> void: show_page("notifications"))
	list.add_child(notif_btn)
	if not _pending_invites.is_empty():
		var inv := _pending_invites[0]
		var c := _card(list, PhoneTheme.RED)
		c.add_child(PhoneTheme.label("INVITATION", 11, PhoneTheme.RED))
		c.add_child(PhoneTheme.label(inv["title"], 15))
		c.add_child(PhoneTheme.wrapped(inv["body"], 12))
		var row := PhoneTheme.hbox(8)
		var acc := PhoneTheme.button("Accept", PhoneTheme.GREEN, 13, 32)
		acc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		acc.pressed.connect(func() -> void: _answer_invite(inv, true))
		var dec := PhoneTheme.button("Decline", PhoneTheme.RED, 13, 32)
		dec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dec.pressed.connect(func() -> void: _answer_invite(inv, false))
		row.add_child(acc)
		row.add_child(dec)
		c.add_child(row)


func _answer_invite(inv: Dictionary, accepted: bool) -> void:
	_pending_invites.erase(inv)
	invitation_answered.emit(inv["kind"], accepted)
	notify(inv["title"], "Accepted. Your match is ready - follow the markers to your portal. Good luck!" if accepted else "Declined.", "invite")
	_refresh_if_open(["home"])


# ---- Job Board
func _job_distance(job: QuestData) -> float:
	var player := get_tree().get_first_node_in_group("players") as Node3D
	if player and job.has_location:
		var d: Vector3 = job.location - player.global_position
		d.y = 0.0
		return d.length()
	return float(job.distance_m)


func _build_jobs(page: VBoxContainer) -> void:
	_header(page, "Job Board", "Every job available in the city")
	var list := _scroll(page)
	if Globalvar.active_job_id != "":
		var job: QuestData = JobManager.jobs[Globalvar.active_job_id]
		var c := _card(list, PhoneTheme.ACCENT)
		c.add_child(PhoneTheme.label("ACTIVE JOB", 11, PhoneTheme.ACCENT))
		c.add_child(PhoneTheme.label(job.title, 17))
		c.add_child(PhoneTheme.wrapped(job.description, 12))
		c.add_child(PhoneTheme.label("Progress %d / %d" % [Globalvar.active_job_progress, Globalvar.active_job_target], 12, PhoneTheme.TEXT))
		c.add_child(PhoneTheme.progress(float(Globalvar.active_job_progress) / maxf(1.0, float(Globalvar.active_job_target)), PhoneTheme.ACCENT, 8))
		var row := PhoneTheme.hbox(8)
		if job.has_location:
			var nav := PhoneTheme.button("GPS to job", PhoneTheme.GREEN, 12, 30)
			nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nav.pressed.connect(func() -> void: set_destination(job.location, job.title, Globalvar.active_job_id))
			row.add_child(nav)
		var cancel := PhoneTheme.button("Cancel", PhoneTheme.RED, 12, 30)
		cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cancel.pressed.connect(func() -> void:
			JobManager.cancel_job()
			clear_destination()
			_rebuild("jobs"))
		row.add_child(cancel)
		c.add_child(row)
	var filt := PhoneTheme.vbox(4)
	filt.add_child(PhoneTheme.label("SORT BY", 10, PhoneTheme.TEXT_DIM))
	_chips(filt, ["pay", "distance", "duration"], _job_sort, func(v: String) -> void:
		_job_sort = v
		_rebuild("jobs"))
	filt.add_child(PhoneTheme.label("TYPE", 10, PhoneTheme.TEXT_DIM))
	_chips(filt, ["All", "Delivery", "Moving", "Foundry", "Combat"], _job_type, func(v: String) -> void:
		_job_type = v
		_rebuild("jobs"))
	list.add_child(filt)
	var ids: Array = JobManager.available_jobs()
	if _job_type != "All":
		ids = ids.filter(func(id: String) -> bool: return JobManager.jobs[id].job_type == _job_type)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ja: QuestData = JobManager.jobs[a]
		var jb: QuestData = JobManager.jobs[b]
		match _job_sort:
			"distance": return _job_distance(ja) < _job_distance(jb)
			"duration": return ja.duration_min < jb.duration_min
		return ja.pay > jb.pay)
	if ids.is_empty():
		list.add_child(PhoneTheme.wrapped("No jobs match. New offers arrive by notification.", 13))
	for id in ids:
		var job: QuestData = JobManager.jobs[id]
		var c := _card(list)
		var top := PhoneTheme.hbox(8)
		top.add_child(PhoneTheme.label(job.title, 16))
		top.add_child(PhoneTheme.spacer())
		top.add_child(PhoneTheme.tag(job.job_type, PhoneTheme.ACCENT2, 10))
		c.add_child(top)
		c.add_child(PhoneTheme.label(job.client, 11, PhoneTheme.ACCENT))
		c.add_child(PhoneTheme.wrapped(job.description, 12))
		var tags := HFlowContainer.new()
		tags.add_theme_constant_override("h_separation", 6)
		tags.add_child(PhoneTheme.tag("%s cr  (pays %s now)" % [PhoneTheme.fmt_int(job.pay), PhoneTheme.fmt_int(JobManager.job_pay(id))], PhoneTheme.GOLD, 10))
		tags.add_child(PhoneTheme.tag("%d m" % int(_job_distance(job)), PhoneTheme.TEXT_DIM, 10))
		tags.add_child(PhoneTheme.tag("~%d min" % job.duration_min, PhoneTheme.TEXT_DIM, 10))
		tags.add_child(PhoneTheme.tag("+%d renown" % job.renown_reward, PhoneTheme.ACCENT2, 10))
		c.add_child(tags)
		var apply := PhoneTheme.button("Apply", PhoneTheme.ACCENT, 13, 34)
		apply.disabled = Globalvar.active_job_id != ""
		var jid: String = id
		apply.pressed.connect(func() -> void:
			if JobManager.accept_job(jid):
				_rebuild("jobs"))
		c.add_child(apply)


func _on_job_accepted(job_id: String) -> void:
	var job: QuestData = JobManager.jobs[job_id]
	notify("Application accepted", "%s - your GPS is guiding you to the location." % job.title, "job")
	if job.has_location:
		set_destination(job.location, job.title, job_id)


func _on_job_completed(job_id: String) -> void:
	var job: QuestData = JobManager.jobs[job_id]
	notify("Job complete: %s" % job.title, "+%s credits  +%d renown  +%d points" % [PhoneTheme.fmt_int(JobManager.last_payout), job.renown_reward, job.credits_reward], "job")
	if _gps_job_id == job_id:
		clear_destination()
	_refresh_if_open(["jobs", "home"])


func _on_marker_arrived() -> void:
	var label := Globalvar.destination_label
	var job_id := _gps_job_id
	clear_destination()
	notify("You have arrived", label, "system")
	if job_id != "" and Globalvar.active_job_id == job_id:
		JobManager.add_job_progress(1)


# ---- Property
func _build_property(page: VBoxContainer) -> void:
	_header(page, "Property", "The Heights - rentals, homes and plots")
	var list := _scroll(page)
	list.add_child(PhoneTheme.label("Wallet: %s credits" % PhoneTheme.fmt_int(Globalvar.current_credits), 13, PhoneTheme.GOLD))
	for prop in PhoneData.PROPERTIES:
		var pid: String = prop["id"]
		var owned: bool = Globalvar.owned_properties.has(pid)
		var rented: bool = Globalvar.rented_property == pid
		var c := _card(list, PhoneTheme.GREEN if (owned or rented) else PhoneTheme.LINE)
		var row := PhoneTheme.hbox(10)
		var photo := PhoneTheme.panel(prop["color"], 10, Color(1, 1, 1, 0.1), 0)
		photo.custom_minimum_size = Vector2(72, 54)
		var pl := PhoneTheme.label(prop["type"].substr(0, 1), 24, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
		pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		photo.add_child(pl)
		row.add_child(photo)
		var col := PhoneTheme.vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(PhoneTheme.label(prop["name"], 16))
		col.add_child(PhoneTheme.label("%s  |  %s" % [prop["type"], prop["district"]], 11, PhoneTheme.ACCENT))
		col.add_child(PhoneTheme.label(prop["size"], 11, PhoneTheme.TEXT_DIM))
		row.add_child(col)
		c.add_child(row)
		c.add_child(PhoneTheme.wrapped(prop["desc"], 12))
		var is_rental: bool = int(prop["rent"]) > 0
		var price: int = int(prop["rent"]) if is_rental else int(prop["price"])
		if owned:
			c.add_child(PhoneTheme.tag("OWNED", PhoneTheme.GREEN, 11))
			continue
		if rented:
			c.add_child(PhoneTheme.tag("RENTED  -  %s cr / month" % PhoneTheme.fmt_int(price), PhoneTheme.GREEN, 11))
			continue
		if _confirm_id == pid:
			c.add_child(PhoneTheme.wrapped("Confirm %s of %s for %s credits%s?" % ["rental" if is_rental else "purchase", prop["name"], PhoneTheme.fmt_int(price), " (first month)" if is_rental else ""], 12, PhoneTheme.TEXT))
			var r := PhoneTheme.hbox(8)
			var yes := PhoneTheme.button("Confirm", PhoneTheme.GREEN, 13, 32)
			yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			yes.pressed.connect(func() -> void:
				_confirm_id = ""
				_buy_property(pid, is_rental, price))
			var no := PhoneTheme.button("Back", PhoneTheme.TEXT_DIM, 13, 32)
			no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			no.pressed.connect(func() -> void:
				_confirm_id = ""
				_rebuild("property"))
			r.add_child(yes)
			r.add_child(no)
			c.add_child(r)
		else:
			var label: String = ("Apply to rent  %s cr / month" if is_rental else "Buy  %s cr") % PhoneTheme.fmt_int(price)
			var b := PhoneTheme.button(label, PhoneTheme.GOLD, 13, 34)
			b.disabled = Globalvar.current_credits < price
			if b.disabled:
				b.text += "   (need %s more)" % PhoneTheme.fmt_int(price - Globalvar.current_credits)
			b.pressed.connect(func() -> void:
				_confirm_id = pid
				_rebuild("property"))
			c.add_child(b)


func _buy_property(pid: String, is_rental: bool, price: int) -> void:
	if not Globalvar.spend_credits(price):
		_rebuild("property")
		return
	var prop := PhoneData.property(pid)
	if is_rental:
		Globalvar.rented_property = pid
	else:
		Globalvar.owned_properties.append(pid)
	Globalvar.add_contact("housing_agent")
	purchase_made.emit("property", pid)
	notify("Property %s" % ("rented" if is_rental else "purchased"), "%s is yours. Your agent will call to arrange the next steps." % prop["name"], "property")
	_rebuild("property")
	var line: String
	if prop["type"] == "Plot":
		line = "Congratulations on the plot! Let's design your home step by step - style, rooms, garage, garden, pool. Every choice shows its cost and construction starts the moment you confirm."
		get_tree().create_timer(45.0).timeout.connect(func() -> void:
			notify("Home construction complete", "%s - the doors are open. Walk through room by room and furnish it." % prop["name"], "property")
			incoming_call("housing_agent", "The doors are open at %s. Come see it whenever you're ready." % prop["name"], "Set GPS", "gps"))
	else:
		line = "Welcome home! %s is ready. I've marked it on your GPS - drive straight into the garage and walk in." % prop["name"]
	get_tree().create_timer(3.0).timeout.connect(func() -> void: incoming_call("housing_agent", line, "Set GPS", "gps"))


# ---- Vehicle
func _build_vehicle(page: VBoxContainer) -> void:
	_header(page, "Vehicle", "Velocity Quarter - full collection")
	var list := _scroll(page)
	list.add_child(PhoneTheme.label("Wallet: %s credits" % PhoneTheme.fmt_int(Globalvar.current_credits), 13, PhoneTheme.GOLD))
	if not Globalvar.owned_vehicles.is_empty():
		var valet_btn := PhoneTheme.button("Call Rook  -  valet & mechanic", PhoneTheme.AMBER, 13, 34)
		valet_btn.pressed.connect(func() -> void: call_contact("mechanic"))
		list.add_child(valet_btn)
	for v in PhoneData.VEHICLES:
		var vid: String = v["id"]
		var owned: bool = Globalvar.owned_vehicles.has(vid)
		var c := _card(list, PhoneTheme.GREEN if owned else PhoneTheme.LINE)
		var top := PhoneTheme.hbox(8)
		top.add_child(PhoneTheme.label(v["name"], 16))
		top.add_child(PhoneTheme.spacer())
		top.add_child(PhoneTheme.tag(v["class"], PhoneTheme.AMBER, 10))
		c.add_child(top)
		c.add_child(PhoneTheme.wrapped(v["desc"], 12))
		var spec := HFlowContainer.new()
		spec.add_theme_constant_override("h_separation", 6)
		spec.add_child(PhoneTheme.tag("Top %d mph" % int(v["top_speed"]), PhoneTheme.TEXT_DIM, 10))
		spec.add_child(PhoneTheme.tag("0-60  %s" % v["accel"], PhoneTheme.TEXT_DIM, 10))
		spec.add_child(PhoneTheme.tag("%s cr" % PhoneTheme.fmt_int(int(v["price"])), PhoneTheme.GOLD, 10))
		c.add_child(spec)
		if owned:
			var orow := PhoneTheme.hbox(6)
			orow.add_child(PhoneTheme.tag("OWNED  -  %s" % Globalvar.vehicle_colors.get(vid, v["colors"][0]), PhoneTheme.GREEN, 11))
			var st: String = Valet.status(vid)
			orow.add_child(PhoneTheme.tag(st, PhoneTheme.RED if "damaged" in st else PhoneTheme.TEXT_DIM, 10))
			c.add_child(orow)
			continue
		var colors: Array = v["colors"]
		var chosen: String = _vehicle_color.get(vid, colors[0])
		_chips(c, colors, chosen, func(col: String) -> void:
			_vehicle_color[vid] = col
			_rebuild("vehicle"))
		var price: int = int(v["price"])
		if _confirm_id == vid:
			c.add_child(PhoneTheme.wrapped("Buy %s in %s for %s credits. Delivery option:" % [v["name"], chosen, PhoneTheme.fmt_int(price)], 12, PhoneTheme.TEXT))
			var r := PhoneTheme.hbox(8)
			var deliver := PhoneTheme.button("Deliver to driveway", PhoneTheme.GREEN, 12, 32)
			deliver.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			deliver.pressed.connect(func() -> void: _buy_vehicle(vid, price, chosen, true))
			var collect := PhoneTheme.button("Collect at dealer", PhoneTheme.ACCENT, 12, 32)
			collect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			collect.pressed.connect(func() -> void: _buy_vehicle(vid, price, chosen, false))
			r.add_child(deliver)
			r.add_child(collect)
			c.add_child(r)
			var back := PhoneTheme.button("Back", PhoneTheme.TEXT_DIM, 12, 28)
			back.pressed.connect(func() -> void:
				_confirm_id = ""
				_rebuild("vehicle"))
			c.add_child(back)
		else:
			var b := PhoneTheme.button("Buy  %s cr" % PhoneTheme.fmt_int(price), PhoneTheme.AMBER, 13, 34)
			b.disabled = Globalvar.current_credits < price
			if b.disabled:
				b.text += "   (need %s more)" % PhoneTheme.fmt_int(price - Globalvar.current_credits)
			b.pressed.connect(func() -> void:
				_confirm_id = vid
				_rebuild("vehicle"))
			c.add_child(b)


func _buy_vehicle(vid: String, price: int, color: String, deliver: bool) -> void:
	_confirm_id = ""
	if not Globalvar.spend_credits(price):
		_rebuild("vehicle")
		return
	Globalvar.owned_vehicles.append(vid)
	_vehicle_color[vid] = color
	Globalvar.vehicle_colors[vid] = color
	Globalvar.add_contact("vehicle_dealer")
	Globalvar.add_contact("mechanic")
	purchase_made.emit("vehicle", vid)
	var v := PhoneData.vehicle(vid)
	_rebuild("vehicle")
	if deliver:
		notify("Vehicle ordered", "%s (%s) - Rook's valet is bringing it to you." % [v["name"], color], "vehicle")
		get_tree().create_timer(1.5).timeout.connect(func() -> void: Valet.request(vid))
	else:
		notify("Vehicle reserved", "%s (%s) is ready to collect at Velocity Quarter." % [v["name"], color], "vehicle")
		var dest := PhoneData.DESTINATIONS[4]
		set_destination(dest["position"], "Collect %s" % v["name"])


# ---- Market
func _build_market(page: VBoxContainer) -> void:
	_header(page, "Market", "The Foundry - weapons, clothing, decor, supplies")
	var list := _scroll(page)
	list.add_child(PhoneTheme.label("Wallet: %s credits" % PhoneTheme.fmt_int(Globalvar.current_credits), 13, PhoneTheme.GOLD))
	_chips(list, PhoneData.MARKET_CATEGORIES, _market_category, func(v: String) -> void:
		_market_category = v
		_rebuild("market"))
	for item in PhoneData.MARKET:
		if _market_category != "All" and item["category"] != _market_category:
			continue
		var iid: String = item["id"]
		var stock: int = Globalvar.market_stock.get(iid, int(item["stock"]))
		var c := _card(list)
		var top := PhoneTheme.hbox(8)
		top.add_child(PhoneTheme.label(item["name"], 15))
		top.add_child(PhoneTheme.spacer())
		top.add_child(PhoneTheme.tag(item["category"], PhoneTheme.GREEN, 10))
		c.add_child(top)
		c.add_child(PhoneTheme.wrapped(item["desc"], 12))
		var row := PhoneTheme.hbox(6)
		row.add_child(PhoneTheme.tag("%s cr" % PhoneTheme.fmt_int(int(item["price"])), PhoneTheme.GOLD, 10))
		row.add_child(PhoneTheme.tag("Stock %d" % stock if stock > 0 else "OUT OF STOCK", PhoneTheme.TEXT_DIM if stock > 0 else PhoneTheme.RED, 10))
		var owned_count: int = Globalvar.inventory_items.count(iid)
		if owned_count > 0:
			row.add_child(PhoneTheme.tag("Owned x%d" % owned_count, PhoneTheme.GREEN, 10))
		c.add_child(row)
		var price: int = int(item["price"])
		var r := PhoneTheme.hbox(8)
		var collect := PhoneTheme.button("Order - collect", PhoneTheme.GREEN, 12, 32)
		collect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		collect.disabled = stock <= 0 or Globalvar.current_credits < price
		collect.pressed.connect(func() -> void: _order_item(iid, price, false))
		var deliver := PhoneTheme.button("Order - deliver", PhoneTheme.ACCENT, 12, 32)
		deliver.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		deliver.disabled = collect.disabled or (Globalvar.owned_properties.is_empty() and Globalvar.rented_property == "")
		deliver.tooltip_text = "Delivery needs a home address"
		deliver.pressed.connect(func() -> void: _order_item(iid, price, true))
		r.add_child(collect)
		r.add_child(deliver)
		c.add_child(r)


func _order_item(iid: String, price: int, deliver: bool) -> void:
	if not Globalvar.spend_credits(price):
		return
	var item := PhoneData.market_item(iid)
	Globalvar.market_stock[iid] = Globalvar.market_stock.get(iid, int(item["stock"])) - 1
	Globalvar.inventory_items.append(iid)
	Globalvar.add_contact("foundry")
	purchase_made.emit("market", iid)
	notify("Order placed", "%s - %s." % [item["name"], "delivery to your home within the hour" if deliver else "ready to collect at The Foundry"], "market")
	if not deliver:
		var dest := PhoneData.DESTINATIONS[3]
		set_destination(dest["position"], "Collect %s" % item["name"])
	_rebuild("market")


# ---- Clan Hub
func _build_clan(page: VBoxContainer) -> void:
	_header(page, "Clan Hub", "%s  -  led by %s" % [PhoneData.CLAN["name"], PhoneData.CLAN["leader"]])
	var list := _scroll(page)
	var me := _card(list, PhoneTheme.ACCENT2)
	me.add_child(PhoneTheme.label("YOUR STANDING", 11, PhoneTheme.ACCENT2))
	var nxt: int = _next_threshold()
	me.add_child(PhoneTheme.label("Rank %s  -  %s renown" % [Globalvar.current_rank, PhoneTheme.fmt_int(Globalvar.current_renown)], 15))
	me.add_child(PhoneTheme.progress(_rank_progress(), PhoneTheme.rank_color(Globalvar.current_rank), 8))
	me.add_child(PhoneTheme.label(("%s / %s to next rank" % [PhoneTheme.fmt_int(Globalvar.current_renown), PhoneTheme.fmt_int(nxt)]) if nxt > 0 else "Top rank reached", 11, PhoneTheme.TEXT_DIM))
	me.add_child(PhoneTheme.label("Reputation %d / 100" % Globalvar.current_reputation, 12, PhoneTheme.GREEN if Globalvar.current_reputation >= 50 else PhoneTheme.RED))
	var msgs := _card(list)
	msgs.add_child(PhoneTheme.label("FROM YOUR CLAN LEADER", 11, PhoneTheme.TEXT_DIM))
	for m in PhoneData.CLAN["messages"]:
		msgs.add_child(PhoneTheme.wrapped("-  " + m, 12, PhoneTheme.TEXT))
	var call_btn := PhoneTheme.button("Call %s" % PhoneData.CLAN["leader"], PhoneTheme.ACCENT2, 12, 30)
	call_btn.pressed.connect(func() -> void: call_contact("clan_leader"))
	msgs.add_child(call_btn)
	var members := _card(list)
	members.add_child(PhoneTheme.label("MEMBERS", 11, PhoneTheme.TEXT_DIM))
	for mem in PhoneData.CLAN["members"]:
		var row := PhoneTheme.hbox(8)
		var dot := ColorRect.new()
		dot.color = PhoneTheme.GREEN if mem["online"] else Color(0.72, 0.73, 0.76)
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		row.add_child(PhoneTheme.label(mem["name"], 13))
		row.add_child(PhoneTheme.spacer())
		row.add_child(PhoneTheme.label("%s  -  Rank %s" % [mem["class"], mem["rank"]], 11, PhoneTheme.TEXT_DIM))
		members.add_child(row)
	var wars := _card(list, PhoneTheme.RED if not _pending_invites.is_empty() else PhoneTheme.LINE)
	wars.add_child(PhoneTheme.label("WAR INVITATIONS", 11, PhoneTheme.TEXT_DIM))
	if _pending_invites.is_empty():
		wars.add_child(PhoneTheme.wrapped("No pending invitations.", 12))
	for inv in _pending_invites:
		wars.add_child(PhoneTheme.label(inv["title"], 14))
		wars.add_child(PhoneTheme.wrapped(inv["body"], 12))
		var row := PhoneTheme.hbox(8)
		var acc := PhoneTheme.button("Accept", PhoneTheme.GREEN, 12, 30)
		acc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		acc.pressed.connect(func() -> void:
			_answer_invite(inv, true)
			_rebuild("clan"))
		var dec := PhoneTheme.button("Decline", PhoneTheme.RED, 12, 30)
		dec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dec.pressed.connect(func() -> void:
			_answer_invite(inv, false)
			_rebuild("clan"))
		row.add_child(acc)
		row.add_child(dec)
		wars.add_child(row)


# ---- GPS
func _build_gps(page: VBoxContainer) -> void:
	_header(page, "GPS", "Set a destination - your mini-map shows the route")
	var list := _scroll(page)
	if Globalvar.has_destination:
		var c := _card(list, PhoneTheme.GREEN)
		c.add_child(PhoneTheme.label("CURRENT ROUTE", 11, PhoneTheme.GREEN))
		c.add_child(PhoneTheme.label(Globalvar.destination_label, 15))
		var player := get_tree().get_first_node_in_group("players") as Node3D
		if player:
			var d: Vector3 = Globalvar.destination - player.global_position
			d.y = 0.0
			c.add_child(PhoneTheme.label("%d m away" % int(d.length()), 12, PhoneTheme.TEXT_DIM))
		var clear := PhoneTheme.button("Clear route", PhoneTheme.RED, 12, 30)
		clear.pressed.connect(func() -> void: clear_destination())
		c.add_child(clear)
	var dests: Array = PhoneData.DESTINATIONS.duplicate()
	for pid in Globalvar.owned_properties:
		var p := PhoneData.property(pid)
		dests.append({"id": pid, "name": "Home - %s" % p["name"], "position": p["position"]})
	if Globalvar.rented_property != "":
		var p := PhoneData.property(Globalvar.rented_property)
		dests.append({"id": p["id"], "name": "Home - %s" % p["name"], "position": p["position"]})
	if Globalvar.active_job_id != "" and JobManager.jobs.has(Globalvar.active_job_id) and JobManager.jobs[Globalvar.active_job_id].has_location:
		dests.append({"id": "job", "name": "Job - %s" % Globalvar.active_job_title, "position": JobManager.jobs[Globalvar.active_job_id].location})
	for d in dests:
		var row := PhoneTheme.hbox(8)
		row.add_child(PhoneTheme.label(d["name"], 13))
		row.add_child(PhoneTheme.spacer())
		var go := PhoneTheme.button("Go", PhoneTheme.ACCENT, 12, 28)
		go.custom_minimum_size = Vector2(56, 28)
		var pos: Vector3 = d["position"]
		var nm: String = d["name"]
		var jid: String = Globalvar.active_job_id if d["id"] == "job" else ""
		go.pressed.connect(func() -> void:
			set_destination(pos, nm, jid)
			_rebuild("gps"))
		row.add_child(go)
		list.add_child(row)


# ---- Stats & Wallet
func _build_stats(page: VBoxContainer) -> void:
	_header(page, "Stats & Wallet", "Rank, Renown, Points, credits, reputation")
	var list := _scroll(page)
	var rank: String = Globalvar.current_rank
	var color := PhoneTheme.rank_color(rank)
	var rc := _card(list, color)
	var row := PhoneTheme.hbox(14)
	var badge := PhoneTheme.panel(Color(color.r, color.g, color.b, 0.18), 36, color, 0)
	badge.custom_minimum_size = Vector2(72, 72)
	var big := PhoneTheme.label(rank, 34, color, HORIZONTAL_ALIGNMENT_CENTER)
	big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(big)
	row.add_child(badge)
	var col := PhoneTheme.vbox(3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(PhoneTheme.label("CURRENT RANK", 10, PhoneTheme.TEXT_DIM))
	col.add_child(PhoneTheme.label("Rank %s" % rank, 20))
	var nxt: int = _next_threshold()
	if nxt > 0:
		col.add_child(PhoneTheme.label("%s / %s renown to Rank %s" % [PhoneTheme.fmt_int(Globalvar.current_renown), PhoneTheme.fmt_int(nxt), _next_rank_name()], 11, PhoneTheme.TEXT_DIM))
		col.add_child(PhoneTheme.progress(_rank_progress(), color, 8))
	else:
		col.add_child(PhoneTheme.label("Rank S - top rank", 11, PhoneTheme.TEXT_DIM))
	row.add_child(col)
	rc.add_child(row)
	_stat_row(list, "Renown", PhoneTheme.fmt_int(Globalvar.current_renown), PhoneTheme.ACCENT2)
	_stat_row(list, "Points", PhoneTheme.fmt_int(Globalvar.current_points), PhoneTheme.ACCENT)
	_stat_row(list, "Credits", PhoneTheme.fmt_int(Globalvar.current_credits), PhoneTheme.GOLD)
	_stat_row(list, "Reputation", "%d / 100" % Globalvar.current_reputation, PhoneTheme.GREEN if Globalvar.current_reputation >= 50 else PhoneTheme.RED)
	_stat_row(list, "Class", Globalvar.current_class.capitalize(), PhoneTheme.TEXT)
	_stat_row(list, "Jobs completed", str(Globalvar.completed_jobs.size()), PhoneTheme.TEXT)
	_stat_row(list, "Properties", str(Globalvar.owned_properties.size() + (1 if Globalvar.rented_property != "" else 0)), PhoneTheme.TEXT)
	_stat_row(list, "Vehicles", str(Globalvar.owned_vehicles.size()), PhoneTheme.TEXT)
	_stat_row(list, "Items", str(Globalvar.inventory_items.size()), PhoneTheme.TEXT)


func _stat_row(list: VBoxContainer, title: String, value: String, color: Color) -> void:
	var c := _card(list)
	var row := PhoneTheme.hbox(8)
	row.add_child(PhoneTheme.label(title, 13, PhoneTheme.TEXT_DIM))
	row.add_child(PhoneTheme.spacer())
	row.add_child(PhoneTheme.label(value, 15, color))
	c.add_child(row)


# ---- Contacts & Calls
func _avatar(text: String, color: Color, size: int) -> PanelContainer:
	var av := PhoneTheme.panel(Color(color.r, color.g, color.b, 0.2), size / 2, color, 0)
	av.custom_minimum_size = Vector2(size, size)
	var ini := PhoneTheme.label(text, int(size * 0.34), PhoneTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	ini.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	av.add_child(ini)
	return av


func _build_contacts(page: VBoxContainer) -> void:
	_header(page, "Contacts", "Players in your session and people you work with")
	var list := _scroll(page)
	# --- players currently in the session (live roster from Session)
	list.add_child(PhoneTheme.label("PLAYERS IN SESSION  (%d)" % Session.players.size(), 11, PhoneTheme.TEXT_DIM))
	if Session.players.is_empty():
		list.add_child(PhoneTheme.wrapped("Nobody else is in the session right now.", 12))
	for pid in Session.player_ids():
		var p: Dictionary = Session.players[pid]
		var on_call: bool = Session.active_call_id == pid
		var c := _card(list, PhoneTheme.GREEN if on_call else PhoneTheme.LINE)
		var row := PhoneTheme.hbox(10)
		row.add_child(_avatar(_initials(p["name"]), PhoneTheme.ACCENT2, 44))
		var col := PhoneTheme.vbox(1)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_row := PhoneTheme.hbox(6)
		name_row.add_child(PhoneTheme.label(p["name"], 15))
		var n_unread: int = int(Session.unread.get(pid, 0))
		if n_unread > 0:
			name_row.add_child(PhoneTheme.tag("%d new" % n_unread, PhoneTheme.RED, 10))
		if on_call:
			name_row.add_child(PhoneTheme.tag("ON CALL", PhoneTheme.GREEN, 10))
		col.add_child(name_row)
		col.add_child(PhoneTheme.label("%s  -  Rank %s  -  online" % [p["class"], p["rank"]], 11, PhoneTheme.ACCENT2))
		row.add_child(col)
		var id_copy: int = pid
		var msg := PhoneTheme.button("Message", PhoneTheme.ACCENT2, 12, 30)
		msg.custom_minimum_size = Vector2(82, 30)
		msg.pressed.connect(func() -> void: open_messages(id_copy))
		row.add_child(msg)
		var callb := PhoneTheme.button("Call", PhoneTheme.GREEN, 12, 30)
		callb.custom_minimum_size = Vector2(60, 30)
		callb.pressed.connect(func() -> void: call_player(id_copy))
		row.add_child(callb)
		c.add_child(row)
	# --- NPC contacts, saved automatically as you meet people
	list.add_child(PhoneTheme.label("CONTACTS", 11, PhoneTheme.TEXT_DIM))
	if Globalvar.contacts.is_empty():
		list.add_child(PhoneTheme.wrapped("No contacts yet. People you work with are saved here.", 13))
	for cid in Globalvar.contacts:
		var ct: Dictionary = PhoneData.CONTACTS.get(cid, {})
		if ct.is_empty():
			continue
		var c := _card(list)
		var row := PhoneTheme.hbox(10)
		row.add_child(_avatar(_initials(ct["name"]), ct["color"], 44))
		var col := PhoneTheme.vbox(1)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(PhoneTheme.label(ct["name"], 15))
		col.add_child(PhoneTheme.label(ct["role"], 11, ct["color"]))
		row.add_child(col)
		if cid == "mechanic":
			row.add_child(PhoneTheme.tag("VALET", PhoneTheme.AMBER, 10))
		var call_btn := PhoneTheme.button("Call", PhoneTheme.GREEN, 12, 30)
		call_btn.custom_minimum_size = Vector2(64, 30)
		var id_copy: String = cid
		call_btn.pressed.connect(func() -> void: call_contact(id_copy))
		row.add_child(call_btn)
		c.add_child(row)


func _initials(name: String) -> String:
	var parts := name.split(" ")
	var s := ""
	for p in parts:
		if p.length() > 0:
			s += p[0]
	return s.substr(0, 2).to_upper()


# ---- Direct messages (player to player)
func open_messages(player_id: int) -> void:
	_msg_player_id = player_id
	Session.mark_read(player_id)
	open("messages")


func _build_messages(page: VBoxContainer) -> void:
	if not Session.players.has(_msg_player_id):
		_header(page, "Messages", "Pick a player in Contacts to start a thread")
		return
	var p: Dictionary = Session.players[_msg_player_id]
	_header(page, p["name"], "%s  -  Rank %s  -  direct messages" % [p["class"], p["rank"]])
	var list := _scroll(page)
	var thread: Array = Session.threads.get(_msg_player_id, [])
	if thread.is_empty():
		list.add_child(PhoneTheme.wrapped("Say hello. Messages go straight to this player's phone.", 12))
	for m in thread:
		var mine: bool = m["from_me"]
		var bubble := PhoneTheme.panel(PhoneTheme.ACCENT if mine else PhoneTheme.CARD_BG, 12, PhoneTheme.LINE, 10)
		bubble.size_flags_horizontal = Control.SIZE_SHRINK_END if mine else Control.SIZE_SHRINK_BEGIN
		var v := PhoneTheme.vbox(2)
		var txt := PhoneTheme.wrapped(m["text"], 13, Color.WHITE if mine else PhoneTheme.TEXT)
		txt.custom_minimum_size = Vector2(220, 0)
		v.add_child(txt)
		v.add_child(PhoneTheme.label(m["time"], 9, Color(1, 1, 1, 0.7) if mine else PhoneTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT if mine else HORIZONTAL_ALIGNMENT_LEFT))
		bubble.add_child(v)
		list.add_child(bubble)
	var sc := list.get_parent().get_parent() as ScrollContainer
	if sc:
		sc.call_deferred("set_v_scroll", 100000)
	# composer pinned under the thread
	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_bottom"]:
		pad.add_theme_constant_override(side, 12)
	pad.add_theme_constant_override("margin_top", 6)
	var row := PhoneTheme.hbox(6)
	_msg_input = LineEdit.new()
	_msg_input.placeholder_text = "Type a message"
	_msg_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_msg_input.custom_minimum_size = Vector2(0, 34)
	_msg_input.add_theme_font_override("font", PhoneTheme.font())
	_msg_input.add_theme_font_size_override("font_size", 13)
	_msg_input.text_submitted.connect(func(_t: String) -> void: _send_message())
	row.add_child(_msg_input)
	var send := PhoneTheme.button("Send", PhoneTheme.ACCENT, 13, 34)
	send.custom_minimum_size = Vector2(64, 34)
	send.pressed.connect(_send_message)
	row.add_child(send)
	pad.add_child(row)
	page.add_child(pad)


func _send_message() -> void:
	if _msg_input == null:
		return
	var text := _msg_input.text
	if Session.send_text(_msg_player_id, text):
		_rebuild("messages")
		if _msg_input:
			_msg_input.call_deferred("grab_focus")


func _on_message_received(player_id: int, text: String) -> void:
	if is_open and _pages["messages"].visible and _msg_player_id == player_id:
		Session.mark_read(player_id)
		_rebuild("messages")
		return
	notify("Message from %s" % Session.player_name(player_id), text, "message")
	_refresh_if_open(["contacts"])


# ---- Voice calls with players
func call_player(player_id: int) -> void:
	if Session.call_state != "idle" or not _active_call.is_empty():
		return
	if Session.start_call(player_id):
		_active_call = {"kind": "player", "player_id": player_id, "incoming": false}
		_show_call_overlay()


func _on_player_call_state(player_id: int, state: String) -> void:
	match state:
		"ringing":
			if not _active_call.is_empty():
				return
			_active_call = {"kind": "player", "player_id": player_id, "incoming": true}
			_show_call_overlay()
		"active":
			if _active_call.get("player_id", -1) == player_id:
				_show_player_call_active()
		"ended", "declined", "busy":
			if _active_call.get("player_id", -1) == player_id:
				_call_state.text = {"ended": "CALL ENDED", "declined": "DECLINED", "busy": "BUSY"}[state]
				_pulse_avatar(false)
				get_tree().create_timer(0.7, true).timeout.connect(_close_call_overlay)
			if state == "declined":
				notify("Call declined", "%s declined your call." % Session.player_name(player_id), "call")
	_refresh_if_open(["contacts"])


func _show_player_call_active() -> void:
	_pulse_avatar(false)
	_call_state.text = "ON CALL"
	_call_timer.visible = true
	_call_meter.visible = true
	_call_text.text = "Voice call connected." if Session._mic_available() else "Voice call connected. No microphone on this device - the level meter shows the simulated feed."
	_call_text.visible_characters = -1
	for c in _call_actions.get_children():
		c.queue_free()
	var mute := PhoneTheme.button("Mute", PhoneTheme.TEXT_DIM, 14, 40)
	mute.custom_minimum_size = Vector2(110, 40)
	mute.pressed.connect(func() -> void:
		mute.text = "Unmute" if Session.toggle_mute() else "Mute")
	_call_actions.add_child(mute)
	var end := PhoneTheme.button("End call", PhoneTheme.RED, 14, 40)
	end.custom_minimum_size = Vector2(120, 40)
	end.pressed.connect(_end_call)
	_call_actions.add_child(end)


# ---- NPC calls
## Outgoing call to a saved contact: the contact answers with one of their scripted lines.
func call_contact(contact_id: String) -> void:
	var ct: Dictionary = PhoneData.CONTACTS.get(contact_id, {})
	if ct.is_empty() or not _active_call.is_empty():
		return
	var lines: Array = ct["lines"]
	_active_call = {"kind": "npc", "contact": contact_id, "line": lines[randi() % lines.size()], "action_label": "", "action_page": "", "incoming": false}
	_show_call_overlay()


func _show_call_overlay() -> void:
	var kind: String = _active_call.get("kind", "npc")
	var caller_name: String
	var role: String
	var color: Color
	if kind == "player":
		var p: Dictionary = Session.players.get(_active_call["player_id"], {})
		caller_name = str(p.get("name", "Player"))
		role = "%s  -  Rank %s  -  in session" % [p.get("class", "?"), p.get("rank", "?")]
		color = PhoneTheme.ACCENT2
	else:
		var ct: Dictionary = PhoneData.CONTACTS[_active_call["contact"]]
		caller_name = ct["name"]
		role = ct["role"]
		color = ct["color"]
	_call_name.text = caller_name
	_call_role.text = role
	_call_role.add_theme_color_override("font_color", color)
	(_call_avatar.get_node("Initials") as Label).text = _initials(caller_name)
	_call_avatar.add_theme_stylebox_override("panel", PhoneTheme.style(Color(color.r, color.g, color.b, 0.2), 44, color, 2, 0))
	_call_text.text = ""
	_call_timer.visible = false
	_call_meter.visible = false
	_call_meter.value = 0.0
	_valet_mode = ""
	for c in _call_actions.get_children():
		c.queue_free()
	for c in _call_panel.get_children():
		c.queue_free()
	_call_overlay.visible = true
	_call_overlay.modulate.a = 0.0
	create_tween().tween_property(_call_overlay, "modulate:a", 1.0, 0.2)
	if _active_call["incoming"]:
		_call_state.text = "INCOMING CALL"
		var answer := PhoneTheme.button("Answer", PhoneTheme.GREEN, 15, 42)
		answer.custom_minimum_size = Vector2(140, 42)
		var ignore := PhoneTheme.button("Decline" if kind == "player" else "Ignore", PhoneTheme.RED, 15, 42)
		ignore.custom_minimum_size = Vector2(140, 42)
		if kind == "player":
			answer.pressed.connect(func() -> void: Session.accept_call())
			ignore.pressed.connect(func() -> void:
				Session.decline_call()
				_close_call_overlay())
		else:
			answer.pressed.connect(_answer_call)
			ignore.pressed.connect(func() -> void:
				notify("Missed call", "%s (%s)" % [caller_name, role], "call")
				_close_call_overlay())
		_call_actions.add_child(answer)
		_call_actions.add_child(ignore)
		_pulse_avatar(true)
	else:
		_call_state.text = "CALLING..."
		if kind == "player":
			var cancel := PhoneTheme.button("Cancel", PhoneTheme.RED, 14, 40)
			cancel.custom_minimum_size = Vector2(120, 40)
			cancel.pressed.connect(_end_call)
			_call_actions.add_child(cancel)
			_pulse_avatar(true)
		else:
			get_tree().create_timer(0.9).timeout.connect(_answer_call)


func _answer_call() -> void:
	if not _call_overlay.visible or _active_call.is_empty() or _active_call.get("kind", "npc") != "npc":
		return
	_pulse_avatar(false)
	_call_state.text = "ON CALL"
	for c in _call_actions.get_children():
		c.queue_free()
	var line: String = _active_call["line"]
	_call_text.text = line
	_call_text.visible_characters = 0
	if _call_typing and _call_typing.is_valid():
		_call_typing.kill()
	_call_typing = create_tween()
	_call_typing.tween_property(_call_text, "visible_characters", line.length(), clampf(line.length() * 0.035, 1.0, 12.0))
	if _active_call["contact"] == "mechanic":
		# Valet spec: the greeting voice line plays first, then Request / Fix / Return appear.
		var length := _speak("ready" if _active_call["incoming"] else "greeting")
		get_tree().create_timer(maxf(length, 1.4), true).timeout.connect(func() -> void:
			if _call_overlay.visible and _active_call.get("contact", "") == "mechanic":
				_show_valet_bar())
		return
	if _active_call["action_label"] != "":
		var act := PhoneTheme.button(_active_call["action_label"], PhoneTheme.ACCENT, 14, 40)
		act.custom_minimum_size = Vector2(170, 40)
		var page: String = _active_call["action_page"]
		act.pressed.connect(func() -> void:
			_close_call_overlay()
			open(page))
		_call_actions.add_child(act)
	var end := PhoneTheme.button("End call", PhoneTheme.RED, 14, 40)
	end.custom_minimum_size = Vector2(120, 40)
	end.pressed.connect(_end_call)
	_call_actions.add_child(end)


## Hang up from the player's side (works for NPC and player calls).
func _end_call() -> void:
	if _active_call.get("kind") == "player" and Session.call_state != "idle":
		if Session.call_state == "ringing":
			Session.decline_call()
		else:
			Session.end_call()
	_close_call_overlay()


func _close_call_overlay() -> void:
	_pulse_avatar(false)
	if _call_typing and _call_typing.is_valid():
		_call_typing.kill()
	_call_overlay.visible = false
	_call_timer.visible = false
	_call_meter.visible = false
	_valet_mode = ""
	_active_call = {}


func _pulse_avatar(on: bool) -> void:
	if _call_avatar.has_meta("pulse"):
		var old: Tween = _call_avatar.get_meta("pulse")
		if old and old.is_valid():
			old.kill()
		_call_avatar.remove_meta("pulse")
	_call_avatar.pivot_offset = _call_avatar.size * 0.5
	_call_avatar.scale = Vector2.ONE
	if on:
		var tw := create_tween().set_loops()
		tw.tween_property(_call_avatar, "scale", Vector2(1.1, 1.1), 0.45).set_trans(Tween.TRANS_SINE)
		tw.tween_property(_call_avatar, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_SINE)
		_call_avatar.set_meta("pulse", tw)


# ---- Valet & Mechanic (Rook): Request / Return / Fix bar on the call screen
func _show_valet_bar() -> void:
	for c in _call_actions.get_children():
		c.queue_free()
	for entry in [["Request", "request", PhoneTheme.ACCENT], ["Fix", "fix", PhoneTheme.AMBER], ["Return", "return", PhoneTheme.ACCENT2]]:
		var b := PhoneTheme.button(entry[0], entry[2], 14, 40)
		b.custom_minimum_size = Vector2(96, 40)
		var mode: String = entry[1]
		b.pressed.connect(func() -> void:
			_valet_mode = mode
			_build_valet_panel())
		_call_actions.add_child(b)
	var end := PhoneTheme.button("End", PhoneTheme.RED, 14, 40)
	end.custom_minimum_size = Vector2(80, 40)
	end.pressed.connect(_end_call)
	_call_actions.add_child(end)


func _build_valet_panel() -> void:
	for c in _call_panel.get_children():
		_call_panel.remove_child(c)
		c.queue_free()
	if _valet_mode == "":
		return
	var ids: Array = Valet.owned_ids()
	if ids.is_empty():
		_call_panel.add_child(PhoneTheme.wrapped("You don't own a vehicle yet - browse the Vehicle app first.", 12))
		return
	match _valet_mode:
		"request":
			_call_panel.add_child(PhoneTheme.label("WHICH CAR SHOULD THE DRIVER BRING?", 11, PhoneTheme.TEXT_DIM))
			for vid in ids:
				var blocker: String = Valet.request_blocker(vid)
				_valet_row(vid, "Send", PhoneTheme.ACCENT, blocker, func() -> void:
					if Valet.request(vid):
						_say("Driver's on the way with your %s. ETA about %d seconds - I'll ping you when it's parked." % [PhoneData.vehicle(vid)["name"], int(Valet.last_delivery_eta)], "request"))
		"return":
			_call_panel.add_child(PhoneTheme.label("RETURN WHICH CAR TO THE GARAGE?", 11, PhoneTheme.TEXT_DIM))
			var any := false
			for vid in ids:
				if Valet.deployed.has(vid) or Valet.en_route.has(vid):
					any = true
					_valet_row(vid, "Return", PhoneTheme.ACCENT2, "", func() -> void:
						if Valet.return_vehicle(vid):
							_say("%s is back in the garage." % PhoneData.vehicle(vid)["name"], "return"))
			if not any:
				_call_panel.add_child(PhoneTheme.wrapped("Nothing of yours is out on the street right now.", 12))
		"fix":
			_call_panel.add_child(PhoneTheme.label("WHICH CAR GOES ON THE LIFT?", 11, PhoneTheme.TEXT_DIM))
			var any := false
			for vid in ids:
				if Valet.in_service(vid):
					continue
				var d: int = Valet.damage_of(vid)
				if d > 0:
					any = true
					_valet_row(vid, "Fix %d%%" % d, PhoneTheme.AMBER, "", func() -> void:
						if Valet.fix(vid):
							_say("%s is in the service queue. Ready in %s - I'll call when it's done." % [PhoneData.vehicle(vid)["name"], Valet._fmt(Valet.service_remaining(vid))], "fix"))
			if not any:
				_call_panel.add_child(PhoneTheme.wrapped("Nothing's damaged. Drive safe.", 12))
			if not Valet.service_queue.is_empty():
				_call_panel.add_child(PhoneTheme.label("SERVICE QUEUE", 11, PhoneTheme.TEXT_DIM))
				for job in Valet.service_queue:
					_call_panel.add_child(PhoneTheme.label("%s  -  %s left" % [PhoneData.vehicle(job["id"])["name"], Valet._fmt(Valet.service_remaining(job["id"]))], 12, PhoneTheme.TEXT))


func _valet_row(vid: String, action: String, color: Color, blocker: String, on_press: Callable) -> void:
	var row := PhoneTheme.hbox(8)
	var col := PhoneTheme.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(PhoneTheme.label(PhoneData.vehicle(vid)["name"], 13))
	col.add_child(PhoneTheme.label(blocker if blocker != "" else Valet.status(vid), 10, PhoneTheme.RED if blocker != "" else PhoneTheme.TEXT_DIM))
	row.add_child(col)
	var b := PhoneTheme.button(action, color, 12, 30)
	b.custom_minimum_size = Vector2(90, 30)
	b.disabled = blocker != ""
	b.pressed.connect(func() -> void:
		on_press.call()
		_build_valet_panel())
	row.add_child(b)
	_call_panel.add_child(row)


func _say(text: String, voice_line := "") -> void:
	_speak(voice_line)
	if _call_typing and _call_typing.is_valid():
		_call_typing.kill()
	_call_text.text = text
	_call_text.visible_characters = 0
	_call_typing = create_tween()
	_call_typing.tween_property(_call_text, "visible_characters", text.length(), clampf(text.length() * 0.025, 0.6, 6.0))


## Plays one of Rook's recorded lines and returns its length (0 if none / not imported).
func _speak(line: String) -> float:
	if not VOICE_LINES.has(line) or not ResourceLoader.exists(VOICE_LINES[line]):
		return 0.0
	if _voice == null:
		_voice = AudioStreamPlayer.new()
		_voice.volume_db = 2.0
		add_child(_voice)
	var stream: AudioStream = load(VOICE_LINES[line])
	_voice.stream = stream
	_voice.play()
	return stream.get_length()


func _refresh_valet_views() -> void:
	_refresh_if_open(["vehicle", "home"])
	if _call_overlay.visible and _valet_mode != "":
		_build_valet_panel()


# ---- Notifications
func _build_notifications(page: VBoxContainer) -> void:
	_header(page, "Notifications", "%d total" % notifications.size())
	var list := _scroll(page)
	if notifications.is_empty():
		list.add_child(PhoneTheme.wrapped("Nothing yet. Job offers, deliveries, construction and tournament alerts land here.", 13))
	else:
		var clear := PhoneTheme.button("Clear all", PhoneTheme.TEXT_DIM, 12, 28)
		clear.pressed.connect(func() -> void:
			notifications.clear()
			_rebuild("notifications"))
		list.add_child(clear)
	for n in notifications:
		var color := _kind_color(n["kind"])
		var c := _card(list, Color(color.r, color.g, color.b, 0.4))
		var row := PhoneTheme.hbox(8)
		row.add_child(PhoneTheme.label(n["title"], 14, color))
		row.add_child(PhoneTheme.spacer())
		row.add_child(PhoneTheme.label(n["time"], 10, PhoneTheme.TEXT_DIM))
		c.add_child(row)
		c.add_child(PhoneTheme.wrapped(n["body"], 12))


# ---- rank (reads the client's RankManager ladder)
func _next_threshold() -> int:
	var nr: Dictionary = RankManager.get_next_rank()
	return int(nr["renown"]) if not nr.is_empty() else -1


func _next_rank_name() -> String:
	var nr: Dictionary = RankManager.get_next_rank()
	return str(nr["name"]) if not nr.is_empty() else ""


func _rank_progress() -> float:
	var nxt := _next_threshold()
	if nxt < 0:
		return 1.0
	var idx: int = maxi(0, RankManager.get_rank_index(Globalvar.current_rank))
	var cur: int = int(RankManager.RANKS[idx]["renown"])
	return clampf(float(Globalvar.current_renown - cur) / float(maxi(1, nxt - cur)), 0.0, 1.0)


func _on_rank_changed(_old_rank: String, new_rank: String) -> void:
	notify("Advanced to Rank %s" % new_rank, PhoneData.RANK_UP_MESSAGE, "rank")
	_refresh_if_open(["home", "stats", "clan"])
