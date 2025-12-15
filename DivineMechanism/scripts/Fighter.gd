class_name Fighter
extends Node2D

const PIXELS_PER_METER = 100.0
const RECT_WIDTH = 50.0 # 角色矩形宽度
const RECT_HEIGHT = 100.0

# Stats
var fighter_name: String
var max_hp: float
var hp: float

# Components
var stamina_comp: StaminaComponent
var poise_comp: PoiseComponent
var timeline_comp: TimelineComponent

# References
var enemy: Fighter

# Visuals
var color_rect: ColorRect
var stun_indicator: Node2D

# UI
var ui_hud: Control
var ui_action_queue: ActionQueueDisplay

# Signals
signal log_event(msg: String)
signal hp_changed(val: float, max_val: float)
signal stamina_changed(val: float, max_val: float)
signal poise_changed(accumulator: float, max_toughness: float)
signal damage_taken(amount: float, pos: Vector2, is_crit: bool)

func _ready():
	# Visuals
	color_rect = ColorRect.new()
	color_rect.size = Vector2(RECT_WIDTH, RECT_HEIGHT)
	color_rect.position = Vector2(-RECT_WIDTH/2, -RECT_HEIGHT/2)
	add_child(color_rect)
	
	var stun_script = load("res://scripts/StunIndicator.gd")
	if stun_script:
		stun_indicator = stun_script.new()
		stun_indicator.position = Vector2(0, -75)
		add_child(stun_indicator)
	
	# Components
	stamina_comp = StaminaComponent.new()
	stamina_comp.name = "StaminaComponent"
	add_child(stamina_comp)
	
	poise_comp = PoiseComponent.new()
	poise_comp.name = "PoiseComponent"
	add_child(poise_comp)
	
	timeline_comp = TimelineComponent.new()
	timeline_comp.name = "TimelineComponent"
	add_child(timeline_comp)
	
	# Setup Components
	timeline_comp.setup(self, stamina_comp, poise_comp)
	
	# Connect Signals
	stamina_comp.stamina_changed.connect(func(v, m): stamina_changed.emit(v, m))
	poise_comp.poise_changed.connect(func(a, m): poise_changed.emit(a, m))
	poise_comp.stunned.connect(func(_d): update_visuals()) # Update visuals on stun
	timeline_comp.log_event.connect(func(msg): log_event.emit(msg))
	timeline_comp.state_changed.connect(_on_state_changed)

func init(p_name: String, p_hp: float, p_root: ActionNode):
	fighter_name = p_name
	max_hp = p_hp
	hp = p_hp
	
	hp_changed.emit(hp, max_hp)
	
	# Init Components
	stamina_comp.init(200.0) # Default max stamina
	poise_comp.reset_accumulator()
	timeline_comp.init_flow(p_root)
	
	if "赵" in p_name: color_rect.color = Color(0.8, 0.2, 0.2)
	else: color_rect.color = Color(0.2, 0.2, 0.8)
	
	if ui_action_queue:
		ui_action_queue.setup(p_root)
		ui_action_queue.highlight_node(timeline_comp.current_node)

func set_enemy(p_enemy: Fighter):
	enemy = p_enemy
	timeline_comp.set_enemy(p_enemy)

func assign_ui(hud: Control, action_queue: ActionQueueDisplay):
	ui_hud = hud
	ui_action_queue = action_queue

func _process(delta):
	# TimelineComponent handles its own process via _process because it's in the tree
	update_visuals()

func take_damage(damage: float, is_interrupt: bool) -> bool:
	hp -= damage
	hp_changed.emit(hp, max_hp)
	damage_taken.emit(damage, global_position, is_interrupt)
	
	var tw = create_tween()
	tw.tween_property(color_rect, "modulate", Color.RED, 0.1)
	tw.tween_property(color_rect, "modulate", Color.WHITE, 0.1)
	
	var interrupted = false
	
	if is_interrupt:
		# Check dodge immunity
		if timeline_comp.current_action_node and timeline_comp.current_action_node.get_action_type() == ActionNode.Type.DODGE:
			log_event.emit("[%s] 闪避中，免疫打断! (受到伤害: %d)" % [fighter_name, damage])
			return false
			
		interrupted = poise_comp.take_poise_damage(damage)
		if not interrupted:
			log_event.emit("[%s] 霸体抗住! 累积削韧: %.1f" % [fighter_name, poise_comp.get_accumulator()])
	else:
		var state_str = TimelineComponent.State.keys()[timeline_comp.current_state]
		log_event.emit("[%s] 受到伤害 %d (状态: %s)" % [fighter_name, damage, state_str])
		
	return interrupted

func get_distance_to_enemy() -> float:
	if not enemy: return 999.0
	var center_dist = abs(global_position.x - enemy.global_position.x)
	var gap = center_dist - RECT_WIDTH
	return max(0.0, gap) / PIXELS_PER_METER

func move_towards_enemy(dist_px_or_m: float):
	# Note: timeline passes pixels? No, timeline calculates speed * delta
	# But move_towards_enemy in original Fighter took meters?
	# Original: move_towards_enemy(dist_m)
	# Inside: var move_dist_px = dist_m * PIXELS_PER_METER
	# Timeline process_move: move_towards_enemy(move_speed * delta) -> passed meters
	
	var dist_m = dist_px_or_m # Just to be clear
	var dir = 1 if enemy.global_position.x > global_position.x else -1
	var move_dist_px = dist_m * PIXELS_PER_METER
	var center_dist = abs(global_position.x - enemy.global_position.x)
	var min_center_dist = RECT_WIDTH
	var max_move_px = max(0.0, center_dist - min_center_dist)
	var actual_move = min(move_dist_px, max_move_px)
	global_position.x += dir * actual_move

func move_away_from_enemy(dist_m: float):
	var dir = -1 if enemy.global_position.x > global_position.x else 1
	global_position.x += dir * dist_m * PIXELS_PER_METER

func apply_knockback(dist_m: float, duration: float = 0.2):
	timeline_comp.apply_knockback(dist_m, duration)

# Helpers for TimelineComponent
func get_stamina() -> float:
	return stamina_comp.get_current()

func get_state() -> int:
	return timeline_comp.current_state

func get_current_action_type() -> int:
	if timeline_comp.current_action_node:
		return timeline_comp.current_action_node.get_action_type()
	return -1

func _on_state_changed(new_state: int, action_node: ActionNode):
	if ui_action_queue:
		ui_action_queue.highlight_node(timeline_comp.current_node)
	update_visuals()

func update_visuals():
	if stun_indicator:
		stun_indicator.visible = (timeline_comp.current_state == TimelineComponent.State.STUNNED)
	
	if ui_hud and ui_hud.has_method("update_state_text"):
		var state_str = TimelineComponent.State.keys()[timeline_comp.current_state]
		var txt = "状态: %s" % state_str
		if timeline_comp.current_action_node and timeline_comp.current_state in [TimelineComponent.State.WINDUP, TimelineComponent.State.ACTIVE, TimelineComponent.State.RECOVERY]:
			txt += " | 招式: %s" % timeline_comp.current_action_node.node_name
		ui_hud.update_state_text(txt)
