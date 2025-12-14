class_name StunIndicator
extends Node2D

func _ready():
	# 初始隐藏
	visible = false
	# 确保在最上层绘制
	z_index = 10

func _process(delta):
	if visible:
		queue_redraw()
		# 整体旋转
		rotation += 3.0 * delta 

func _draw():
	# 绘制光圈
	# 使用相对坐标 (0,0) 为中心
	
	var radius = 25.0
	var color = Color(1, 1, 0) # 黄色
	var width = 3.0
	
	# 画一个圆环
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, color, width)
	
	# 画几个动态的小星星/小球
	# 计算相对于圆心的位置
	var time = Time.get_ticks_msec() / 1000.0
	
	for i in range(3):
		var angle = (i * TAU / 3) # + time * 2.0 (不需要额外time，因为整个node在rotate)
		var offset = Vector2(cos(angle), sin(angle)) * radius
		draw_circle(offset, 5, color)
