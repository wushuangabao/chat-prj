class_name Fighter
extends Node2D

enum State {
	IDLE,     # 待机
	MOVE,     # 移动
	WINDUP,   # 前摇
	ACTIVE,   # 判定
	RECOVERY, # 后摇
	STUNNED   # 僵直
}

# 属性
var fighter_name: String
var max_hp: float
var hp: float
var max_stamina: float = 100.0
var stamina: float = 100.0
var stamina_regen: float = 20.0

# 状态
var current_state: int = State.IDLE
var state_timer: float = 0.0
var stun_duration: float = 0.0

# 战斗逻辑
var nodes: Dictionary = {}
var root_node_name: String = "start"
var current_node_name: String = "start"
var current_action_node: ActionNode = null

var poise_damage_accumulator: float = 0.0
var last_hit_time: float = -999.0

# 引用
var enemy: Fighter

# 视觉表现
var color_rect: ColorRect
# UI 引用 (由外部 Main.gd 分配)
var ui_stats_label: Label
var ui_action_queue: ActionQueueDisplay

signal log_event(msg: String)

func _ready():
	# 创建简单的视觉元素
	color_rect = ColorRect.new()
	color_rect.size = Vector2(50, 100)
	color_rect.position = Vector2(-25, -50) # 垂直居中
	add_child(color_rect)

func debug_log(msg: String):
	print(msg)
	log_event.emit(msg)

func assign_ui(stats_label: Label, action_queue: ActionQueueDisplay):
	ui_stats_label = stats_label
	ui_action_queue = action_queue

func init(p_name: String, p_hp: float, p_nodes: Dictionary, p_root: String):
	fighter_name = p_name
	max_hp = p_hp
	hp = p_hp
	nodes = p_nodes
	root_node_name = p_root
	current_node_name = root_node_name
	
	# 根据名字设置演示用的颜色
	if "赵" in p_name: color_rect.color = Color(0.8, 0.2, 0.2) # 红色
	else: color_rect.color = Color(0.2, 0.2, 0.8) # 蓝色
	
	# 初始化队列显示 (如果在 init 之前已经 assign_ui)
	if ui_action_queue:
		ui_action_queue.setup(nodes, root_node_name)
		ui_action_queue.highlight_node(current_node_name)

func set_enemy(p_enemy: Fighter):
	enemy = p_enemy

func take_damage(damage: float, is_interrupt: bool) -> bool:
	hp -= damage
	# 视觉反馈
	var tw = create_tween()
	tw.tween_property(color_rect, "modulate", Color.RED, 0.1)
	tw.tween_property(color_rect, "modulate", Color.WHITE, 0.1)
	
	var interrupted = false
	
	if is_interrupt:
		# 特殊检查：闪避动作不可被打断
		if current_action_node and current_action_node.get_action_type() == ActionNode.Type.DODGE:
			debug_log("[%s] 闪避中，免疫打断!" % fighter_name)
			return false

		poise_damage_accumulator += damage
		var toughness_value = 0.0
		# 只有在 WINDUP 和 ACTIVE 阶段才有霸体保护
		# 后摇(RECOVERY)阶段视为失去架势，韧性为0，极易被破防
		if current_action_node and current_state in [State.WINDUP, State.ACTIVE]:
			toughness_value = current_action_node.get_toughness()
		
		if poise_damage_accumulator > toughness_value:
			var actual_stun = damage * 0.05
			enter_stunned(actual_stun)
			poise_damage_accumulator = 0.0
			debug_log("[%s] 被破防! 僵直: %.2f" % [fighter_name, actual_stun])
			interrupted = true
		else:
			debug_log("[%s] 霸体抗住! 累积削韧: %.1f" % [fighter_name, poise_damage_accumulator])
	else:
		debug_log("[%s] 受到伤害 %d" % [fighter_name, damage])
	
	return interrupted

func enter_stunned(duration: float):
	current_state = State.STUNNED
	state_timer = 0.0
	stun_duration = duration
	current_action_node = null
	current_node_name = root_node_name
	
	# 重置高亮
	if ui_action_queue:
		ui_action_queue.highlight_node(current_node_name)

func _process(delta):
	if hp <= 0: return
	
	# 如果敌人已经死了，停止行动
	if enemy and enemy.hp <= 0:
		current_state = State.IDLE
		return
	
	state_timer += delta
	update_stamina(delta)
	update_visuals()
	
	match current_state:
		State.STUNNED:
			process_stunned(delta)
		State.IDLE:
			process_idle(delta)
		State.MOVE:
			process_move(delta)
		State.WINDUP:
			process_windup(delta)
		State.ACTIVE:
			process_active(delta)
		State.RECOVERY:
			process_recovery(delta)

