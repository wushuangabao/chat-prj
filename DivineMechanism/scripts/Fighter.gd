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
const PIXELS_PER_METER = 100.0
const DEFAULT_MAX_STAMINA: float = 200.0 # 全局耐力上限

var fighter_name: String
var max_hp: float
var hp: float
var max_stamina: float = DEFAULT_MAX_STAMINA
var stamina: float = DEFAULT_MAX_STAMINA
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
const RECT_WIDTH = 50.0 # 角色矩形宽度
const RECT_HEIGHT = 100.0
# UI 引用 (由外部 Main.gd 分配)
var ui_hud: Control # 期望是 FighterHUD (Control)
var ui_action_queue: ActionQueueDisplay
var stun_indicator: Node2D # 眩晕指示器

signal log_event(msg: String)
signal hp_changed(val: float, max_val: float)
signal stamina_changed(val: float, max_val: float)
signal poise_changed(accumulator: float, max_toughness: float)
signal damage_taken(amount: float, pos: Vector2, is_crit: bool)

func _ready():
	# 创建简单的视觉元素
	color_rect = ColorRect.new()
	color_rect.size = Vector2(RECT_WIDTH, RECT_HEIGHT)
	color_rect.position = Vector2(-RECT_WIDTH/2, -RECT_HEIGHT/2) # 垂直居中
	add_child(color_rect)
	
	# 创建眩晕指示器
	var stun_script = load("res://scripts/StunIndicator.gd")
	if stun_script:
		stun_indicator = stun_script.new()
		# 放在头顶上方 (角色高100，中心在0，所以顶部是-50。再往上移25px左右)
		stun_indicator.position = Vector2(0, -75) 
		add_child(stun_indicator)

func debug_log(msg: String):
	print(msg)
	log_event.emit(msg)

func assign_ui(hud: Control, action_queue: ActionQueueDisplay):
	ui_hud = hud
	ui_action_queue = action_queue

func init(p_name: String, p_hp: float, p_nodes: Dictionary, p_root: String):
	fighter_name = p_name
	max_hp = p_hp
	hp = p_hp
	nodes = p_nodes
	root_node_name = p_root
	current_node_name = root_node_name
	
	last_executed_node_id = ""
	last_wait_branch_target = ""
	last_failed_node_id = ""
	
	hp_changed.emit(hp, max_hp)
	stamina_changed.emit(stamina, max_stamina)
	poise_changed.emit(0.0, 0.0)
	
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
	hp_changed.emit(hp, max_hp)
	
	# 发送受伤信号（用于飘字）
	# 简单的暴击判定逻辑：如果是打断攻击，视为"Critical"（红色/大字体），否则普通（白色/黄色）
	damage_taken.emit(damage, global_position, is_interrupt)
	
	# 视觉反馈
	var tw = create_tween()
	tw.tween_property(color_rect, "modulate", Color.RED, 0.1)
	tw.tween_property(color_rect, "modulate", Color.WHITE, 0.1)
	
	var interrupted = false
	
	if is_interrupt:
		# 特殊检查：闪避动作不可被打断
		if current_action_node and current_action_node.get_action_type() == ActionNode.Type.DODGE:
			debug_log("[%s] 闪避中，免疫打断! (受到伤害: %d)" % [fighter_name, damage])
			return false

		poise_damage_accumulator += damage
		
		var toughness_value = 0.0
		if current_action_node:
			toughness_value = current_action_node.get_toughness()
			
		poise_changed.emit(poise_damage_accumulator, toughness_value)
		
		if poise_damage_accumulator > toughness_value:
			# 僵直计算优化：使用非线性曲线 (Ease-Out)
			# 公式：stun = min + (max - min) * (1 - (1 - t)^3)
			# 其中 t = clamp(damage / 100.0, 0, 1)
			# 这会让僵直时间随着伤害快速增加，然后逐渐趋于平缓
			var t = clamp(damage / 100.0, 0.0, 1.0)
			var curve_factor = 1.0 - pow(1.0 - t, 3.0) # Cubic Ease Out
			var actual_stun = 0.5 + (1.5 * curve_factor) # Range: 0.5s -> 2.0s
			
			enter_stunned(actual_stun)
			poise_damage_accumulator = 0.0
			poise_changed.emit(0.0, 0.0)
			debug_log("[%s] 被破防! 僵直: %.2f" % [fighter_name, actual_stun])
			interrupted = true
		else:
			debug_log("[%s] 霸体抗住! 累积削韧: %.1f" % [fighter_name, poise_damage_accumulator])
	else:
		var state_str = State.keys()[current_state]
		debug_log("[%s] 受到伤害 %d (状态: %s)" % [fighter_name, damage, state_str])
	
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
	
	# 处理击退物理
	if not is_zero_approx(knockback_velocity):
		global_position.x += knockback_velocity * delta * PIXELS_PER_METER # 像素/秒
		
		# 摩擦力衰减
		var sign_before = sign(knockback_velocity)
		knockback_velocity -= sign_before * knockback_friction * delta
		
		# 如果符号改变（过零），则停止
		if sign(knockback_velocity) != sign_before:
			knockback_velocity = 0.0
	
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
	# 允许回复耐力的状态：待机、后摇、移动
	# 特殊情况：如果是 ACTIVE 状态，但执行的是 WaitActionNode (观望)，也允许回复耐力
	var is_waiting = (current_state == State.ACTIVE and current_action_node is WaitActionNode)
	
	if current_state in [State.IDLE, State.RECOVERY, State.MOVE] or is_waiting:
		stamina = min(max_stamina, stamina + stamina_regen * delta)
		stamina_changed.emit(stamina, max_stamina)

