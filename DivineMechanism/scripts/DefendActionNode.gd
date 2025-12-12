class_name DefendActionNode
extends ActionNode

@export var power: float = 10.0      # 防御强度/反击伤害基数
@export var toughness: float = 10.0  # 防御时的韧性

func get_action_type() -> Type:
	return Type.DEFEND

func get_power() -> float: return power
func get_toughness() -> float: return toughness

func _init(p_name: String = "Defend", p_windup:=0.1, p_active:=0.5, p_recovery:=0.2, \
		   p_power:=10.0, p_toughness:=10.0, p_cost:=5.0):
	node_name = p_name
	windup = p_windup
	active = p_active
	recovery = p_recovery
	cost = p_cost
	power = p_power
	toughness = p_toughness
