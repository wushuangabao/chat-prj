extends Control

var current_flow: MeridianFlow
var selected_node: ActionNode

# UI Elements
var node_list: ItemList
var id_edit: LineEdit
var name_edit: LineEdit
var type_option: OptionButton
var windup_spin: SpinBox
var active_spin: SpinBox
var recovery_spin: SpinBox
var power_spin: SpinBox
var toughness_spin: SpinBox
var cost_spin: SpinBox
var next_node_edit: LineEdit

var filename_edit: LineEdit

func _ready():
	_setup_ui()
	_create_new_flow()

func _setup_ui():
	var root = HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	
	# --- Left Panel: Node List ---
	var left_panel = VBoxContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(left_panel)
	
	var add_btn = Button.new()
	add_btn.text = "Add Node"
	add_btn.pressed.connect(_on_add_node)
	left_panel.add_child(add_btn)
	
	var remove_btn = Button.new()
	remove_btn.text = "Remove Node"
	remove_btn.pressed.connect(_on_remove_node)
	left_panel.add_child(remove_btn)
	
	node_list = ItemList.new()
	node_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	node_list.item_selected.connect(_on_node_selected)
	left_panel.add_child(node_list)
	
	# --- Middle Panel: Inspector ---
	var mid_panel = VBoxContainer.new()
	mid_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(mid_panel)
	
	id_edit = _create_field(mid_panel, "ID")
	name_edit = _create_field(mid_panel, "Name")
	
	mid_panel.add_child(Label.new()) # Spacer
	var type_label = Label.new()
	type_label.text = "Type"
	mid_panel.add_child(type_label)
	type_option = OptionButton.new()
	type_option.add_item("ATTACK", ActionNode.Type.ATTACK)
	type_option.add_item("DEFEND", ActionNode.Type.DEFEND)
	type_option.add_item("DODGE", ActionNode.Type.DODGE)
	type_option.add_item("WAIT", ActionNode.Type.WAIT)
	type_option.item_selected.connect(_on_data_changed_dummy)
	mid_panel.add_child(type_option)
	
	windup_spin = _create_spin(mid_panel, "Windup")
	active_spin = _create_spin(mid_panel, "Active")
	recovery_spin = _create_spin(mid_panel, "Recovery")
	power_spin = _create_spin(mid_panel, "Power", 1000)
	toughness_spin = _create_spin(mid_panel, "Toughness", 1000)
	cost_spin = _create_spin(mid_panel, "Cost", 1000)
	
	next_node_edit = _create_field(mid_panel, "Next Node ID")
	
	var apply_btn = Button.new()
	apply_btn.text = "Apply Changes"
	apply_btn.pressed.connect(_save_node_data)
	mid_panel.add_child(apply_btn)
	
	# --- Right Panel: File Ops ---
	var right_panel = VBoxContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right_panel)
	
	filename_edit = LineEdit.new()
	filename_edit.text = "user://p1_flow.tres"
	right_panel.add_child(filename_edit)
	
	var save_btn = Button.new()
	save_btn.text = "Save Flow"
	save_btn.pressed.connect(_on_save_flow)
	right_panel.add_child(save_btn)
	
	var load_btn = Button.new()
	load_btn.text = "Load Flow"
	load_btn.pressed.connect(_on_load_flow)
	right_panel.add_child(load_btn)
	
	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): visible = false)
	right_panel.add_child(close_btn)

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

func _create_new_flow():
	current_flow = MeridianFlow.new()
	_refresh_list()

func _refresh_list():
	node_list.clear()
	for i in range(current_flow.nodes.size()):
		var n = current_flow.nodes[i]
		var txt = n.id if n.id != "" else "[Unnamed]"
		node_list.add_item(txt + " (" + n.node_name + ")")

func _on_add_node():
	var n = ActionNode.new()
	n.id = "node_" + str(current_flow.nodes.size())
	n.node_name = "New Action"
	current_flow.nodes.append(n)
	_refresh_list()

func _on_remove_node():
	if node_list.is_anything_selected():
		var idx = node_list.get_selected_items()[0]
		current_flow.nodes.remove_at(idx)
		_refresh_list()
		selected_node = null

func _on_node_selected(idx):
	selected_node = current_flow.nodes[idx]
	_load_node_to_ui(selected_node)

func _load_node_to_ui(n: ActionNode):
	id_edit.text = n.id
	name_edit.text = n.node_name
	type_option.selected = n.action_type
	windup_spin.value = n.windup
	active_spin.value = n.active
	recovery_spin.value = n.recovery
	power_spin.value = n.power
	toughness_spin.value = n.toughness
	cost_spin.value = n.cost
	next_node_edit.text = n.next_node_name

func _save_node_data():
	if selected_node:
		selected_node.id = id_edit.text
		selected_node.node_name = name_edit.text
		selected_node.action_type = type_option.selected
		selected_node.windup = windup_spin.value
		selected_node.active = active_spin.value
		selected_node.recovery = recovery_spin.value
		selected_node.power = power_spin.value
		selected_node.toughness = toughness_spin.value
		selected_node.cost = cost_spin.value
		selected_node.next_node_name = next_node_edit.text
		_refresh_list()

func _on_data_changed_dummy(val):
	pass

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
		_refresh_list()
		print("Loaded from " + path)
	else:
		print("File not found: " + path)
