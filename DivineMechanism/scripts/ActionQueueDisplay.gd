class_name ActionQueueDisplay
extends HBoxContainer

var node_panels: Dictionary = {} # node_name -> PanelContainer

func setup(nodes: Dictionary, root_node_name: String):
	# 清除旧的显示
	for child in get_children():
		child.queue_free()
	node_panels.clear()
	
	# 遍历节点链表，按顺序显示
	# 注意：这假设是一个简单的链表结构。如果是复杂的树，可能只显示当前路径。
	# 为了演示，我们尝试从 root 开始遍历显示最多 5 个节点
	
	var current_name = root_node_name
	var steps = 0
	
	# 使用一个集合防止无限循环
	var visited = []
	
	while steps < 6: # 最多显示6个
		if not nodes.has(current_name):
			break
			
		var action_node = nodes[current_name]
		
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
		lbl.text = action_node.node_name
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(lbl)
		
		add_child(panel)
		
		# 存储引用以便高亮
		# 如果有重复节点名（循环），我们需要处理一下键名，或者每次都刷新整个列表？
		# 简单起见，我们存储所有的 panel，用名字做 key 可能会冲突。
		# 既然是静态显示链条，我们还是只在初始化时创建一次。
		# 如果是循环链表，我们只显示一部分。
		node_panels[current_name] = panel
		
		# 箭头
		if action_node.next_node_name != "":
			var arrow = Label.new()
			arrow.text = "->"
			add_child(arrow)
		
		visited.append(current_name)
		current_name = action_node.next_node_name
		if current_name == "" or current_name in visited:
			# 如果循环回到已访问节点，显示一个循环标记并结束
			if current_name in visited:
				var loop_lbl = Label.new()
				loop_lbl.text = "(Loop)"
				add_child(loop_lbl)
			break
			
		steps += 1

func highlight_node(node_name: String):
	for name in node_panels:
		var panel = node_panels[name]
		var style = panel.get_theme_stylebox("panel").duplicate()
		
		if name == node_name:
			style.bg_color = Color(0.8, 0.6, 0.2, 0.9) # 高亮黄
			style.border_color = Color.WHITE
		else:
			style.bg_color = Color(0.2, 0.2, 0.2, 0.8) # 默认灰
			style.border_color = Color.GRAY
			
		panel.add_theme_stylebox_override("panel", style)
