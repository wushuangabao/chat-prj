extends Control

var current_flow: MeridianFlow
var selected_node: ActionNode

# UI Elements
var graph_edit: GraphEdit
var inspector_panel: VBoxContainer
var filename_edit: LineEdit

# Inspector Fields
var id_edit: LineEdit
var name_edit: LineEdit
var type_option: OptionButton
var windup_spin: SpinBox
var active_spin: SpinBox
var recovery_spin: SpinBox
var power_spin: SpinBox
var toughness_spin: SpinBox
var cost_spin: SpinBox
var condition_option: OptionButton
var param_spin: SpinBox

# Context Menu
var context_menu: PopupMenu
var context_menu_pos: Vector2

func _ready():
	_setup_ui()
	_create_new_flow()

func _setup_ui():
	# 添加不透明背景
	var bg = Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 设置为深灰色背景
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 1.0)
	bg.add_theme_stylebox_override("panel", style)
	add_child(bg)

	var root = HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	
	# --- Left: Graph Editor ---
	graph_edit = GraphEdit.new()
	graph_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_edit.size_flags_stretch_ratio = 3.0
	graph_edit.right_disconnects = true # Allow disconnecting from right port
	
	# Connect signals
	graph_edit.connection_request.connect(_on_connection_request)
	graph_edit.disconnection_request.connect(_on_disconnection_request)
	graph_edit.delete_nodes_request.connect(_on_delete_nodes_request)
	graph_edit.node_selected.connect(_on_node_selected)
	graph_edit.node_deselected.connect(_on_node_deselected)
	graph_edit.popup_request.connect(_on_popup_request)
	
	root.add_child(graph_edit)
	
	# --- Right: Inspector & File Ops ---
	var right_sidebar = VBoxContainer.new()
	right_sidebar.custom_minimum_size = Vector2(300, 0)
	right_sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(right_sidebar)
	
	# ScrollContainer for Inspector to prevent overflow
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_sidebar.add_child(scroll)
	
	# Inspector
	inspector_panel = VBoxContainer.new()
	inspector_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(inspector_panel)
	
	_setup_inspector()
	
	right_sidebar.add_child(HSeparator.new())
	
	# File Ops
	var file_ops = VBoxContainer.new()
	file_ops.custom_minimum_size = Vector2(0, 150) # Ensure space for file ops
	right_sidebar.add_child(file_ops)
	
	filename_edit = LineEdit.new()
	filename_edit.text = "user://p1_flow.tres"
	file_ops.add_child(filename_edit)
	
	var save_btn = Button.new()
	save_btn.text = "Save Flow"
	save_btn.pressed.connect(_on_save_flow)
	file_ops.add_child(save_btn)
	
	var load_btn = Button.new()
	load_btn.text = "Load Flow"
	load_btn.pressed.connect(_on_load_flow)
	file_ops.add_child(load_btn)
	
	var close_btn = Button.new()
	close_btn.text = "Close Editor"
	close_btn.pressed.connect(func(): visible = false)
	file_ops.add_child(close_btn)
	
	# Context Menu for adding nodes
	context_menu = PopupMenu.new()
	context_menu.add_item("Add Attack Node", 0)
	context_menu.add_item("Add Defend Node", 1)
	context_menu.add_item("Add Dodge Node", 2)
	context_menu.add_item("Add Wait Node", 3)
	context_menu.id_pressed.connect(_on_context_menu_item_selected)
	add_child(context_menu)

