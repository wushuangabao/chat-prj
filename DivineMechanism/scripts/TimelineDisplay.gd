class_name TimelineDisplay
extends Control

var fighter: Fighter
var bar_height: float = 20.0
var pixels_per_second: float = 150.0 # 1秒 = 150像素
var total_width: float = 0.0

func setup(p_fighter: Fighter):
	fighter = p_fighter

func _process(delta):
	queue_redraw()

func _draw():
	if not fighter: return
	
	# 绘制背景条 (代表总长度或容器)
	# 假设我们只绘制当前动作的长度
	var node = fighter.timeline_comp.current_action_node
	var current_timer = fighter.timeline_comp.state_timer
	
	var start_x = 0.0
	var y = 0.0
	
	# 绘制状态指示文字
	# var state_name = Fighter.State.keys()[fighter.current_state]
	# var font = get_theme_default_font()
	# draw_string(font, Vector2(0, -5), "%s: %s" % [fighter.fighter_name, state_name], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	
	if node:
		# 计算各阶段宽度
		var w_windup = node.windup * pixels_per_second
		var w_active = node.active * pixels_per_second
		var w_recovery = node.recovery * pixels_per_second
		
		# 绘制色块
		# Windup: 蓝色
		draw_rect(Rect2(start_x, y, w_windup, bar_height), Color(0.2, 0.4, 0.8))
		
		# Active: 红色 (Wait节点用紫色)
		var active_color = Color(0.8, 0.2, 0.2)
		if node is WaitActionNode:
			active_color = Color(0.6, 0.2, 0.8)
		draw_rect(Rect2(start_x + w_windup, y, w_active, bar_height), active_color)
		
		# Recovery: 灰色
		draw_rect(Rect2(start_x + w_windup + w_active, y, w_recovery, bar_height), Color(0.5, 0.5, 0.5))
		
		# 绘制光标
		var cursor_x = 0.0
		var current_state = fighter.timeline_comp.current_state
		
		match current_state:
			TimelineComponent.State.WINDUP:
				cursor_x = current_timer * pixels_per_second
			TimelineComponent.State.ACTIVE:
				cursor_x = (node.windup + current_timer) * pixels_per_second
			TimelineComponent.State.RECOVERY:
				cursor_x = (node.windup + node.active + current_timer) * pixels_per_second
			_:
				cursor_x = 0.0 # 其他状态不显示光标或在起点
				
		# 只有在相关状态下才绘制光标
		if current_state in [TimelineComponent.State.WINDUP, TimelineComponent.State.ACTIVE, TimelineComponent.State.RECOVERY]:
			draw_line(Vector2(cursor_x, y - 5), Vector2(cursor_x, y + bar_height + 5), Color.WHITE, 2.0)
			
	else:
		# IDLE 或其他状态，绘制一个空的灰色条或者什么都不画
		draw_rect(Rect2(0, y, 50, bar_height), Color(0.2, 0.2, 0.2))
		if fighter.timeline_comp.current_state == TimelineComponent.State.STUNNED:
			var font = get_theme_default_font()
			draw_string(font, Vector2(60, y + 15), "STUNNED (%.1fs)" % (fighter.timeline_comp.stun_duration - fighter.timeline_comp.state_timer), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.YELLOW)
