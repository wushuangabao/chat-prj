class_name TimelineComponent
extends Node

enum State {
	IDLE,     # 待机
	MOVE,     # 移动
	WINDUP,   # 前摇
	ACTIVE,   # 判定
	RECOVERY, # 后摇
	STUNNED   # 僵直
}

signal state_changed(new_state: int, action_node: ActionNode)
signal log_event(msg: String)

# 依赖项
var fighter: Node2D # 所属角色
var stamina_comp: StaminaComponent
var poise_comp: PoiseComponent
var enemy: Node2D # 敌对角色

# 逻辑
# var nodes: Dictionary = {} # 不再需要 Dictionary 查找
var root_node: ActionNode
var current_node: ActionNode
var current_action_node: ActionNode = null

var current_state: int = State.IDLE
var state_timer: float = 0.0
var stun_duration: float = 0.0

# 历史记录/去重
var last_action_type: int = -1
var last_executed_node_id: String = ""
var last_wait_branch_target_id: String = "" # Keep storing ID for dedup if possible, or use instance id
var last_failed_node_id: String = ""

# 移动
var knockback_velocity: float = 0.0
var knockback_friction: float = 0.0

func setup(p_fighter: Node2D, p_stamina: StaminaComponent, p_poise: PoiseComponent):
	fighter = p_fighter
	stamina_comp = p_stamina
	poise_comp = p_poise
	
	poise_comp.stunned.connect(_on_stunned)

func init_flow(p_root: ActionNode):
	root_node = p_root
	current_node = root_node
	
	last_executed_node_id = ""
	last_wait_branch_target_id = ""
	last_failed_node_id = ""

func set_enemy(p_enemy: Node2D):
	enemy = p_enemy

func _process(delta):
	if not fighter or fighter.hp <= 0: return
	if enemy and enemy.hp <= 0:
		current_state = State.IDLE
		return
		
	state_timer += delta
	
	_process_knockback(delta)
	
	# 耐力回复逻辑
	var is_waiting = (current_state == State.ACTIVE and current_action_node is WaitActionNode)
	if current_state in [State.IDLE, State.RECOVERY, State.MOVE] or is_waiting:
		stamina_comp.process_regen(delta)

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
			
	# 更新视觉/UI逻辑应由信号处理或由 Fighter 主动获取数据

func _process_knockback(delta):
	if not is_zero_approx(knockback_velocity):
		fighter.global_position.x += knockback_velocity * delta * fighter.PIXELS_PER_METER
		
		var sign_before = sign(knockback_velocity)
		knockback_velocity -= sign_before * knockback_friction * delta
		
		if sign(knockback_velocity) != sign_before:
			knockback_velocity = 0.0

func _on_stunned(duration: float):
	enter_stunned(duration)
	log_event.emit("[%s] 被破防! 僵直: %.2f" % [fighter.fighter_name, duration])

func enter_stunned(duration: float):
	current_state = State.STUNNED
	state_timer = 0.0
	stun_duration = duration
	current_action_node = null
	current_node = root_node
	state_changed.emit(current_state, null)

func process_stunned(delta):
	if state_timer >= stun_duration:
		current_state = State.IDLE
		state_timer = 0
		log_event.emit("[%s] 从僵直中恢复，流程重置" % fighter.fighter_name)
		current_node = root_node
		state_changed.emit(current_state, null)

func get_next_action_node():
	if current_node == null:
		current_node = root_node
	return current_node

func process_idle(delta):
	var next_action = get_next_action_node()
	if next_action:
		var dist = fighter.get_distance_to_enemy()
		var effective_range = next_action.get_atk_range() + next_action.get_dash()
		
		if next_action.get_atk_range() > 0 and dist > effective_range:
			if stamina_comp.has_enough(next_action.cost):
				current_action_node = next_action
				current_state = State.MOVE
				state_timer = 0
				poise_comp.reset_accumulator()
				log_event.emit("[%s] 距离过远 (%.1fm > %.1fm)，开始接近..." % [fighter.fighter_name, dist, effective_range])
				state_changed.emit(current_state, current_action_node)
				return
		
		if stamina_comp.has_enough(next_action.cost):
			stamina_comp.consume(next_action.cost)
			current_action_node = next_action
			current_state = State.WINDUP
			state_timer = 0
			
			var is_repeated_wait = (next_action.id == last_executed_node_id) and (next_action is WaitActionNode)
			last_executed_node_id = next_action.id
			
			poise_comp.reset_accumulator()
			poise_comp.set_toughness(next_action.get_toughness())
			
			if not (next_action is WaitActionNode):
				last_failed_node_id = ""
				last_wait_branch_target_id = ""
			
			last_action_type = next_action.get_action_type()
			
			if not is_repeated_wait:
				_log_action_start(next_action)
				
			state_changed.emit(current_state, current_action_node)
		else:
			_handle_stamina_fail(next_action)

