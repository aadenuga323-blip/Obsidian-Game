extends Node3D
var a=false
@export var player: Node3D
func _process(delta: float) -> void:
	if  a:
		player.cinematic_scene = true
		player.cinematic_follow($GateArea/GateEnterPlayerArea, 3.0, 0.0)

		
		
func player_entered_gate():
	var dialogue_text: String= "Hey there. I see you just arrived. Fresh off the gates, right? No place to stay, no credits in your pocket… I know what that feels like. You look like someone who's willing to work. Need a job? I've got small tasks — deliveries, simple runs. Nothing dangerous yet, but it'll pay. I've sent someone to pick you up. Look to your right — they're less than a minute away. No need to walk far. They'll bring you straight to me. See you soon."
	_on_intro_triggered("EnterTheGate")
	await $"../GameUI".play_typewriter_effect(dialogue_text)
	player.cinematic_scene = false
	# Design doc, Step Three: the Job Agent calls moments after you walk through the gates.
	Phone.incoming_call("job_agent", PhoneData.FIRST_CALL, "Open Job Board", "jobs")
	
	
@onready var cinematic_manager=$"../CinematicManager"
@onready var text_title=$"../GameUI"
func _on_trigger_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("players"):
		text_title.show_message("NOVA AETHERIS",2.0)
		print("Player entered the area!")
		_on_intro_triggered("ClearTheGate")


func _on_intro_triggered(name: String) -> void:
	if name=="ClearTheGate":
		$"../CinematicManager".play_marker($"../CameraPositions/ClearTheGate",3.0,4.0)
	if name=="EnterTheGate":
		$"../CinematicManager".play_marker($"../CameraPositions/EnterTheGate",3.0,10.0)


func _on_gate_enter_player_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("players"):
		print("PLAYER ENTERED THE GATE")
		player_entered_gate()
	
	
