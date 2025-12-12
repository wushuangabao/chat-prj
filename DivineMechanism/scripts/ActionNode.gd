class_name ActionNode
extends Resource

enum Type {
	ATTACK, # 攻击
	DEFEND, # 防御
	DODGE,  # 闪避
	WAIT    # 等待
}

@export var id: String = ""
@export var node_name: String
@export var action_type: Type
@export var windup: float     # 前摇：受击易被打断
@export var active: float     # 判定：伤害/效果生效窗口
@export var recovery: float   # 后摇：动作结束后的硬直
@export var power: float      # 威力/伤害
@export var toughness: float  # 韧性/霸体值
@export var cost: float       # 耐力消耗
@export var atk_range: float  # 攻击距离
@export var dash: float       # 突进距离 (在前摇期间)
@export var knockback: float  # 击退距离
@export var backdash: float   # 后撤距离 (闪避用)

@export var next_node_name: String = ""

func _init(p_name: String = "", p_type: Type = Type.ATTACK, p_windup:=0.3, p_active:=0.1, p_recovery:=0.5, \
		   p_power:=10.0, p_toughness:=0.0, p_cost:=10.0, p_atk_range:=1.0, \
		   p_dash:=0.0, p_knockback:=0.5, p_backdash:=0.0):
	node_name = p_name
	action_type = p_type
	windup = p_windup
	active = p_active
	recovery = p_recovery
	power = p_power
	toughness = p_toughness
	cost = p_cost
	atk_range = p_atk_range
	dash = p_dash
	knockback = p_knockback
	backdash = p_backdash

func set_next(p_next: String) -> ActionNode:
	next_node_name = p_next
	return self