func process_stunned(delta):
	if state_timer >= stun_duration:
		current_state = State.IDLE
		state_timer = 0
		debug_log("[%s] 从僵直中恢复，流程重置" % fighter_name)
		current_node_name = root_node_name
		if ui_action_queue:
			ui_action_queue.highlight_node(current_node_name)

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
	
	# 计算中心距离 (像素)
	var center_dist = abs(global_position.x - enemy.global_position.x)
	
	# 减去两个半宽，得到空隙宽度
	# 假设敌我宽度一致，均为 RECT_WIDTH
	var gap = center_dist - RECT_WIDTH
	
	return max(0.0, gap) / PIXELS_PER_METER # 像素转米 (100px = 1m)

func move_towards_enemy(dist_m: float):
	var dir = 1 if enemy.global_position.x > global_position.x else -1
	
	# 目标移动距离 (像素)
	var move_dist_px = dist_m * PIXELS_PER_METER
	
	# 当前中心距离
	var center_dist = abs(global_position.x - enemy.global_position.x)
	
	# 最小允许中心距离 = 两个半宽之和 = RECT_WIDTH
	var min_center_dist = RECT_WIDTH
	
	# 计算实际可移动的最大距离 (不能穿过最小距离)
	var max_move_px = max(0.0, center_dist - min_center_dist)
	
	# 实际移动量
	var actual_move = min(move_dist_px, max_move_px)
	
	global_position.x += dir * actual_move


func move_away_from_enemy(dist_m: float):
	var dir = -1 if enemy.global_position.x > global_position.x else 1
	global_position.x += dir * dist_m * PIXELS_PER_METER

func apply_knockback(dist_m: float, duration: float = 0.2):
	# 如果处于闪避状态，免疫击退
	if current_action_node and current_action_node.get_action_type() == ActionNode.Type.DODGE:
		return
		
	if dist_m <= 0: return
	
	# 击退方向：远离敌人
	var dir = -1 if enemy.global_position.x > global_position.x else 1
	
	# 计算初速度和摩擦力 (假设匀减速运动)
	# d = v0*t/2 => v0 = 2d/t
	# a = v0/t
	var v0 = (dist_m * 2.0) / duration
	knockback_velocity = v0 * dir
	knockback_friction = v0 / duration

# 记录上一次执行的动作类型，用于日志去重
var last_action_type: int = -1
var last_executed_node_id: String = ""
var last_wait_branch_target: String = ""

# 击退相关
var knockback_velocity: float = 0.0
var knockback_friction: float = 0.0
var last_failed_node_id: String = ""

