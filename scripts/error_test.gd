extends Node

# Intentional runtime error to check that script errors reach stdout.
func _ready() -> void:
	var missing: Node = null
	missing.queue_free()