func update_stamina(delta):
	if current_state in [State.IDLE, State.RECOVERY, State.MOVE]:
		stamina = min(max_stamina, stamina + stamina_regen * delta)

func process_stunned(delta):
	var remaining = stun_duration - state_timer
	var ukemi_cost = 40.0
	if remaining > 0.3 and stamina >= ukemi_cost:
		stamina -= ukemi_cost
		current_state = State.IDLE
		state_timer = 0
		debug_log("[%s] 受身!" % fighter_name)
		return
	
	if state_timer >= stun_duration:
		current_state = State.IDLE
		state_timer = 0
		debug_log("[%s] 从僵直中恢复" % fighter_name)

func get_next_action_node():
	var steps = 0
	var temp_name = current_node_name
	
	while steps < 10:
		if not nodes.has(temp_name):
			temp_name = root_node_name
		
		var n = nodes[temp_name]
		return n
		
	return null

func get_distance_to_enemy() -> float:
	if not enemy: return 999.0
	return abs(global_position.x - enemy.global_position.x) / 100.0 # 像素转米 (100px = 1m)

func move_towards_enemy(dist_m: float):
	var dir = 1 if enemy.global_position.x > global_position.x else -1
	var old_pos = global_position.x
	global_position.x += dir * dist_m * 100.0
	# 防止穿模：如果移动后超过了敌人，就停在敌人面前0.1m处
	if (dir == 1 and global_position.x > enemy.global_position.x) or \
	   (dir == -1 and global_position.x < enemy.global_position.x):
		global_position.x = enemy.global_position.x - (dir * 10.0) # 10px = 0.1m


func move_away_from_enemy(dist_m: float):
	var dir = -1 if enemy.global_position.x > global_position.x else 1
	global_position.x += dir * dist_m * 100.0

func process_idle(delta):
	var next_action = get_next_action_node()
	if next_action:
		var dist = get_distance_to_enemy()
		var effective_range = next_action.get_atk_range() + next_action.get_dash()
		
		if next_action.get_atk_range() > 0 and dist > effective_range:
			current_action_node = next_action
			current_state = State.MOVE
			state_timer = 0
			debug_log("[%s] 距离过远 (%.1fm > %.1fm)，开始接近..." % [fighter_name, dist, effective_range])
			return
		
		if stamina >= next_action.cost:
			stamina -= next_action.cost
			current_action_node = next_action
			current_state = State.WINDUP
			state_timer = 0
			poise_damage_accumulator = 0.0
			debug_log("[%s] 起手: 【%s】 (前摇 %.1fs, 突进 %.1fm)" % [fighter_name, next_action.node_name, next_action.windup, next_action.get_dash()])
		else:
			# 耐力不足，休息
			pass

func process_move(delta):
	var move_speed = 3.0 # m/s
	var dist = get_distance_to_enemy()
	
	move_towards_enemy(move_speed * delta)
	
	var node = current_action_node
	var effective_range = node.get_atk_range() + node.get_dash()
	dist = get_distance_to_enemy()
	
	if dist <= effective_range:
		if stamina >= node.cost:
			stamina -= node.cost
			current_state = State.WINDUP
			state_timer = 0
			poise_damage_accumulator = 0.0
			debug_log("[%s] 进入射程 (%.1fm)! 起手: 【%s】" % [fighter_name, dist, node.node_name])
		else:
			current_state = State.IDLE
	
	if dist < 0.5:
		move_away_from_enemy(0.5 - dist)

func process_windup(delta):
	var node = current_action_node
	
	if node.get_dash() > 0:
		var dash_speed = node.get_dash() / node.windup
		move_towards_enemy(dash_speed * delta)
		
	if node.get_backdash() > 0:
		var back_speed = node.get_backdash() / node.windup
		move_away_from_enemy(back_speed * delta)
		
	if state_timer >= node.windup:
		var dist = get_distance_to_enemy()
		# 允许 0.05m 的误差容忍，防止浮点数精度问题导致看起来在范围内却挥空
		# 例如 1.54m 显示为 1.5m，攻击距离 1.5m，应该算命中
		if node.get_atk_range() > 0 and dist > (node.get_atk_range() + 0.05):
			debug_log("[%s] 挥空!" % fighter_name)
			current_state = State.IDLE
			state_timer = 0
			current_action_node = null
			poise_damage_accumulator = 0.0
		else:
			current_state = State.ACTIVE
			state_timer = 0
			perform_hit_check(node)