func process_idle(delta):
	var next_action = get_next_action_node()
	if next_action:
		var dist = get_distance_to_enemy()
		var effective_range = next_action.get_atk_range() + next_action.get_dash()
		
		if next_action.get_atk_range() > 0 and dist > effective_range:
			# 只有在耐力充足时才移动，否则直接进入下方的耐力判定失败逻辑
			if stamina >= next_action.cost:
				current_action_node = next_action
				current_state = State.MOVE
				state_timer = 0
				poise_damage_accumulator = 0.0 # 确保进入移动状态时也重置削韧值
				debug_log("[%s] 距离过远 (%.1fm > %.1fm)，开始接近..." % [fighter_name, dist, effective_range])
				return
		
		if stamina >= next_action.cost:
			stamina -= next_action.cost
			stamina_changed.emit(stamina, max_stamina)
			current_action_node = next_action
			current_state = State.WINDUP
			state_timer = 0
			# poise_damage_accumulator = 0.0 # 移至下方统一处理
			# poise_changed.emit(0.0, next_action.get_toughness())
			
			# 检查是否是重复的Wait节点，如果是则跳过日志
			var is_repeated_wait = (next_action.id == last_executed_node_id) and (next_action is WaitActionNode)
			last_executed_node_id = next_action.id
			
			# 确保每次新动作开始时削韧值归零
			poise_damage_accumulator = 0.0
			poise_changed.emit(0.0, next_action.get_toughness())
			
			# 成功执行动作，清除失败记录，并更新动作类型
			# 仅当执行非Wait节点时才清除失败记录，防止Wait节点的成功执行打断了"耐力不足"的去重逻辑
			if not (next_action is WaitActionNode):
				last_failed_node_id = ""
				# 同时也清除Wait分支的记忆，因为我们已经成功进入了该分支的动作
				last_wait_branch_target = ""
			
			last_action_type = next_action.get_action_type()
			
			if not is_repeated_wait:
				if next_action.get_action_type() == ActionNode.Type.DODGE:
					debug_log("[%s] 起手: 【%s】 (前摇 %.1fs, 后撤 %.1fm)" % [fighter_name, next_action.node_name, next_action.windup, next_action.get_backdash()])
				elif next_action.get_action_type() == ActionNode.Type.ATTACK:
					debug_log("[%s] 起手: 【%s】 (前摇 %.1fs, 突进 %.1fm)" % [fighter_name, next_action.node_name, next_action.windup, next_action.get_dash()])
				else:
					debug_log("[%s] 起手: 【%s】" % [fighter_name, next_action.node_name])
		else:
			# 耐力不足，休息，并重置流程回起点
			
			# 如果是尝试执行非Wait动作（如闪避/攻击）失败，强制显示日志，不进行抑制
			# 这样可以避免"Wait切入成功 -> 实际没动"造成的困惑
			var force_log = not (next_action is WaitActionNode)
			
			# 检查是否针对同一个节点重复失败
			var is_same_failure = (next_action.id == last_failed_node_id)
			
			# 仅当 last_action_type 不为特殊值 -2 (表示已进入耐力不足状态) 时，或者强制显示时才日志
			# 同时必须不是针对同一个节点的重复失败
			if (last_action_type != -2 or force_log) and not is_same_failure:
				debug_log("[%s] 耐力不足 (%.0f < %.0f)，无法执行【%s】，重置流程!" % [fighter_name, stamina, next_action.cost, next_action.node_name])
				last_action_type = -2
				last_failed_node_id = next_action.id
				
			current_node_name = root_node_name
			current_action_node = null
			# 高亮下一个节点
			if ui_action_queue:
				ui_action_queue.highlight_node(current_node_name)

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
			stamina_changed.emit(stamina, max_stamina)
			current_state = State.WINDUP
			state_timer = 0
			poise_damage_accumulator = 0.0
			poise_changed.emit(0.0, node.get_toughness())
			debug_log("[%s] 进入射程 (%.1fm)! 起手: 【%s】" % [fighter_name, dist, node.node_name])
		else:
			# 耐力不足，重置流程
			debug_log("[%s] 接近后耐力不足 (%.0f < %.0f)，放弃【%s】，重置流程!" % [fighter_name, stamina, node.cost, node.node_name])
			current_state = State.IDLE
			current_node_name = root_node_name
			current_action_node = null
			if ui_action_queue:
				ui_action_queue.highlight_node(current_node_name)
	
	if dist < 0.5:
		move_away_from_enemy(0.5 - dist)

