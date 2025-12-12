class_name WaitActionNode
extends ActionNode

enum Condition {
	ALWAYS_TRUE,    # 总是通过 (Wait)
	DISTANCE_GT,    # 距离 > param
	DISTANCE_LT,    # 距离 < param
	MY_HP_LT,       # 自身生命 < param
	MY_STAMINA_LT,  # 自身耐力 < param
	ENEMY_HP_LT,    # 敌人生命 < param
	ENEMY_STAMINA_LT # 敌人耐力 < param
}

@export var condition: Condition = Condition.ALWAYS_TRUE
@export var param: float = 0.0
@export var next_node_fail: String = "" # 判定失败时的分支

func get_action_type() -> Type:
	return Type.WAIT

func _init(p_name: String = "Wait", p_duration: float = 0.5, \
		   p_condition: Condition = Condition.ALWAYS_TRUE, p_param: float = 0.0, p_fail: String = ""):
	node_name = p_name
	windup = 0.0
	active = p_duration
	recovery = 0.0
	cost = 0.0
	
	condition = p_condition
	param = p_param
	next_node_fail = p_fail
