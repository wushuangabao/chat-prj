class_name FloatingText
extends Label

func _ready():
	# 初始设置：透明度1，居中
	modulate.a = 1.0
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	# 注意：之前的 _ready 动画逻辑已移动到 setup 中，以便支持动态方向

func setup(amount: int, start_pos: Vector2, color: Color = Color.RED, drift_dir: Vector2 = Vector2.UP):
	text = str(amount)
	position = start_pos
	modulate = color
	
	# 动画：向指定方向飘动并渐隐
	# 减小飘动高度：从 50 减到 30
	# 减慢速度：从 0.8s 增加到 1.2s
	var tw = create_tween()
	tw.set_parallel(true)
	
	# 根据 drift_dir 飘动
	var target_pos = position + drift_dir * 40.0 # 飘动距离
	
	tw.tween_property(self, "position", target_pos, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 0.0, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# 动画结束后销毁
	tw.chain().tween_callback(queue_free)
	
	# 加上黑色描边效果以增强可读性（通过 LabelSettings）
	var settings = LabelSettings.new()
	settings.font_size = 24
	settings.font_color = color
	settings.outline_size = 4
	settings.outline_color = Color.BLACK
	label_settings = settings