func process_active(delta):
	var node = current_action_node
	if state_timer >= node.active:
		# 处理分支逻辑
		var next_id = node.next_node_name
		
		if node is WaitActionNode:
			var condition_met = _evaluate_condition(node)
			if condition_met:
				debug_log("[%s] 条件判定通过!" % fighter_name)
			else:
				debug_log("[%s] 条件判定失败 -> 走分支" % fighter_name)
				if node.next_node_fail != "":
					next_id = node.next_node_fail
		
		if next_id != "":
			if not (node is WaitActionNode): # 只有非Wait节点才显示动作完成
				debug_log("[%s] 动作完成 -> 连招取消后摇!" % fighter_name)
				
			current_state = State.IDLE
			state_timer = 0
			current_node_name = next_id
			poise_damage_accumulator = 0.0
			# 高亮下一个节点
			if ui_action_queue:
				ui_action_queue.highlight_node(current_node_name)
		else:
			current_state = State.RECOVERY
			state_timer = 0

func _evaluate_condition(node: WaitActionNode) -> bool:
	match node.condition:
		WaitActionNode.Condition.ALWAYS_TRUE:
			return true
		WaitActionNode.Condition.DISTANCE_GT:
			return get_distance_to_enemy() > node.param
		WaitActionNode.Condition.DISTANCE_LT:
			return get_distance_to_enemy() < node.param
		WaitActionNode.Condition.MY_HP_LT:
			return hp < node.param
		WaitActionNode.Condition.MY_STAMINA_LT:
			return stamina < node.param
		WaitActionNode.Condition.ENEMY_HP_LT:
			if enemy: return enemy.hp < node.param
			return false
		WaitActionNode.Condition.ENEMY_STAMINA_LT:
			if enemy: return enemy.stamina < node.param
			return false
	return true


func perform_hit_check(node: ActionNode):
	debug_log("[%s] 【%s】 出招!" % [fighter_name, node.node_name])
	if node.get_action_type() == ActionNode.Type.ATTACK:
		var hit = true
		var is_int = false
		
		if enemy.current_state == State.ACTIVE and enemy.current_action_node and enemy.current_action_node.get_action_type() == ActionNode.Type.DODGE:
			hit = false
			debug_log(">> 闪避成功!")# 2. 对方在格挡?
		elif enemy.current_state == State.ACTIVE and enemy.current_action_node and enemy.current_action_node.get_action_type() == ActionNode.Type.DEFEND:
			var dmg = int(node.get_power() * 0.2)
			enemy.take_damage(dmg, false)
			debug_log(">> 攻击被格挡，造成 %d 点伤害" % dmg)
			hit = false
			var block_kb = node.get_knockback() * 0.5
			var dist = get_distance_to_enemy()
			if dist < block_kb:
				enemy.move_away_from_enemy(block_kb - dist)
		
		if hit:
			# 只在敌人处于前摇(WINDUP)或后摇(RECOVERY)时触发打断判定
			if enemy.current_state in [State.WINDUP, State.RECOVERY]:
				is_int = true
				# debug_log(">> 试图打断...") # 暂时不输出，等 take_damage 返回结果
			
			var actually_interrupted = enemy.take_damage(node.get_power(), is_int)
			if actually_interrupted:
				debug_log(">> 打断成功!")
			
			if node.get_knockback() > 0:
				var dist = get_distance_to_enemy()
				if dist < node.get_knockback():
					enemy.move_away_from_enemy(node.get_knockback() - dist)

func process_recovery(delta):
	var node = current_action_node
	if state_timer >= node.recovery:
		current_state = State.IDLE
		state_timer = 0
		
		# 如果没有指定下一个节点，自动回到起始节点循环
		if node.next_node_name != "":
			current_node_name = node.next_node_name
		else:
			debug_log("[%s] 流程结束，循环回起点" % fighter_name)
			current_node_name = root_node_name
			
		poise_damage_accumulator = 0.0
		current_action_node = null
		
		# 高亮下一个节点
		if ui_action_queue:
			ui_action_queue.highlight_node(current_node_name)

func update_visuals():
	var state_str = State.keys()[current_state]
	if ui_stats_label:
		ui_stats_label.text = "%s\n生命: %.0f\n耐力: %.0f\n状态: %s" % [fighter_name, hp, stamina, state_str]
		if current_action_node:
			ui_stats_label.text += "\n招式: %s" % current_action_node.node_name