func _setup_inspector():
	var p = inspector_panel
	p.add_child(Label.new()) # Spacer
	
	var title = Label.new()
	title.text = "Inspector"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(title)
	p.add_child(HSeparator.new())
	
	id_edit = _create_field(p, "ID")
	name_edit = _create_field(p, "Name")
	
	p.add_child(Label.new())
	var type_lbl = Label.new()
	type_lbl.text = "Type"
	p.add_child(type_lbl)
	
	type_option = OptionButton.new()
	type_option.add_item("ATTACK", ActionNode.Type.ATTACK)
	type_option.add_item("DEFEND", ActionNode.Type.DEFEND)
	type_option.add_item("DODGE", ActionNode.Type.DODGE)
	type_option.add_item("WAIT", ActionNode.Type.WAIT)
	type_option.item_selected.connect(_on_type_changed)
	p.add_child(type_option)
	
	windup_spin = _create_spin(p, "Windup")
	active_spin = _create_spin(p, "Active")
	recovery_spin = _create_spin(p, "Recovery")
	cost_spin = _create_spin(p, "Cost", 1000)
	
	p.add_child(HSeparator.new())
	power_spin = _create_spin(p, "Power", 1000)
	toughness_spin = _create_spin(p, "Toughness", 1000)
	
	p.add_child(HSeparator.new())
	var cond_lbl = Label.new()
	cond_lbl.text = "Condition (Wait Only)"
	p.add_child(cond_lbl)
	
	condition_option = OptionButton.new()
	condition_option.add_item("ALWAYS_TRUE", WaitActionNode.Condition.ALWAYS_TRUE)
	condition_option.add_item("DISTANCE_GT", WaitActionNode.Condition.DISTANCE_GT)
	condition_option.add_item("DISTANCE_LT", WaitActionNode.Condition.DISTANCE_LT)
	condition_option.add_item("MY_HP_LT", WaitActionNode.Condition.MY_HP_LT)
	condition_option.add_item("MY_STAMINA_LT", WaitActionNode.Condition.MY_STAMINA_LT)
	condition_option.add_item("ENEMY_HP_LT", WaitActionNode.Condition.ENEMY_HP_LT)
	condition_option.add_item("ENEMY_STAMINA_LT", WaitActionNode.Condition.ENEMY_STAMINA_LT)
	p.add_child(condition_option)
	
	param_spin = _create_spin(p, "Param", 1000)
	
	p.add_child(Label.new())
	var apply_btn = Button.new()
	apply_btn.text = "Apply Changes"
	apply_btn.pressed.connect(_save_node_data)
	p.add_child(apply_btn)

func _create_field(parent, label_text) -> LineEdit:
	var lbl = Label.new()
	lbl.text = label_text
	parent.add_child(lbl)
	var edit = LineEdit.new()
	parent.add_child(edit)
	return edit

func _create_spin(parent, label_text, max_val=10.0) -> SpinBox:
	var lbl = Label.new()
	lbl.text = label_text
	parent.add_child(lbl)
	var spin = SpinBox.new()
	spin.step = 0.1
	spin.max_value = max_val
	parent.add_child(spin)
	return spin

# --- Graph Logic ---

func _create_new_flow():
	current_flow = MeridianFlow.new()
	_refresh_graph()

func _refresh_graph():
	graph_edit.clear_connections()
	# Clear existing nodes
	for child in graph_edit.get_children():
		if child is GraphNode:
			child.queue_free()
	
	# Create nodes
	for n in current_flow.nodes:
		_create_graph_node(n)
	
	# Create connections
	# Wait one frame for nodes to be ready (ports to exist)
	await get_tree().process_frame
	
	for n in current_flow.nodes:
		if n.next_node_name != "":
			graph_edit.connect_node(n.id, 0, n.next_node_name, 0)
		
		if n is WaitActionNode and n.next_node_fail != "":
			graph_edit.connect_node(n.id, 1, n.next_node_fail, 0)

func _create_graph_node(n: ActionNode):
	var gnode = GraphNode.new()
	gnode.name = n.id # Use ID as node name in scene tree for connection mapping
	gnode.title = n.node_name + " (" + n.id + ")"
	gnode.position_offset = n.graph_position
	gnode.resizable = true
	gnode.size = Vector2(200, 150)
	
	# Slot 0: Input (Left)
	gnode.set_slot(0, true, 0, Color.WHITE, false, 0, Color.WHITE)
	
	var label = Label.new()
	label.text = ActionNode.Type.keys()[n.get_action_type()]
	gnode.add_child(label)
	
	# Output Slots
	if n is WaitActionNode:
		# Wait Node:
		# Slot 0 (Child 0): Type Label (Input Only)
		# Slot 1 (Child 1): True Output
		# Slot 2 (Child 2): False Output
		
		var out_true = Label.new()
		out_true.text = "True / Next"
		out_true.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		gnode.add_child(out_true)
		# port_index 0 (output) is assigned to child 1
		gnode.set_slot(1, false, 0, Color.WHITE, true, 0, Color.GREEN)
		
		var out_false = Label.new()
		out_false.text = "False"
		out_false.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		gnode.add_child(out_false)
		# port_index 1 (output) is assigned to child 2
		gnode.set_slot(2, false, 0, Color.WHITE, true, 1, Color.RED)
		
	else:
		# Standard Node:
		# Slot 0 (Child 0): Type Label (Input Only)
		# Slot 1 (Child 1): Next Output
		
		var out_lbl = Label.new()
		out_lbl.text = "Next"
		out_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		gnode.add_child(out_lbl)
		# port_index 0 (output) is assigned to child 1
		gnode.set_slot(1, false, 0, Color.WHITE, true, 0, Color.WHITE)
	
	# Store reference to data
	gnode.set_meta("action_node", n)
	
	# Update position when dragged
	gnode.dragged.connect(func(from, to): 
		n.graph_position = to
		gnode.position_offset = to
	)
	
	graph_edit.add_child(gnode)

