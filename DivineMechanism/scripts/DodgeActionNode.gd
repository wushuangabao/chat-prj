class_name DodgeActionNode
extends ActionNode

@export var backdash: float = 2.0     # 后撤距离

func get_action_type() -> Type:
	return Type.DODGE

func get_backdash() -> float: return backdash

func _init(p_name: String = "Dodge", p_windup:=0.1, p_active:=0.3, p_recovery:=0.2, \
		   p_cost:=10.0, p_backdash:=2.0):
	node_name = p_name
	windup = p_windup
	active = p_active
	recovery = p_recovery
	cost = p_cost
	backdash = p_backdash
