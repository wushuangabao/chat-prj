extends Camera2D

# 目标跟踪
var targets: Array[Node2D] = []

# 摄像机参数
var min_zoom: float = 0.5 # 最小缩放 (拉远)
var max_zoom: float = 1.2 # 最大缩放 (拉近)
var zoom_margin: float = 300.0 # 屏幕边缘留白 (像素)
var zoom_speed: float = 5.0 # 缩放平滑速度
var move_speed: float = 10.0 # 移动平滑速度

# 屏幕尺寸 (用于计算缩放)
@onready var screen_size = get_viewport_rect().size

func setup(p_targets: Array[Node2D]):
	targets = p_targets
	# 初始位置瞬移
	if targets.size() > 0:
		position = get_center_point()
		zoom = Vector2.ONE * calculate_zoom()

func _process(delta):
	if targets.is_empty():
		return
		
	# 1. 移动摄像机到中心点
	var target_pos = get_center_point()
	position = position.lerp(target_pos, move_speed * delta)
	
	# 2. 动态缩放
	var target_zoom = calculate_zoom()
	# 保持 X 和 Y 缩放一致
	var new_zoom = zoom.x
	new_zoom = lerp(new_zoom, target_zoom, zoom_speed * delta)
	zoom = Vector2.ONE * new_zoom

func get_center_point() -> Vector2:
	if targets.is_empty():
		return position
		
	var center = Vector2.ZERO
	for target in targets:
		center += target.position
	return center / targets.size()

func calculate_zoom() -> float:
	if targets.is_empty():
		return 1.0
		
	# 计算包围盒
	var r = Rect2(targets[0].position, Vector2.ZERO)
	for target in targets:
		r = r.expand(target.position)
	
	# 增加留白
	r = r.grow(zoom_margin)
	
	# 计算需要的缩放比例
	# 视口宽度 / 包围盒宽度 = 需要的缩放值
	# 我们取宽高中较小的一个比例，以确保全部在画面内
	var z_x = screen_size.x / r.size.x
	var z_y = screen_size.y / r.size.y
	var z = min(z_x, z_y)
	
	return clamp(z, min_zoom, max_zoom)
