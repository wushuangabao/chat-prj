class_name ActionQueueDisplay
extends HBoxContainer

var node_panels: Dictionary = {} # node_name -> PanelContainer

func setup(root_node: ActionNode):
	# 清除旧的显示
	for child in get_children():
		child.queue_free()
	node_panels.clear()
	
	if root_node == null: return
	
	# 遍历节点链表，按顺序显示
	# 注意：这假设是一个简单的链表结构。如果是复杂的树，可能只显示当前路径。
	# 为了演示，我们尝试从 root 开始遍历显示最多 5 个节点
	
	var current_node = root_node
	var steps = 0
	
	# 使用一个集合防止无限循环
	var visited = []
	
	while steps < 6: # 最多显示6个
		if current_node == null:
			break
			
		# 创建节点显示
		var panel = PanelContainer.new()
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = Color.GRAY
		panel.add_theme_stylebox_override("panel", style)
		
		var lbl = Label.new()
		lbl.text = current_node.node_name
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(lbl)
		
		add_child(panel)
		
		# 存储引用以便高亮
		# 使用 id 或 node_name 作为键，这里假设 id 唯一
		var key = current_node.id if current_node.id != "" else current_node.node_name
		node_panels[key] = panel
		
		# 箭头
		if current_node.next_node:
			var arrow = Label.new()
			arrow.text = "->"
			add_child(arrow)
		
		visited.append(current_node)
		current_node = current_node.next_node
		
		if current_node == null or current_node in visited:
			# 如果循环回到已访问节点，显示一个循环标记并结束
			if current_node in visited:
				var loop_lbl = Label.new()
				loop_lbl.text = "(Loop)"
				add_child(loop_lbl)
			break
			
		steps += 1

func highlight_node(node: ActionNode):
	if node == null: return
	var key = node.id if node.id != "" else node.node_name
	
	for name in node_panels:
		var panel = node_panels[name]
		var style = panel.get_theme_stylebox("panel").duplicate()
		
		if name == key:
			style.bg_color = Color(0.8, 0.6, 0.2, 0.9) # 高亮黄
			style.border_color = Color.WHITE
		else:
			style.bg_color = Color(0.2, 0.2, 0.2, 0.8) # 默认灰
			style.border_color = Color.GRAY
			
		panel.add_theme_stylebox_override("panel", style)
