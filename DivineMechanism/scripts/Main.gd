extends Node2D

var p1: Fighter
var p2: Fighter
var p1_flow: MeridianFlow
var p2_flow: MeridianFlow

@export_group("Meridian Flows")
@export var default_p1_flow: MeridianFlow
@export var default_p2_flow: MeridianFlow

func _ready():
	# 清除旧的存档文件，确保加载新的类结构
	# todo：我们希望保留用户的编辑，但前提是版本一致，否则会加载错误的类结构
	# if FileAccess.file_exists("user://p1_flow.res"):
	# 	DirAccess.remove_absolute("user://p1_flow.res")
	# if FileAccess.file_exists("user://p2_flow.res"):
	# 	DirAccess.remove_absolute("user://p2_flow.res")

	# 创建战士
	p1 = Fighter.new()
	p1.name = "P1"
	p1.position = Vector2(300, 400)
	add_child(p1)
	
	p2 = Fighter.new()
	p2.name = "P2"
	p2.position = Vector2(600, 400) # 3米距离 (300像素)
	add_child(p2)
	
	# 设置 P1
	p1_flow = _load_or_create_flow("p1_flow.res", default_p1_flow)
	p1.init("赵无极", 200, p1_flow.starting_node)
	
	# 设置 P2
	p2_flow = _load_or_create_flow("p2_flow.res", default_p2_flow)
	p2.init("张无忌", 200, p2_flow.starting_node)
	
	# 建立链接
	p1.set_enemy(p2)
	p2.set_enemy(p1)
	
	# 设置摄像机
	var cam_script = load("res://scripts/GameCamera.gd")
	var cam = Camera2D.new()
	cam.set_script(cam_script)
	add_child(cam)
	cam.make_current()
	
	var targets: Array[Node2D] = [p1, p2]
	cam.setup(targets)
	
	setup_hud()

	# 设置处理模式，确保暂停时也能响应输入
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# 让战士和摄像机在暂停时停止 (覆盖继承的 ALWAYS)
	p1.process_mode = Node.PROCESS_MODE_PAUSABLE
	p2.process_mode = Node.PROCESS_MODE_PAUSABLE
	cam.process_mode = Node.PROCESS_MODE_PAUSABLE
	
	# 连接日志信号
	p1.log_event.connect(func(msg): _on_log_event(msg, true))
	p2.log_event.connect(func(msg): _on_log_event(msg, false))
	
	# 连接受伤信号
	p1.damage_taken.connect(_on_damage_taken)
	p2.damage_taken.connect(_on_damage_taken)

var time_label: Label
var distance_label: Label
var p1_log_label: Label
var p2_log_label: Label
var p1_log_history: Array = []
var p2_log_history: Array = []

var p1_log_scroll: ScrollContainer
var p2_log_scroll: ScrollContainer
var pause_btn: Button