func _on_popup_request(position):
	context_menu_pos = position
	# Use get_global_mouse_position() for popup position
	# `position` from signal is local to GraphEdit, but popup() expects screen coords?
	# Actually popup() usually takes coordinates relative to window or screen depending on method.
	# But a simpler way is using `set_position` with global mouse pos.
	
	context_menu.position = Vector2(get_viewport().get_mouse_position())
	context_menu.popup()

func _on_context_menu_item_selected(id):
	var new_node: ActionNode
	match id:
		0: new_node = AttackActionNode.new()
		1: new_node = DefendActionNode.new()
		2: new_node = DodgeActionNode.new()
		3: new_node = WaitActionNode.new()
	
	new_node.id = "node_" + str(Time.get_ticks_msec()) # Unique ID
	new_node.node_name = "New Action"
	# Adjust position to be relative to graph scroll
	new_node.graph_position = (context_menu_pos + graph_edit.scroll_offset) / graph_edit.zoom
	
	current_flow.nodes.append(new_node)
	_create_graph_node(new_node)
	
	# Select the new node
	selected_node = new_node
	_load_node_to_inspector(new_node)

func _on_connection_request(from_node_id, from_port, to_node_id, to_port):
	# Update Data
	var from_node = _get_node_by_id(from_node_id)
	var to_node = _get_node_by_id(to_node_id)
	
	if not from_node or not to_node: return
	
	# Disconnect existing connection from this port if any
	# Iterate through all connections to find if there is already one from this node and port
	for conn in graph_edit.get_connection_list():
		if conn["from_node"] == from_node_id and conn["from_port"] == from_port:
			graph_edit.disconnect_node(conn["from_node"], conn["from_port"], conn["to_node"], conn["to_port"])
			break
			
	# Disconnect existing connection to the target input port if any (Limit 1 input per port)
	for conn in graph_edit.get_connection_list():
		if conn["to_node"] == to_node_id and conn["to_port"] == to_port:
			# Disconnect visual
			graph_edit.disconnect_node(conn["from_node"], conn["from_port"], conn["to_node"], conn["to_port"])
			
			# Clear data from the old source node
			var old_source = _get_node_by_id(conn["from_node"])
			if old_source:
				if old_source is WaitActionNode:
					if conn["from_port"] == 0:
						old_source.next_node_name = ""
					else:
						old_source.next_node_fail = ""
				else:
					old_source.next_node_name = ""
			break
	
	# Port 0 is usually the first output port (index 0 of output ports)
	# But in GraphEdit signal, from_port is the index of the port enabled for output.
	# WaitNode: Port 0 (True), Port 1 (False)
	
	if from_node is WaitActionNode:
		if from_port == 0:
			from_node.next_node_name = to_node.id
		else:
			from_node.next_node_fail = to_node.id
	else:
		from_node.next_node_name = to_node.id
	
	# Update Graph Visuals
	graph_edit.connect_node(from_node_id, from_port, to_node_id, to_port)

func _on_disconnection_request(from_node_id, from_port, to_node_id, to_port):
	var from_node = _get_node_by_id(from_node_id)
	if not from_node: return
	
	if from_node is WaitActionNode:
		if from_port == 0:
			from_node.next_node_name = ""
		else:
			from_node.next_node_fail = ""
	else:
		from_node.next_node_name = ""
		
	graph_edit.disconnect_node(from_node_id, from_port, to_node_id, to_port)

