extends Node2D

var p1: Fighter
var p2: Fighter
var p1_flow: MeridianFlow
var p2_flow: MeridianFlow

func _ready():
	# 清除旧的存档文件，确保加载新的类结构
	# 在实际项目中应该有版本迁移逻辑，这里简单起见直接删除
	if FileAccess.file_exists("user://p1_flow.tres"):
		DirAccess.remove_absolute("user://p1_flow.tres")
	if FileAccess.file_exists("user://p2_flow.tres"):
		DirAccess.remove_absolute("user://p2_flow.tres")

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
	p1_flow = _load_or_create_flow("p1_flow.tres", _create_default_p1_flow)
	p1.init("赵无极", 200, p1_flow.get_nodes_as_dict(), p1_flow.starting_node_id)
	
	# 设置 P2
	p2_flow = _load_or_create_flow("p2_flow.tres", _create_default_p2_flow)
	p2.init("张无忌", 200, p2_flow.get_nodes_as_dict(), p2_flow.starting_node_id)
	
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

var time_label: Label
var distance_label: Label
var p1_log_label: Label
var p2_log_label: Label
var p1_log_history: Array = []
var p2_log_history: Array = []

var p1_log_scroll: ScrollContainer
var p2_log_scroll: ScrollContainer

func setup_hud():
	# 暂停提示
	var hint = Label.new()
	hint.text = "按 SPACE 暂停/继续"
	hint.position = Vector2(10, 10)
	
	var ui_layer = CanvasLayer.new()
	ui_layer.name = "HUDLayer"
	add_child(ui_layer)
	
	# HUD Root
	var hud_root = Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(hud_root)
	
	hud_root.add_child(hint)
	
	# --- 顶部居中容器 (时间 + 距离) ---
	var top_center_container = VBoxContainer.new()
	top_center_container.layout_mode = 1
	top_center_container.anchors_preset = Control.PRESET_TOP_WIDE
	top_center_container.offset_top = 10
	top_center_container.alignment = BoxContainer.ALIGNMENT_BEGIN
	# 设置鼠标过滤器为 IGNORE，防止透明区域遮挡下层按钮
	top_center_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(top_center_container)
	
	time_label = Label.new()
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_center_container.add_child(time_label)
	
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
	
	var p1_queue = ActionQueueDisplay.new()
	var p1_stats = Label.new()
	p1_container.add_child(p1_queue)
	p1_container.add_child(p1_stats)
	p1.assign_ui(p1_stats, p1_queue)
	
	# --- P2 容器 (右下) ---
	var p2_container = VBoxContainer.new()
	p2_container.layout_mode = 1
	p2_container.anchors_preset = Control.PRESET_BOTTOM_RIGHT
	p2_container.offset_right = -20
	p2_container.offset_bottom = -20
	p2_container.grow_horizontal = Control.GROW_DIRECTION_BEGIN # 向左增长
	p2_container.grow_vertical = Control.GROW_DIRECTION_BEGIN # 向上增长
	hud_root.add_child(p2_container)
	
	var p2_queue = ActionQueueDisplay.new()
	var p2_stats = Label.new()
	p2_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p2_container.add_child(p2_queue)
	p2_container.add_child(p2_stats)
	p2.assign_ui(p2_stats, p2_queue)

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

	# 暂停逻辑
	if Input.is_action_just_pressed("ui_accept"): # 默认 Space 是 ui_accept
		get_tree().paused = not get_tree().paused
		print("游戏暂停" if get_tree().paused else "游戏继续")

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
	var editor_scene = load("res://scenes/MeridianEditor.tscn")
	var editor = editor_scene.instantiate()
	# 确保编辑器在暂停时也能运行
	editor.process_mode = Node.PROCESS_MODE_ALWAYS
	get_node("HUDLayer").add_child(editor)

func _load_or_create_flow(filename: String, factory_func: Callable) -> MeridianFlow:
	var path = "user://" + filename
	if ResourceLoader.exists(path):
		return ResourceLoader.load(path)
	else:
		var flow = factory_func.call()
		ResourceSaver.save(flow, path)
		return flow

func _create_default_p1_flow() -> MeridianFlow:
	var flow = MeridianFlow.new()
	flow.flow_name = "赵无极 - 重剑流"
	flow.starting_node_id = "start"
	
	var heavy_atk = AttackActionNode.new("开山斧", 1.0, 0.2, 1.0, 50, 25.0, 30.0, 1.5, 0.5, 2.0)
	heavy_atk.id = "start"
	# heavy_atk.set_next("start") # 不再需要手动闭环
	flow.nodes.append(heavy_atk)
	
	return flow

func _create_default_p2_flow() -> MeridianFlow:
	var flow = MeridianFlow.new()
	flow.flow_name = "张无忌 - 敏捷流"
	flow.starting_node_id = "start"
	
	var light_atk1 = AttackActionNode.new("太极剑·刺", 0.3, 0.1, 0.3, 15, 0.0, 15.0, 0.8, 1.0, 0.2)
	light_atk1.id = "start"
	light_atk1.set_next("atk2")
	
	var light_atk2 = AttackActionNode.new("太极剑·挑", 0.3, 0.1, 0.3, 15, 0.0, 15.0, 0.8, 0.5, 0.2)
	light_atk2.id = "atk2"
	light_atk2.set_next("dodge")
	
	var dodge = DodgeActionNode.new("梯云纵", 0.1, 0.5, 0.2, 20.0, 2.0, 0.0)
	dodge.id = "dodge"
	# dodge.set_next("start") # 不再需要手动闭环
	
	flow.nodes.append(light_atk1)
	flow.nodes.append(light_atk2)
	flow.nodes.append(dodge)
	
	return flow
