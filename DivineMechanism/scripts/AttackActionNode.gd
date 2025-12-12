class_name AttackActionNode
extends ActionNode

@export var power: float = 10.0      # 威力/伤害
@export var toughness: float = 0.0   # 韧性/霸体值
@export var atk_range: float = 1.0   # 攻击距离
@export var dash: float = 0.0        # 突进距离
@export var knockback: float = 0.5   # 击退距离

func get_action_type() -> Type:
	return Type.ATTACK

func get_power() -> float: return power
func get_toughness() -> float: return toughness
func get_atk_range() -> float: return atk_range
func get_dash() -> float: return dash
func get_knockback() -> float: return knockback

func _init(p_name: String = "Attack", p_windup:=0.3, p_active:=0.1, p_recovery:=0.5, \
		   p_power:=10.0, p_toughness:=0.0, p_cost:=10.0, p_atk_range:=1.0, \
		   p_dash:=0.0, p_knockback:=0.5):
	node_name = p_name
	windup = p_windup
	active = p_active
	recovery = p_recovery
	cost = p_cost
	power = p_power
	toughness = p_toughness
	atk_range = p_atk_range
	dash = p_dash
	knockback = p_knockback