func _log_action_start(node: ActionNode):
	if node.get_action_type() == ActionNode.Type.DODGE:
		log_event.emit("[%s] 起手: 【%s】 (前摇 %.1fs, 后撤 %.1fm)" % [fighter.fighter_name, node.node_name, node.windup, node.get_backdash()])
	elif node.get_action_type() == ActionNode.Type.ATTACK:
		log_event.emit("[%s] 起手: 【%s】 (前摇 %.1fs, 突进 %.1fm)" % [fighter.fighter_name, node.node_name, node.windup, node.get_dash()])
	else:
		log_event.emit("[%s] 起手: 【%s】" % [fighter.fighter_name, node.node_name])

func _handle_stamina_fail(node: ActionNode):
	var force_log = not (node is WaitActionNode)
	var is_same_failure = (node.id == last_failed_node_id)
	
	if (last_action_type != -2 or force_log) and not is_same_failure:
		log_event.emit("[%s] 耐力不足 (%.0f < %.0f)，无法执行【%s】，重置流程!" % [fighter.fighter_name, stamina_comp.get_current(), node.cost, node.node_name])
		last_action_type = -2
		last_failed_node_id = node.id
		
	current_node = root_node
	current_action_node = null
	# 触发更新?

func process_move(delta):
	var move_speed = 3.0
	fighter.move_towards_enemy(move_speed * delta)
	
	var node = current_action_node
	var effective_range = node.get_atk_range() + node.get_dash()
	var dist = fighter.get_distance_to_enemy()
	
	if dist <= effective_range:
		if stamina_comp.has_enough(node.cost):
			stamina_comp.consume(node.cost)
			current_state = State.WINDUP
			state_timer = 0
			poise_comp.reset_accumulator()
			poise_comp.set_toughness(node.get_toughness())
			log_event.emit("[%s] 进入射程 (%.1fm)! 起手: 【%s】" % [fighter.fighter_name, dist, node.node_name])
			state_changed.emit(current_state, current_action_node)
		else:
			log_event.emit("[%s] 接近后耐力不足 (%.0f < %.0f)，放弃【%s】，重置流程!" % [fighter.fighter_name, stamina_comp.get_current(), node.cost, node.node_name])
			current_state = State.IDLE
			current_node = root_node
			current_action_node = null
			state_changed.emit(current_state, null)
	
	if dist < 0.5:
		fighter.move_away_from_enemy(0.5 - dist)

func process_windup(delta):
	var node = current_action_node
	
	if node.get_dash() > 0:
		var dash_speed = node.get_dash() / node.windup
		fighter.move_towards_enemy(dash_speed * delta)
		
	if state_timer >= node.windup:
		var dist = fighter.get_distance_to_enemy()
		if node.get_atk_range() > 0 and dist > (node.get_atk_range() + 0.05):
			log_event.emit("[%s] 挥空!" % fighter.fighter_name)
			current_state = State.IDLE
			state_timer = 0
			current_action_node = null
			poise_comp.reset_accumulator()
			poise_comp.set_toughness(0.0)
			state_changed.emit(current_state, null)
		else:
			current_state = State.ACTIVE
			state_timer = 0
			
			if node.get_backdash() > 0:
				var dash_dist = node.get_backdash()
				var dur = node.active
				var v0 = (dash_dist * 2.0) / dur
				var dir = -1 if enemy.global_position.x > fighter.global_position.x else 1
				knockback_velocity = v0 * dir
				knockback_friction = v0 / dur
			
			perform_hit_check(node)
			state_changed.emit(current_state, current_action_node)

func process_active(delta):
	var node = current_action_node
	
	if node is WaitActionNode:
		_process_wait_node(node, delta)
		return

	if state_timer >= node.active:
		var next_node_ref = node.next_node
		var can_cancel_recovery = false
		
		if next_node_ref:
			if node.get_action_type() == ActionNode.Type.ATTACK and \
			   next_node_ref.get_action_type() == ActionNode.Type.ATTACK:
				can_cancel_recovery = true
		
		if can_cancel_recovery:
			log_event.emit("[%s] 动作完成 -> 连招取消后摇!" % fighter.fighter_name)
			current_state = State.IDLE
			state_timer = 0
			current_node = next_node_ref
			poise_comp.reset_accumulator()
			poise_comp.set_toughness(0.0)
			state_changed.emit(current_state, null)
		else:
			current_state = State.RECOVERY
			state_timer = 0
			state_changed.emit(current_state, current_action_node)

