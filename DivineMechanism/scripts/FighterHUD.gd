extends Control

var hp_bar: ProgressBar
var stamina_bar: ProgressBar
var poise_bar: ProgressBar
var state_label: Label

var hp_label: Label
var stamina_label: Label

@export var is_left_aligned: bool = true

func _ready():
	_setup_ui()

func _setup_ui():
	if hp_bar: return # 防止重复初始化
	
	# Root Container
	var container = VBoxContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 移除内部的靠下对齐，让内容自然排列，避免与下方的Timeline挤在一起
	# container.alignment = BoxContainer.ALIGNMENT_END 
	add_child(container)
	
	# 设置自身的最小尺寸
	custom_minimum_size = Vector2(350, 120) # 加大宽度，确保能放下 Bar(200)+Label(110)+间距
	
	# Name Label (Removed as per request, duplicate with existing UI or handled elsewhere?)
	# The user said "删掉重复的名字", but we still need to know who is who.
	# Let's keep the Fighter Name at the top of the HUD block, but maybe smaller or styled?
	# The user said "新做的进度条与名字的位置和之前的文字重叠了", likely referring to the old `ui_stats_label` text.
	# We will replace the old text with this HUD.
	
	var name_lbl = Label.new()
	name_lbl.name = "NameLabel"
	# name_lbl.text = "Fighter" # Will be set in setup
	if is_left_aligned:
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	else:
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	container.add_child(name_lbl)
	
	# HP Row
	var hp_row = _create_stat_row(Color(0.8, 0.2, 0.2), "HP")
	hp_bar = hp_row[0]
	hp_label = hp_row[1]
	container.add_child(hp_row[2]) # The HBoxContainer
	
	# Stamina Row
	var stamina_row = _create_stat_row(Color(0.2, 0.8, 0.2), "Stamina")
	stamina_bar = stamina_row[0]
	stamina_label = stamina_row[1]
	container.add_child(stamina_row[2])
	
	# Poise Bar (No text needed usually, or simple)
	# Poise bar just below stamina
	poise_bar = _create_bar(Color(0.8, 0.8, 0.2), "Poise")
	poise_bar.custom_minimum_size.y = 8
	container.add_child(poise_bar)
	
	# State/Action Label (To replace the old text info)
	state_label = Label.new()
	if is_left_aligned:
		state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	else:
		state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	container.add_child(state_label)

func _create_stat_row(color: Color, label_text: String) -> Array:
	# 使用 MarginContainer 来实现文字覆盖在进度条上的效果
	# 这样可以节省空间，避免水平排列导致的挤压和重叠问题
	var container = MarginContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var bar = _create_bar(color, label_text)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_FILL
	container.add_child(bar)
	
	var lbl = Label.new()
	lbl.text = "100 / 100"
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 文字加阴影，防止在亮色背景上看不清
	lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	
	# 根据玩家位置设置文字对齐
	if is_left_aligned:
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		# 增加一点左边距
		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 5)
		margin.add_theme_constant_override("margin_right", 5)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE # 透传
		container.add_child(margin)
		margin.add_child(lbl)
	else:
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		# 增加一点右边距
		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 5)
		margin.add_theme_constant_override("margin_right", 5)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(margin)
		margin.add_child(lbl)
		
	return [bar, lbl, container]

func _create_bar(color: Color, tooltip: String) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(200, 20)
	bar.show_percentage = false
	bar.tooltip_text = tooltip
	
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = color
	bar.add_theme_stylebox_override("fill", style_box)
	
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	bar.add_theme_stylebox_override("background", bg_style)
	
	if not is_left_aligned:
		bar.fill_mode = ProgressBar.FILL_END_TO_BEGIN
		
	return bar

func setup(fighter: Fighter):
	# 确保 UI 已初始化 (防止 setup 在 _ready 之前被调用)
	if not hp_bar:
		_setup_ui()

	var name_node = find_child("NameLabel")
	if name_node: name_node.text = fighter.fighter_name
	
	# Initial Values
	update_hp(fighter.hp, fighter.max_hp)
	update_stamina(fighter.stamina, fighter.max_stamina)
	
	poise_bar.max_value = 1.0 
	poise_bar.value = 0.0
	# 初始化时不显示韧性条，因为它通常在出招时才有效
	poise_bar.visible = false 
	
	# Connect Signals
	fighter.hp_changed.connect(update_hp)
	fighter.stamina_changed.connect(update_stamina)
	fighter.poise_changed.connect(_on_poise_changed)
	
	# Connect update loop for state text (or use signal if available)
	# For simplicity, we can let Fighter push text to us or we pull it.
	# The old system pushed text to a label.
	# We will expose a method to update state text.

func update_hp(val, max_val):
	hp_bar.max_value = max_val
	hp_bar.value = val
	hp_label.text = "%.0f / %.0f" % [val, max_val]

func update_stamina(val, max_val):
	stamina_bar.max_value = max_val
	stamina_bar.value = val
	stamina_label.text = "%.0f / %.0f" % [val, max_val]

func _on_poise_changed(accumulator: float, max_toughness: float):
	if max_toughness <= 0.001:
		# 没有霸体（或处于Idle/Recovery），隐藏进度条或显示为空
		poise_bar.visible = false
		poise_bar.value = 0.0
	else:
		poise_bar.visible = true
		poise_bar.max_value = max_toughness
		# 显示剩余韧性
		var remaining = max(0.0, max_toughness - accumulator)
		poise_bar.value = remaining

func update_state_text(text: String):
	state_label.text = text
