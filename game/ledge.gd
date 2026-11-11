extends Marker2D

# Grabbable platform corner. face_dir is the facing the player has while hanging (towards the platform).

@export_enum("Left:-1", "Right:1") var face_dir := 1


func _ready() -> void:
	add_to_group(&"ledges")
