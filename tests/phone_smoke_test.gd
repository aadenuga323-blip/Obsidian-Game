extends Node
## Headless check of the phone system against Globalvar + JobManager, plus the
## session (player-to-player) and valet (Mechanic) services:
##   godot --headless --path . res://tests/phone_smoke_test.tscn

var _fail := 0


func _check(ok: bool, label: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label)
	if not ok:
		_fail += 1


func _wait_until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await get_tree().process_frame
		t += get_process_delta_time()
	return cond.call()


func _ready() -> void:
	await get_tree().process_frame
	_check(Phone != null and not Phone.is_open, "Phone autoload present and closed")
	Phone.open()
	_check(Phone.is_open, "phone opens")
	for p in ["jobs", "property", "vehicle", "market", "clan", "gps", "stats", "contacts", "notifications", "home"]:
		Phone.show_page(p)
		_check(Phone._pages[p].get_child_count() > 0, "page builds: %s" % p)
	# Jobs: apply, GPS marker, arrival completes delivery and pays credits.
	var before: int = Globalvar.current_credits
	_check(JobManager.accept_job("delivery_002"), "apply to Foundry Parts Run")
	_check(Globalvar.has_destination and Globalvar.destination_label == "Foundry Parts Run", "GPS set to the job")
	Phone._on_marker_arrived()
	await get_tree().process_frame
	_check(Globalvar.completed_jobs.has("delivery_002"), "arrival completes the delivery job")
	_check(Globalvar.current_credits > before, "job pays credits")
	_check(Globalvar.current_renown == 12 and Globalvar.current_points == 6, "job pays renown and points")
	# Property with confirm + agent call.
	Globalvar.add_credits(20000)
	Phone.show_page("property")
	Phone._buy_property("apt_heights_01", true, 350)
	_check(Globalvar.rented_property == "apt_heights_01", "rents an apartment")
	Phone._buy_property("plot_heights_07", false, 9500)
	_check(Globalvar.owned_properties.has("plot_heights_07"), "buys a plot")
	_check(Globalvar.contacts.has("housing_agent"), "housing agent saved to contacts")
	await get_tree().create_timer(3.2).timeout
	_check(Phone._call_overlay.visible and Phone._call_name.text == "Mara Vell", "housing agent calls after purchase")
	Phone._answer_call()
	await get_tree().process_frame
	_check(Phone._call_state.text == "ON CALL", "call answered")
	Phone._end_call()
	# Market + invitations + rank.
	var stock0: int = PhoneData.market_item("sword_short")["stock"]
	Phone._order_item("sword_short", 650, false)
	_check(Globalvar.inventory_items.has("sword_short") and Globalvar.market_stock["sword_short"] == stock0 - 1, "market order decrements stock")
	Phone.invite("clan_war", "Clan war: Ashfall vs Ironvale", "Rank D, Ruins Arena, tonight.")
	_check(Phone._pending_invites.size() == 1, "invitation received")
	Phone._answer_invite(Phone._pending_invites[0], true)
	_check(Phone._pending_invites.is_empty(), "invitation accepted")
	RankManager.add_renown(100 - Globalvar.current_renown, "test")
	_check(Globalvar.current_rank == "C", "rank advances D -> C at 100 renown")
	_check(Phone.notifications[0]["kind"] == "rank", "rank-up notification sent")

	await _test_session()
	await _test_valet()

	Phone.close()
	_check(not Phone.is_open, "phone closes")
	print("\nPHONE SMOKE TEST %s (%d failure(s))" % ["PASSED" if _fail == 0 else "FAILED", _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _test_session() -> void:
	print("[Session: player-to-player]")
	_check(not Session.is_online() and Session.players.size() >= 3, "offline session has a simulated roster")
	var pid: int = Session.player_ids()[0]
	Phone.show_page("contacts")
	_check(Phone._pages["contacts"].get_child_count() > 0, "contacts page lists session players")
	Phone.open_messages(pid)
	_check(Phone._pages["messages"].visible and Phone._msg_input != null, "message thread opens with composer")
	Phone._msg_input.text = "where are you?"
	Phone._send_message()
	_check(Session.threads[pid].size() == 1 and Session.threads[pid][0]["from_me"], "text sent to player")
	var replied: bool = await _wait_until(func() -> bool: return Session.threads[pid].size() >= 2, 5.0)
	_check(replied and not Session.threads[pid][1]["from_me"], "player replies to the text")
	# outgoing voice call
	Phone.call_player(pid)
	_check(Session.call_state == "calling" and Phone._call_overlay.visible and Phone._call_state.text == "CALLING...", "outgoing call rings")
	var active: bool = await _wait_until(func() -> bool: return Session.call_state == "active", 4.0)
	_check(active and Phone._call_timer.visible and Phone._call_meter.visible, "call connects with timer and mic meter")
	_check(Session.toggle_mute() == true, "mute toggles")
	Phone._end_call()
	_check(Session.call_state == "idle" and not Phone._call_overlay.visible, "call ends cleanly")
	# incoming voice call
	await get_tree().create_timer(0.8).timeout
	Session.simulate_incoming_call(pid)
	await get_tree().process_frame
	_check(Phone._call_overlay.visible and Phone._call_state.text == "INCOMING CALL", "incoming player call shows Answer/Decline")
	Session.accept_call()
	await get_tree().process_frame
	_check(Session.call_state == "active" and Phone._call_state.text == "ON CALL", "incoming call answered")
	Session.end_call()
	await get_tree().create_timer(0.9).timeout
	_check(not Phone._call_overlay.visible, "overlay closes when the other side hangs up")


func _test_valet() -> void:
	print("[Valet: Request / Return / Fix]")
	# a flat ground so the delivered car has something to drive on
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(0, -0.5, 0)
	get_tree().current_scene.add_child(ground)
	var player := CharacterBody3D.new()
	player.add_to_group("players")
	var pshape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	pshape.shape = cap
	pshape.position = Vector3(0, 1, 0)
	player.add_child(pshape)
	get_tree().current_scene.add_child(player)
	player.global_position = Vector3(0, 0.1, 0)

	Globalvar.add_credits(10000)
	Phone._buy_vehicle("car_city", 4200, "Navy", false)
	_check(Globalvar.owned_vehicles.has("car_city") and Globalvar.vehicle_colors["car_city"] == "Navy", "owned car with colour recorded")
	_check(Globalvar.contacts.has("mechanic"), "mechanic saved to contacts")
	Phone.call_contact("mechanic")
	await get_tree().create_timer(1.2).timeout
	_check(Phone._call_text.text.begins_with("Hey, how can I help you"), "Rook answers with the greeting voice line")
	_check(Phone._call_actions.get_child_count() == 0, "options wait until the greeting has been spoken")
	await get_tree().create_timer(4.0).timeout
	var labels: Array = []
	for b in Phone._call_actions.get_children():
		labels.append(b.text)
	_check(labels == ["Request", "Fix", "Return", "End"], "greeting is followed by the Request / Fix / Return bar (%s)" % str(labels))
	Phone._valet_mode = "request"
	Phone._build_valet_panel()
	_check(Phone._call_panel.get_child_count() >= 2, "request lists owned cars")
	Valet.spawn_distance = 14.0
	_check(Valet.request("car_city"), "request dispatches a driver")
	_check(Valet.en_route.has("car_city") and Valet.status("car_city") == "En route to you", "car is en route")
	var car: Node3D = Valet.en_route["car_city"].get_parent()
	var start_d: float = car.global_position.distance_to(player.global_position)
	var delivered: bool = await _wait_until(func() -> bool: return Valet.deployed.has("car_city"), 40.0)
	var end_d: float = car.global_position.distance_to(player.global_position) if is_instance_valid(car) else 999.0
	_check(delivered, "NPC drives the car to the player (%.1f m -> %.1f m)" % [start_d, end_d])
	_check(end_d < 9.0, "car parked within reach of the player")
	_check(car.get_node_or_null("ValetDriver") == null, "driver hands the car over (controller removed)")
	_check(Valet.request_blocker("car_city") != "", "cannot request a car that is already out")
	_check(Valet.return_vehicle("car_city"), "return takes the car back")
	await get_tree().process_frame
	_check(not Valet.deployed.has("car_city") and not is_instance_valid(car), "car disappears immediately")
	_check(not Valet.fix("car_city"), "undamaged car is not sent for repair")
	Globalvar.damage_vehicle("car_city", 40)
	Valet.repair_seconds_per_percent = 0.05
	Valet.min_repair_seconds = 1.0
	_check(Valet.fix("car_city") and Valet.in_service("car_city"), "damaged car enters the service queue")
	_check(Valet.request_blocker("car_city") != "", "car in service cannot be requested")
	var repaired: bool = await _wait_until(func() -> bool: return not Valet.in_service("car_city"), 6.0)
	_check(repaired and Valet.damage_of("car_city") == 0, "repair sequence completes and clears damage")
	await get_tree().create_timer(0.3).timeout
	_check(Phone._call_overlay.visible and Phone._call_name.text == "Rook Hale", "mechanic calls back when the car is ready")
	Phone._end_call()
