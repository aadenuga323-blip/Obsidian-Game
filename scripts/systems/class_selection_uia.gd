extends Control

var picked_class: String = ""
@onready var descriptiontext=$"CanvasLayer/Description"
@onready var swordsman=$CanvasLayer/Swordsman_Control/title
@onready var ninja=$CanvasLayer/Ninja_Control/title
@onready var archer=$CanvasLayer/Archer_Control/title
@onready var sniper=$CanvasLayer/Sniper_Control/title
@onready var assault=$CanvasLayer/Assault_Control/title
@onready var engineer=$CanvasLayer/Engineer_Control/title

func _ready() -> void:
	swordsman.hide()
	ninja.hide()
	archer.hide()
	sniper.hide()
	assault.hide()
	engineer.hide()
	
func _on_swordsman_b_pressed() -> void:
	picked_class= "swordsman"
	descriptiontext.text="naturally favour the Central Plaza — an open, flat area perfect for close-quarters duels.
Snipers will find the High Spires most useful — tall structures with long, clear sightlines overlooking the rest of the battlefield."
	print(picked_class)
	show_class(swordsman)


func _on_ninja_b_pressed() -> void:
	picked_class= "ninja"
	descriptiontext.text="use the Shadow Corridors — a network of covered walkways, tunnels, and vertical passages that let them move unseen and appear where they are least expected."
	print(picked_class)
	show_class(ninja)


func _on_archer_b_pressed() -> void:
	picked_class= "archer"
	descriptiontext.text=" excel from the Mid-Tier Balconies — positioned perfectly between ground level and the highest points, with good range on all sides."
	print(picked_class)
	show_class(archer)


func _on_sniper_b_pressed() -> void:
	picked_class= "sniper"
	descriptiontext.text="will find the High Spires most useful — tall structures with long, clear sightlines overlooking the rest of the battlefield."
	print(picked_class)
	show_class(sniper)


func _on_assault_b_pressed() -> void:
	picked_class= "assault"
	descriptiontext.text="use the Ramp Entrances — wide, covered approaches that let a team push forward toward the centre of the ruins."
	print(picked_class)
	show_class(assault)


func _on_engineer_b_pressed() -> void:
	picked_class= "engineer"
	descriptiontext.text="control the Chokepoints — narrow doorways, bridges, and alleyways where mines and traps are most effective."
	print(picked_class)
	show_class(engineer)

func _on_select_b_pressed() -> void:
	if picked_class.is_empty():
		print("Please select a class first!")
		return
	print("Spawning class: ", picked_class)
	Globalvar.current_class=picked_class
	queue_free()

func show_class(selected: Label) -> void:
	swordsman.hide()
	ninja.hide()
	archer.hide()
	sniper.hide()
	assault.hide()
	engineer.hide()
	
	selected.show()