func process_windup(delta):
	var node = current_action_node
	
	if node.get_dash() > 0:
		var dash_speed = node.get_dash() / node.windup
		move_towards_enemy(dash_speed * delta)
		
	if node.get_backdash() > 0:
		# 移至 Active 阶段执行
		pass
		
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
			poise_changed.emit(0.0, 0.0)
		else:
			current_state = State.ACTIVE
			state_timer = 0
			
			# 如果是闪避动作，施加物理位移（模拟摩擦力，先快后慢）
			if node.get_backdash() > 0:
				var dash_dist = node.get_backdash()
				var dur = node.active
				# d = v0*t/2 => v0 = 2d/t
				var v0 = (dash_dist * 2.0) / dur
				# 击退方向：远离敌人
				var dir = -1 if enemy.global_position.x > global_position.x else 1
				
				# 手动设置击退速度，模拟物理位移
				# 注意：这里我们绕过了 apply_knockback 的免疫检查，因为这是主动位移
				knockback_velocity = v0 * dir
				knockback_friction = v0 / dur
			
			perform_hit_check(node)

func process_active(delta):
	var node = current_action_node
	
	# 特殊处理 Wait 节点：持续观望模式
	if node is WaitActionNode:
		_process_wait_node(node, delta)
		return

	# 非 Wait 节点的通用逻辑
	# if node.get_backdash() > 0:
	# 	var back_speed = node.get_backdash() / node.active
	# 	move_away_from_enemy(back_speed * delta)

	if state_timer >= node.active:
		# 处理分支逻辑
		var next_id = node.next_node_name
		
		var can_cancel_recovery = false
		
		if next_id != "":
			var next_node = nodes.get(next_id)
			if next_node:
				# 只有当当前动作和下一个动作都是 ATTACK 类型时，才允许取消后摇
				if node.get_action_type() == ActionNode.Type.ATTACK and \
				   next_node.get_action_type() == ActionNode.Type.ATTACK:
					can_cancel_recovery = true
		
		if can_cancel_recovery:
			debug_log("[%s] 动作完成 -> 连招取消后摇!" % fighter_name)
				
			current_state = State.IDLE
			state_timer = 0
			current_node_name = next_id
			poise_damage_accumulator = 0.0
			poise_changed.emit(0.0, 0.0)
			# 高亮下一个节点
			if ui_action_queue:
				ui_action_queue.highlight_node(current_node_name)
		else:
			# 无法取消后摇，正常进入 Recovery
			# 即使有 next_id，也得先跑完 Recovery 再由 process_recovery 切换
			# 但这里逻辑有点问题：如果进入 Recovery，process_recovery 结束后会自动切换到 next_node_name
			# 所以如果 next_id 存在但不满足取消条件，我们什么都不做，自然流转到 Recovery
			# 等 Recovery 结束，process_recovery 会处理切换
			
			current_state = State.RECOVERY
			state_timer = 0

