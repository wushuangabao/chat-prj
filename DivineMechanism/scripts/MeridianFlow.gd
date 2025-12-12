class_name MeridianFlow
extends Resource

@export var flow_name: String = "New Flow"
@export var starting_node_id: String = "start"
@export var nodes: Array[ActionNode] = []

func get_nodes_as_dict() -> Dictionary:
	var dict = {}
	for node in nodes:
		if node.id != "":
			dict[node.id] = node
	return dict