func setup_hud():
	# 暂停按钮
	pause_btn = Button.new()
	pause_btn.text = "暂停 (Pause)"
	pause_btn.position = Vector2(10, 10)
	pause_btn.process_mode = Node.PROCESS_MODE_ALWAYS # 确保暂停时能点击
	pause_btn.pressed.connect(func():
		get_tree().paused = not get_tree().paused
		pause_btn.text = "继续 (Resume)" if get_tree().paused else "暂停 (Pause)"
		print("游戏暂停" if get_tree().paused else "游戏继续")
	)
	
	var ui_layer = CanvasLayer.new()
	ui_layer.name = "HUDLayer"
	add_child(ui_layer)
	
	# HUD Root
	var hud_root = Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 确保 HUD 不会拦截所有鼠标事件，但其子控件（如按钮）可以接收
	hud_root.mouse_filter = Control.MOUSE_FILTER_PASS 
	ui_layer.add_child(hud_root)
	
	# --- 顶部居中容器 (时间 + 速度 + 距离) ---
	var top_center_container = VBoxContainer.new()
	top_center_container.layout_mode = 1
	top_center_container.anchors_preset = Control.PRESET_TOP_WIDE
	top_center_container.offset_top = 10
	top_center_container.alignment = BoxContainer.ALIGNMENT_BEGIN
	# 容器本身不拦截鼠标，允许穿透点击下面的按钮
	top_center_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(top_center_container)

	# 将暂停按钮放在容器之后添加，确保在最上层
	hud_root.add_child(pause_btn)
	
	# 1. 时间
	time_label = Label.new()
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_center_container.add_child(time_label)
	
	# 2. 游戏速度控制 (HBox)
	var speed_container = HBoxContainer.new()
	speed_container.alignment = BoxContainer.ALIGNMENT_CENTER
	top_center_container.add_child(speed_container)
	
	var speed_label = Label.new()
	speed_label.text = "游戏速度:"
	speed_container.add_child(speed_label)
	
	var speed_slider = HSlider.new()
	speed_slider.min_value = 0.1
	speed_slider.max_value = 2.0
	speed_slider.step = 0.1
	speed_slider.value = 1.0
	speed_slider.custom_minimum_size = Vector2(100, 20)
	# SIZE_CENTER does not exist. Use SIZE_SHRINK_CENTER or similar flag logic.
	# Actually size_flags_vertical is an int bitmask.
	# To center vertically in container: SIZE_SHRINK_CENTER
	speed_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	speed_slider.process_mode = Node.PROCESS_MODE_ALWAYS
	speed_slider.value_changed.connect(func(val): Engine.time_scale = val)
	speed_container.add_child(speed_slider)
	
	# 3. 距离
	distance_label = Label.new()
	distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	distance_label.modulate = Color(0.8, 1.0, 0.8) # 淡绿色
	top_center_container.add_child(distance_label)

	var editor_btn = Button.new()
	editor_btn.text = "经脉编程 (Editor)"
	# 将按钮移到顶部提示文字的右侧，避免遮挡日志
	editor_btn.position = Vector2(220, 5)
	# 确保在暂停模式下按钮仍然可以响应点击
	editor_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	editor_btn.pressed.connect(_open_editor)
	hud_root.add_child(editor_btn)
	
	var restart_btn = Button.new()
	restart_btn.text = "重启战斗 (Restart)"
	restart_btn.position = Vector2(380, 5)
	restart_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	restart_btn.pressed.connect(_on_restart_pressed)
	hud_root.add_child(restart_btn)
	
	# --- P1 日志 (左上) ---
	# Scroll Container
	p1_log_scroll = ScrollContainer.new()
	p1_log_scroll.custom_minimum_size = Vector2(440, 450)
	p1_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p1_log_scroll.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p1_log_scroll.offset_left = 20
	p1_log_scroll.offset_top = 50
	hud_root.add_child(p1_log_scroll)
	
	p1_log_label = Label.new()
	p1_log_label.modulate = Color(1.0, 0.8, 0.8, 0.9) # 淡红
	p1_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p1_log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL # 必须设置水平扩展
	p1_log_scroll.add_child(p1_log_label)
	
	# --- P2 日志 (右上) ---
	p2_log_scroll = ScrollContainer.new()
	p2_log_scroll.custom_minimum_size = Vector2(440, 450) # 1.1倍宽, 1.5倍高
	p2_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p2_log_scroll.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p2_log_scroll.offset_right = -20
	p2_log_scroll.offset_top = 50
	# 右对齐布局修正：使用 grow_horizontal = BEGIN 让它向左延伸
	p2_log_scroll.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	
	hud_root.add_child(p2_log_scroll)
	
	p2_log_label = Label.new()
	p2_log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p2_log_label.modulate = Color(0.8, 0.8, 1.0, 0.9) # 淡蓝
	p2_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p2_log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL # 必须设置水平扩展，否则ScrollContainer会把它压得很窄
	p2_log_scroll.add_child(p2_log_label)
	
	# --- P1 容器 (左下) ---
	var p1_container = VBoxContainer.new()
	p1_container.layout_mode = 1 # Anchors
	p1_container.anchors_preset = Control.PRESET_BOTTOM_LEFT
	p1_container.offset_left = 20
	p1_container.offset_bottom = -20
	p1_container.grow_vertical = Control.GROW_DIRECTION_BEGIN # 向上增长
	hud_root.add_child(p1_container)
	
	# 1. Action Queue (最上方)
	var p1_queue = ActionQueueDisplay.new()
	p1_container.add_child(p1_queue)
	
	# 2. HUD (中间)
	var p1_hud_script = load("res://scripts/FighterHUD.gd")
	var p1_hud = p1_hud_script.new()
	p1_hud.is_left_aligned = true
	# p1_container.add_child(p1_hud) # 延迟添加，见下方
	p1_hud.setup(p1)
	p1_container.add_child(p1_hud)
	
	# 3. Timeline (最下方)
	# 添加一个间隔，防止Timeline紧贴HUD文字
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 10
	p1_container.add_child(spacer)
	
	var p1_tl = TimelineDisplay.new()
	p1_tl.custom_minimum_size = Vector2(0, 30) # 减小高度，因为移除了文字
	p1_tl.setup(p1)
	p1_container.add_child(p1_tl)
	
	# 移除旧的 stats label
	# 传递 p1_hud 给 fighter，让 fighter 更新 HUD 上的 state label
	p1.assign_ui(p1_hud, p1_queue)
	
	# --- P2 容器 (右下) ---
	var p2_container = VBoxContainer.new()
	p2_container.layout_mode = 1
	p2_container.anchors_preset = Control.PRESET_BOTTOM_RIGHT
	p2_container.offset_right = -20
	p2_container.offset_bottom = -20
	p2_container.grow_horizontal = Control.GROW_DIRECTION_BEGIN # 向左增长
	p2_container.grow_vertical = Control.GROW_DIRECTION_BEGIN # 向上增长
	hud_root.add_child(p2_container)
	
	# 1. Queue
	var p2_queue = ActionQueueDisplay.new()
	p2_container.add_child(p2_queue)
	
	# 2. HUD
	var p2_hud = p1_hud_script.new()
	p2_hud.is_left_aligned = false
	# p2_container.add_child(p2_hud) # 延迟添加
	p2_hud.setup(p2)
	p2_container.add_child(p2_hud)
	
	# 3. Timeline
	# 间隔
	var spacer2 = Control.new()
	spacer2.custom_minimum_size.y = 10
	p2_container.add_child(spacer2)
	
	var p2_tl = TimelineDisplay.new()
	p2_tl.custom_minimum_size = Vector2(0, 30)
	p2_tl.setup(p2)
	p2_container.add_child(p2_tl)
	
	p2.assign_ui(p2_hud, p2_queue)

