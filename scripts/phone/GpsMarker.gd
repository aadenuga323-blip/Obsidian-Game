extends Node3D
class_name GpsMarker
## World beacon spawned by the Phone's GPS. Emits arrived() when a node in the
## "players" group comes within arrive_radius, then the Phone removes it.

signal arrived

@export var arrive_radius := 4.0

var label_text := "DESTINATION"
var _time := 0.0
var _ring: MeshInstance3D
var _beam: MeshInstance3D
var _label: Label3D
var _done := false


func _ready() -> void:
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.5
	beam_mesh.bottom_radius = 0.5
	beam_mesh.height = 30.0
	beam_mesh.radial_segments = 12
	_beam = MeshInstance3D.new()
	_beam.mesh = beam_mesh
	_beam.position = Vector3(0, 15, 0)
	_beam.material_override = _glow(PhoneTheme.ACCENT, 0.3)
	add_child(_beam)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 1.8
	ring_mesh.outer_radius = 2.2
	_ring = MeshInstance3D.new()
	_ring.mesh = ring_mesh
	_ring.position = Vector3(0, 0.3, 0)
	_ring.material_override = _glow(PhoneTheme.ACCENT, 1.0)
	add_child(_ring)
	_label = Label3D.new()
	_label.text = label_text
	_label.font_size = 48
	_label.pixel_size = 0.03
	_label.position = Vector3(0, 3.5, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = PhoneTheme.ACCENT
	_label.outline_size = 10
	_label.no_depth_test = true
	add_child(_label)


func _glow(color: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.5
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _process(delta: float) -> void:
	_time += delta
	_ring.rotation.y += delta * 1.5
	_ring.position.y = 0.3 + sin(_time * 2.0) * 0.15
	if _done:
		return
	var player := get_tree().get_first_node_in_group("players") as Node3D
	if player == null:
		return
	var d := player.global_position - global_position
	d.y = 0.0
	if d.length() <= arrive_radius:
		_done = true
		arrived.emit()