func _process_wait_node(node: WaitActionNode, delta):
	# 只有当达到判定间隔时才进行检查
	if state_timer >= node.active:
		state_timer = 0 # 重置计时，准备下一个判定周期
		
		var condition_met = _evaluate_condition(node)
		var next_id = ""
		
		if condition_met:
			if node.next_node_name != "" and node.next_node_name != node.id:
				var next_node = nodes.get(node.next_node_name)
				
				# 可行性预判
				if next_node and _check_feasibility(next_node):
					# 只有真正可行时才跳转
					if node.next_node_name != last_wait_branch_target:
						debug_log("[%s] 条件判定通过! -> 切入【%s】" % [fighter_name, next_node.node_name])
						last_wait_branch_target = node.next_node_name
					next_id = node.next_node_name
				else:
					# 不可行，继续观望（保持在当前状态）
					if next_node and node.next_node_name != last_wait_branch_target:
						debug_log("[%s] 判定通过但条件不足，放弃【%s】，继续观望..." % [fighter_name, next_node.node_name])
						last_wait_branch_target = node.next_node_name
					# next_id 保持空，意味着不跳转，继续留在 ACTIVE
		else:
			if node.next_node_fail != "":
				var fail_node = nodes.get(node.next_node_fail)
				if fail_node and node.next_node_fail != node.id:
					# 可行性预判
					if _check_feasibility(fail_node):
						if node.next_node_fail != last_wait_branch_target:
							if not (fail_node is WaitActionNode): 
								debug_log("[%s] 条件判定失败 -> 走分支: 【%s】" % [fighter_name, fail_node.node_name])
							last_wait_branch_target = node.next_node_fail
						next_id = node.next_node_fail
		
		# 如果确定了要跳转的目标（且不是自己），则执行跳转
		if next_id != "" and next_id != node.id:					
			current_state = State.IDLE
			state_timer = 0
			current_node_name = next_id
			poise_damage_accumulator = 0.0
			poise_changed.emit(0.0, 0.0)
			# 高亮下一个节点
			if ui_action_queue:
				ui_action_queue.highlight_node(current_node_name)

func _check_feasibility(node: ActionNode) -> bool:
	if stamina < node.cost:
		return false
	return true

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
		WaitActionNode.Condition.ENEMY_STATE_WINDUP:
			if enemy and enemy.current_state == State.WINDUP:
				if enemy.current_action_node and enemy.current_action_node.get_action_type() == ActionNode.Type.ATTACK:
					return true
			return false
	return true


func perform_hit_check(node: ActionNode):
	# Wait节点不显示“出招”日志，避免刷屏
	if node is WaitActionNode:
		return

	debug_log("[%s] 【%s】 出招!" % [fighter_name, node.node_name])
	if node.get_action_type() == ActionNode.Type.ATTACK:
		var hit = true
		var is_int = false
		
		if enemy.current_state == State.ACTIVE and enemy.current_action_node and enemy.current_action_node.get_action_type() == ActionNode.Type.DODGE:
			# 闪避不再提供伤害免疫 (hit = true)，但因为在Active/Dodge状态，具有霸体保护 (is_int = false)
			# 除非我们显式地让 is_int 为 false?
			# 根据规则：闪避期间免疫削韧和打断。
			# 这里的 perform_hit_check 主要是计算伤害。
			# 只要不打断，就视为"闪避成功"（或者叫"抗住"了）
			# 但用户说：仍会受到攻击伤害（只要没挥空）。
			# 所以 hit 应该为 true。
			hit = true
			debug_log(">> 命中闪避中的敌人!")
			# 2. 对方在格挡?
		elif enemy.current_state == State.ACTIVE and enemy.current_action_node and enemy.current_action_node.get_action_type() == ActionNode.Type.DEFEND:
			var dmg = int(node.get_power() * 0.2)
			enemy.take_damage(dmg, false)
			debug_log(">> 攻击被格挡，造成 %d 点伤害" % dmg)
			hit = false
			var block_kb = node.get_knockback() * 0.5
			var dist = get_distance_to_enemy()
			if dist < block_kb:
				# 使用平滑击退
				enemy.apply_knockback(block_kb - dist, 0.1) # 格挡击退较快
		
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
					# 使用平滑击退
					enemy.apply_knockback(node.get_knockback() - dist, 0.25)

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
		poise_changed.emit(0.0, 0.0)
		current_action_node = null
		
		# 高亮下一个节点
		if ui_action_queue:
			ui_action_queue.highlight_node(current_node_name)

func update_visuals():
	# 更新眩晕指示器
	if stun_indicator:
		stun_indicator.visible = (current_state == State.STUNNED)

	var state_str = State.keys()[current_state]
	if ui_hud and ui_hud.has_method("update_state_text"):
		var txt = "状态: %s" % state_str
		
		# 在出招相关的状态下显示招式名
		if current_action_node and current_state in [State.WINDUP, State.ACTIVE, State.RECOVERY]:
			txt += " | 招式: %s" % current_action_node.node_name
			
		ui_hud.update_state_text(txt)