func _on_damage_taken(amount: float, pos: Vector2, is_crit: bool):
	var floating_text = FloatingText.new()
	
	# 为了让飘字跟随角色移动，我们需要找到发出信号的角色节点，并将飘字作为其子节点添加。
	# 但是 damage_taken 信号只传递了位置，没有传递来源实例。
	# 我们可以通过比较 pos 和 p1/p2 的 global_position 来判断是谁受伤了？
	# 或者，最简单的：修改 damage_taken 信号，传递 self。
	# 但由于之前的指令要求简化参数，我们可以在这里做简单的距离判断。
	
	var target_fighter = p1
	if pos.distance_squared_to(p2.global_position) < pos.distance_squared_to(p1.global_position):
		target_fighter = p2
		
	target_fighter.add_child(floating_text)
	
	# ... (省略坐标转换注释)
	
	# 统一使用红色，仅在暴击时加粗/变大
	var color = Color(1, 0.2, 0.2) # 统一为红色
	if is_crit:
		floating_text.scale = Vector2(1.5, 1.5) # 暴击放大
		color = Color(1, 0.0, 0.0) # 暴击更鲜艳的红
	else:
		floating_text.scale = Vector2(1.0, 1.0)
		color = Color(1, 0.5, 0.5) # 普通伤害稍微淡一点的红
	
	# 确定飘动方向：
	# 基于屏幕位置：如果在屏幕左侧，往左上飘；在右侧，往右上飘
	# 注意：现在 floating_text 是角色的子节点，position 是局部坐标。
	# 我们需要根据角色在屏幕上的位置来决定方向。
	# 另外，pos 参数是全局坐标。我们需要将其转换为局部坐标，通常是 (0, 0) 附近（头顶）。
	
	var screen_x = target_fighter.get_global_transform_with_canvas().origin.x
	var center_x = get_viewport_rect().size.x / 2.0
	var drift_dir = Vector2(-0.5, -1) if screen_x < center_x else Vector2(0.5, -1)
	drift_dir = drift_dir.normalized()
	
	# 局部坐标起始点：在头顶上方一点
	# 假设角色原点在脚底，高100。
	var local_start_pos = Vector2(0, -120)
	
	# 加上一点随机偏移
	var offset = Vector2(randf_range(-10, 10), randf_range(-10, -20))
	floating_text.setup(int(amount), local_start_pos + offset, color, drift_dir)

