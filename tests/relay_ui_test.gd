extends Node
## Entry point: hands over to a driver under /root (see relay_ui_driver.gd).


func _ready() -> void:
	get_tree().root.add_child.call_deferred(load("res://tests/relay_ui_driver.gd").new())
