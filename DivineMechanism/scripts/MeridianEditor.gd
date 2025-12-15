extends Control

var current_flow: MeridianFlow
var selected_node: ActionNode
var flows: Dictionary = {} # {"P1": flow, "P2": flow}
var current_char_key: String = ""

# UI Elements
var graph_edit: GraphEdit
var inspector_panel: VBoxContainer
var char_selector: OptionButton # Character Selector
var apply_btn: Button # Make it member variable

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
	# No default flow creation, wait for setup_editor

func setup_editor(p_flows: Dictionary):
	flows = p_flows
	
	char_selector.clear()
	for key in flows.keys():
		char_selector.add_item(key)
	
	if flows.size() > 0:
		_on_char_selected(0)

func _on_char_selected(index):
	var key = char_selector.get_item_text(index)
	current_char_key = key
	current_flow = flows[key]
	_refresh_graph()
	# Clear inspector
	_load_node_to_inspector(null)

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
	
	# Character Selector Area
	var char_area = VBoxContainer.new()
	char_area.custom_minimum_size = Vector2(0, 100)
	right_sidebar.add_child(char_area)
	
	var char_lbl = Label.new()
	char_lbl.text = "Select Character:"
	char_area.add_child(char_lbl)
	
	char_selector = OptionButton.new()
	char_selector.item_selected.connect(_on_char_selected)
	char_area.add_child(char_selector)
	
	var close_btn = Button.new()
	close_btn.text = "Close & Restart"
	close_btn.pressed.connect(_on_close_editor)
	char_area.add_child(close_btn)
	
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
	condition_option.add_item("ENEMY_STATE_WINDUP", WaitActionNode.Condition.ENEMY_STATE_WINDUP)
	p.add_child(condition_option)
	
	param_spin = _create_spin(p, "Param", 1000)
	
	p.add_child(Label.new())
	apply_btn = Button.new()
	apply_btn.text = "Apply Changes"
	apply_btn.visible = false # Hidden by default, readonly mode
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
	# 使用 remove_child + free 立即删除，防止同名节点冲突
	# 因为 queue_free 会延迟到帧末，导致新创建的同名节点被自动重命名，从而破坏连线逻辑
	for child in graph_edit.get_children():
		if child is GraphNode:
			graph_edit.remove_child(child)
			child.free()
	
	# Create nodes
	for n in current_flow.nodes:
		_create_graph_node(n)
	
	# Create connections
	# Wait one frame for nodes to be ready (ports to exist)
	# 虽然节点已立即创建，但 GraphEdit 的端口更新可能仍需一帧
	await get_tree().process_frame
	
	for n in current_flow.nodes:
		if n.next_node:
			graph_edit.connect_node(n.id, 0, n.next_node.id, 0)
		
		if n is WaitActionNode and n.next_node_fail:
			graph_edit.connect_node(n.id, 1, n.next_node_fail.id, 0)

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
		# 将 type_right 设为 0，以便能连接到其他节点的 Input (type 0)
		gnode.set_slot(2, false, 0, Color.WHITE, true, 0, Color.RED)
		
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
						old_source.next_node = null
					else:
						old_source.next_node_fail = null
				else:
					old_source.next_node = null
			break
	
	# Port 0 is usually the first output port (index 0 of output ports)
	# But in GraphEdit signal, from_port is the index of the port enabled for output.
	# WaitNode: Port 0 (True), Port 1 (False)
	
	if from_node is WaitActionNode:
		if from_port == 0:
			from_node.next_node = to_node
		else:
			from_node.next_node_fail = to_node
	else:
		from_node.next_node = to_node
	
	# Update Graph Visuals
	graph_edit.connect_node(from_node_id, from_port, to_node_id, to_port)

func _on_disconnection_request(from_node_id, from_port, to_node_id, to_port):
	var from_node = _get_node_by_id(from_node_id)
	if not from_node: return
	
	if from_node is WaitActionNode:
		if from_port == 0:
			from_node.next_node = null
		else:
			from_node.next_node_fail = null
	else:
		from_node.next_node = null
		
	graph_edit.disconnect_node(from_node_id, from_port, to_node_id, to_port)

func _on_delete_nodes_request(nodes):
	for node_name_in_scene in nodes:
		var gnode = graph_edit.get_node(str(node_name_in_scene))
		if gnode:
			var action_node = gnode.get_meta("action_node")
			if action_node:
				current_flow.nodes.erase(action_node)
				
				# Clean up data references in other nodes pointing to this one
				for n in current_flow.nodes:
					if n.next_node == action_node: n.next_node = null
					if n is WaitActionNode and n.next_node_fail == action_node: n.next_node_fail = null
			
			gnode.queue_free()
	
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
	# Hide Apply Button
	apply_btn.visible = false
	
	if not n: return
	
	id_edit.text = n.id
	name_edit.text = n.node_name
	type_option.selected = n.get_action_type()
	windup_spin.value = n.windup
	active_spin.value = n.active
	recovery_spin.value = n.recovery
	cost_spin.value = n.cost
	
	# Read-only fields
	id_edit.editable = false
	name_edit.editable = false
	
	type_option.disabled = true
	
	windup_spin.editable = false
	active_spin.editable = false
	recovery_spin.editable = false
	cost_spin.editable = false
	
	power_spin.editable = false
	toughness_spin.editable = false
	
	condition_option.disabled = true
	param_spin.editable = false
	
	if n is WaitActionNode:
		condition_option.selected = n.condition
		param_spin.value = n.param
		
		power_spin.value = 0
		toughness_spin.value = 0
	else:
		# condition_option.disabled = true # Already disabled above
		param_spin.value = 0
		
		power_spin.value = n.get_power()
		toughness_spin.value = n.get_toughness()

func _save_node_data():
	# Now this function only updates the internal data structure from UI,
	# BUT since UI is read-only, we shouldn't be calling this.
	# However, dragging nodes updates positions directly.
	# We might want to remove the Apply button entirely.
	pass

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
	new_node.next_node = selected_node.next_node
	new_node.graph_position = selected_node.graph_position # Keep pos
	new_node.windup = selected_node.windup
	new_node.active = selected_node.active
	new_node.recovery = selected_node.recovery
	new_node.cost = selected_node.cost
	
	if selected_node is WaitActionNode:
		new_node.next_node = selected_node.next_node
		# fail node lost if switching away from Wait
	
	# Replace in array
	var idx = current_flow.nodes.find(selected_node)
	if idx != -1:
		current_flow.nodes[idx] = new_node
		selected_node = new_node
		_refresh_graph() # Rebuild graph to update ports
		_load_node_to_inspector(selected_node)

signal editor_closed

func _on_close_editor():
	visible = false
	editor_closed.emit()