func _on_log_event(msg: String, is_p1: bool):
	var timestamp = "%.2fs" % elapsed_time
	# 获取当前距离 (由于Godot每帧更新位置，日志触发时位置可能已经微调，但对于"位移前"的精确判定需要更复杂的快照逻辑。
	# 不过对于大多数逻辑日志（如起手、判定开始），此时位置尚未发生大幅突变，直接获取当前距离近似为"事件发生时的距离"。
	# 如果是"位移发生前"，比如突进开始时，日志是在开始前打印的，所以当前距离就是位移前的距离。)
	var dist = p1.get_distance_to_enemy()
	var log_line = "[%s|%.1fm] %s" % [timestamp, dist, msg]
	
	if is_p1:
		p1_log_history.append(log_line)
		# 移除数量上限，因为有了 ScrollContainer
		
		var text = ""
		for line in p1_log_history:
			text += line + "\n"
		p1_log_label.text = text
		
		# 自动滚动到底部
		await get_tree().process_frame
		p1_log_scroll.scroll_vertical = p1_log_scroll.get_v_scroll_bar().max_value
	else:
		p2_log_history.append(log_line)
		# 移除数量上限
		
		var text = ""
		for line in p2_log_history:
			text += line + "\n"
		p2_log_label.text = text
		
		# 自动滚动到底部
		await get_tree().process_frame
		p2_log_scroll.scroll_vertical = p2_log_scroll.get_v_scroll_bar().max_value

var elapsed_time: float = 0.0

func _process(delta):
	# 即使暂停，update_time 也会运行，因为 Main 是 PROCESS_MODE_ALWAYS
	# 如果想暂停时时间也停止，需要判断 paused
	var dist = p1.get_distance_to_enemy()
	distance_label.text = "距离: %.1fm" % dist
	
	if not get_tree().paused:
		elapsed_time += delta
		time_label.text = "时间: %.2fs" % elapsed_time
	else:
		time_label.text = "时间: %.2fs (暂停)" % elapsed_time

	# 游戏结束检查
	if p1.hp <= 0:
		set_process(false)
		print("张无忌 获胜!")
	elif p2.hp <= 0:
		set_process(false)
		print("赵无极 获胜!")

func _on_restart_pressed():
	print("正在重启战斗...")
	get_tree().paused = false
	get_tree().reload_current_scene()

func _open_editor():
	# 打开编辑器时自动暂停
	if not get_tree().paused:
		get_tree().paused = true
		if pause_btn:
			pause_btn.text = "继续 (Resume)"
		print("游戏暂停 (Editor Opened)")

	# Check if editor already exists
	var editor
	if get_node("HUDLayer").has_node("MeridianEditor"):
		editor = get_node("HUDLayer/MeridianEditor")
		editor.visible = true
	else:
		var editor_scene = load("res://scenes/MeridianEditor.tscn")
		editor = editor_scene.instantiate()
		# 确保编辑器在暂停时也能运行
		editor.process_mode = Node.PROCESS_MODE_ALWAYS
		editor.name = "MeridianEditor" # Ensure consistent naming
		get_node("HUDLayer").add_child(editor)
		
		# Connect close signal to resume game (optional, or just handle manually)
		editor.editor_closed.connect(restart_battle)
	
	# Pass data to editor
	# We pass references to the MeridianFlow objects so changes are live (in memory)
	# If we want to persist, Main needs to handle saving eventually, or Editor saves internally to memory.
	# The flows are Resources, so they are passed by reference.
	var flow_map = {
		"赵无极 (P1)": p1_flow,
		"张无忌 (P2)": p2_flow
	}
	editor.setup_editor(flow_map)