func _on_delete_nodes_request(nodes):
	for node_name_in_scene in nodes:
		var gnode = graph_edit.get_node(node_name_in_scene)
		if gnode:
			var action_node = gnode.get_meta("action_node")
			if action_node:
				current_flow.nodes.erase(action_node)
			gnode.queue_free()
			
			# Disconnect related
			# (Simple way: just let them be broken references, or clean up)
			# GraphEdit removes visual connections automatically.
			# We should clean up data references in other nodes pointing to this one.
			for n in current_flow.nodes:
				if n.next_node_name == action_node.id: n.next_node_name = ""
				if n is WaitActionNode and n.next_node_fail == action_node.id: n.next_node_fail = ""
	
	selected_node = null

func _on_node_selected(node):
	selected_node = node.get_meta("action_node")
	_load_node_to_inspector(selected_node)

func _on_node_deselected(node):
	pass # Keep inspector showing last selection or clear?

func _get_node_by_id(id: String) -> ActionNode:
	for n in current_flow.nodes:
		if n.id == id: return n
	return null

# --- Inspector Logic ---

func _load_node_to_inspector(n: ActionNode):
	if not n: return
	
	id_edit.text = n.id
	name_edit.text = n.node_name
	type_option.selected = n.get_action_type()
	windup_spin.value = n.windup
	active_spin.value = n.active
	recovery_spin.value = n.recovery
	cost_spin.value = n.cost
	
	if n is WaitActionNode:
		condition_option.selected = n.condition
		param_spin.value = n.param
		condition_option.disabled = false
		param_spin.editable = true
		
		power_spin.value = 0
		toughness_spin.value = 0
		power_spin.editable = false
		toughness_spin.editable = false
	else:
		condition_option.disabled = true
		param_spin.editable = false
		
		power_spin.value = n.get_power()
		toughness_spin.value = n.get_toughness()
		power_spin.editable = true
		toughness_spin.editable = true

func _save_node_data():
	if selected_node:
		selected_node.id = id_edit.text
		selected_node.node_name = name_edit.text
		selected_node.windup = windup_spin.value
		selected_node.active = active_spin.value
		selected_node.recovery = recovery_spin.value
		selected_node.cost = cost_spin.value
		
		if selected_node is AttackActionNode or selected_node is DefendActionNode:
			selected_node.power = power_spin.value
			selected_node.toughness = toughness_spin.value
		
		if selected_node is WaitActionNode:
			selected_node.condition = condition_option.selected
			selected_node.param = param_spin.value
			
		# Update GraphNode Title
		var gnode = graph_edit.get_node_or_null(selected_node.id)
		if gnode:
			gnode.title = selected_node.node_name + " (" + selected_node.id + ")"

func _on_type_changed(type_idx):
	if not selected_node: return
	if selected_node.get_action_type() == type_idx: return
	
	# Replace node logic (same as before)
	var new_node: ActionNode
	match type_idx:
		ActionNode.Type.ATTACK: new_node = AttackActionNode.new()
		ActionNode.Type.DEFEND: new_node = DefendActionNode.new()
		ActionNode.Type.DODGE: new_node = DodgeActionNode.new()
		ActionNode.Type.WAIT: new_node = WaitActionNode.new()
	
	# Copy data
	new_node.id = selected_node.id
	new_node.node_name = selected_node.node_name
	new_node.next_node_name = selected_node.next_node_name
	new_node.graph_position = selected_node.graph_position # Keep pos
	new_node.windup = selected_node.windup
	new_node.active = selected_node.active
	new_node.recovery = selected_node.recovery
	new_node.cost = selected_node.cost
	
	if selected_node is WaitActionNode:
		new_node.next_node_name = selected_node.next_node_name
		# fail node lost if switching away from Wait
	
	# Replace in array
	var idx = current_flow.nodes.find(selected_node)
	if idx != -1:
		current_flow.nodes[idx] = new_node
		selected_node = new_node
		_refresh_graph() # Rebuild graph to update ports
		_load_node_to_inspector(selected_node)

func _on_save_flow():
	var path = filename_edit.text
	var err = ResourceSaver.save(current_flow, path)
	if err == OK:
		print("Saved to " + path)
	else:
		print("Error saving: " + str(err))

func _on_load_flow():
	var path = filename_edit.text
	if ResourceLoader.exists(path):
		current_flow = ResourceLoader.load(path)
		_refresh_graph()
		print("Loaded from " + path)
	else:
		print("File not found: " + path)