func _process_wait_node(node: WaitActionNode, delta):
	if state_timer >= node.active:
		state_timer = 0
		
		var condition_met = _evaluate_condition(node)
		var next_target: ActionNode = null
		
		if condition_met:
			if node.next_node and node.next_node != node:
				if stamina_comp.has_enough(node.next_node.cost):
					if node.next_node.id != last_wait_branch_target_id:
						log_event.emit("[%s] 条件判定通过! -> 切入【%s】" % [fighter.fighter_name, node.next_node.node_name])
						last_wait_branch_target_id = node.next_node.id
					next_target = node.next_node
				else:
					if node.next_node.id != last_wait_branch_target_id:
						log_event.emit("[%s] 判定通过但条件不足，放弃【%s】，继续观望..." % [fighter.fighter_name, node.next_node.node_name])
						last_wait_branch_target_id = node.next_node.id
		else:
			if node.next_node_fail:
				if node.next_node_fail != node:
					if stamina_comp.has_enough(node.next_node_fail.cost):
						if node.next_node_fail.id != last_wait_branch_target_id:
							if not (node.next_node_fail is WaitActionNode): 
								log_event.emit("[%s] 条件判定失败 -> 走分支: 【%s】" % [fighter.fighter_name, node.next_node_fail.node_name])
							last_wait_branch_target_id = node.next_node_fail.id
						next_target = node.next_node_fail
		
		if next_target and next_target != node:
			current_state = State.IDLE
			state_timer = 0
			current_node = next_target
			poise_comp.reset_accumulator()
			poise_comp.set_toughness(0.0)
			state_changed.emit(current_state, null)

func process_recovery(delta):
	var node = current_action_node
	if state_timer >= node.recovery:
		current_state = State.IDLE
		state_timer = 0
		
		if node.next_node:
			current_node = node.next_node
		else:
			log_event.emit("[%s] 流程结束，循环回起点" % fighter.fighter_name)
			current_node = root_node
			
		poise_comp.reset_accumulator()
		poise_comp.set_toughness(0.0)
		current_action_node = null
		state_changed.emit(current_state, null)

func apply_knockback(dist_m: float, duration: float = 0.2):
	if current_action_node and current_action_node.get_action_type() == ActionNode.Type.DODGE:
		return
	if dist_m <= 0: return
	
	var dir = -1 if enemy.global_position.x > fighter.global_position.x else 1
	var v0 = (dist_m * 2.0) / duration
	knockback_velocity = v0 * dir
	knockback_friction = v0 / duration

func _evaluate_condition(node: WaitActionNode) -> bool:
	match node.condition:
		WaitActionNode.Condition.ALWAYS_TRUE:
			return true
		WaitActionNode.Condition.DISTANCE_GT:
			return fighter.get_distance_to_enemy() > node.param
		WaitActionNode.Condition.DISTANCE_LT:
			return fighter.get_distance_to_enemy() < node.param
		WaitActionNode.Condition.MY_HP_LT:
			return fighter.hp < node.param
		WaitActionNode.Condition.MY_STAMINA_LT:
			return stamina_comp.get_current() < node.param
		WaitActionNode.Condition.ENEMY_HP_LT:
			if enemy: return enemy.hp < node.param
			return false
		WaitActionNode.Condition.ENEMY_STAMINA_LT:
			if enemy and enemy.has_method("get_stamina"):
				return enemy.get_stamina() < node.param
			return false
		WaitActionNode.Condition.ENEMY_STATE_WINDUP:
			if enemy and enemy.has_method("get_state"):
				if enemy.get_state() == State.WINDUP:
					if enemy.has_method("get_current_action_type"):
						return enemy.get_current_action_type() == ActionNode.Type.ATTACK
			return false
	return true

func perform_hit_check(node: ActionNode):
	if node is WaitActionNode: return
	
	log_event.emit("[%s] 【%s】 出招!" % [fighter.fighter_name, node.node_name])
	
	if node.get_action_type() == ActionNode.Type.ATTACK:
		var hit = true
		var is_int = false
		
		var enemy_state = enemy.get_state() if enemy.has_method("get_state") else State.IDLE
		var enemy_action_type = enemy.get_current_action_type() if enemy.has_method("get_current_action_type") else -1
		
		if enemy_state == State.ACTIVE and enemy_action_type == ActionNode.Type.DODGE:
			hit = true
			log_event.emit(">> 命中闪避中的敌人!")
		elif enemy_state == State.ACTIVE and enemy_action_type == ActionNode.Type.DEFEND:
			var dmg = int(node.get_power() * 0.2)
			enemy.take_damage(dmg, false)
			
			# 反震逻辑：伤害越高，反震距离越远
			var recoil_dist = node.get_power() * 0.01
			apply_knockback(recoil_dist, 0.15)
			
			log_event.emit(">> 攻击被格挡! 造成 %d 伤害，受到反震 %.1fm" % [dmg, recoil_dist])
			hit = false
			var block_kb = node.get_knockback() * 0.5
			var dist = fighter.get_distance_to_enemy()
			if dist < block_kb:
				enemy.apply_knockback(block_kb - dist, 0.2)
		
		if hit:
			if enemy_state in [State.WINDUP, State.RECOVERY]:
				is_int = true
			
			var actually_interrupted = enemy.take_damage(node.get_power(), is_int)
			if actually_interrupted:
				log_event.emit(">> 打断成功!")
			
			if node.get_knockback() > 0:
				var dist = fighter.get_distance_to_enemy()
				if dist < node.get_knockback():
					enemy.apply_knockback(node.get_knockback() - dist, 0.25)