func restart_battle():
	ResourceSaver.save(p1_flow, "user://p1_flow.res")
	ResourceSaver.save(p2_flow, "user://p2_flow.res")
	# 复用 _on_restart_pressed 的逻辑
	# 这样无论是点 HUD 按钮，还是编辑器关闭，都执行相同的全场景重载
	# 全场景重载最干净，能重置所有单例、静态变量残留等问题
	_on_restart_pressed()


func _load_or_create_flow(filename: String, default_resource: MeridianFlow) -> MeridianFlow:
	var path = "user://" + filename
	var flow: MeridianFlow = null
	
	# Try to load existing
	if ResourceLoader.exists(path):
		flow = ResourceLoader.load(path)
	
	# If failed or invalid (check starting_node), fallback to default
	if flow == null or flow.starting_node == null:
		# If default provided, try to use it (but we know it might be broken due to script changes)
		if default_resource and default_resource.starting_node != null:
			flow = default_resource.duplicate(true)
		else:
			# Rebuild demo flow programmatically
			if "p1" in filename:
				flow = _create_demo_flow_p1()
			else:
				flow = _create_demo_flow_p2()
		
		var err = ResourceSaver.save(flow, path, ResourceSaver.FLAG_CHANGE_PATH)
		if err != OK:
			printerr("Failed to save flow to ", path, " Error: ", err)
	
	return flow

func _create_demo_flow_p1() -> MeridianFlow:
	var flow = MeridianFlow.new()
	flow.flow_name = "P1 Heavy Demo"
	
	# "开山斧"
	var n1 = AttackActionNode.new()
	n1.id = "p1_heavy_atk"
	n1.node_name = "开山斧"
	n1.windup = 1.0
	n1.active = 0.2
	n1.recovery = 1.0
	n1.cost = 30.0
	n1.power = 50.0
	n1.toughness = 25.0
	n1.atk_range = 1.5
	n1.dash = 0.5
	n1.knockback = 2.0
	
	n1.next_node = n1 # Loop
	
	flow.starting_node = n1
	flow.nodes.clear()
	flow.nodes.append(n1)
	return flow

func _create_demo_flow_p2() -> MeridianFlow:
	var flow = MeridianFlow.new()
	flow.flow_name = "P2 Agile Demo"
	
	# 1. 刺
	var n1 = AttackActionNode.new()
	n1.id = "p2_atk1"
	n1.node_name = "太极剑·刺"
	n1.windup = 0.3
	n1.active = 0.1
	n1.recovery = 0.3
	n1.cost = 15.0
	n1.power = 15.0
	n1.atk_range = 0.8
	n1.dash = 1.0
	n1.knockback = 0.2
	
	# 2. 挑
	var n2 = AttackActionNode.new()
	n2.id = "p2_atk2"
	n2.node_name = "太极剑·挑"
	n2.windup = 0.3
	n2.active = 0.1
	n2.recovery = 0.3
	n2.cost = 15.0
	n2.power = 15.0
	n2.atk_range = 0.8
	n2.dash = 0.5
	n2.knockback = 0.2
	
	# 3. 闪
	var n3 = DodgeActionNode.new()
	n3.id = "p2_dodge"
	n3.node_name = "梯云纵"
	n3.windup = 0.1
	n3.active = 0.5
	n3.recovery = 0.2
	n3.cost = 20.0
	n3.backdash = 2.0
	
	# Connections
	n1.next_node = n2
	n2.next_node = n3
	n3.next_node = n1 # Loop back to start
	
	flow.starting_node = n1
	flow.nodes.clear()
	flow.nodes.append_array([n1, n2, n3])
	return flow

# _create_default_p1_flow and _create_default_p2_flow are removed
