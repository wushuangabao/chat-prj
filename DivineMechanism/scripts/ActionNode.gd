class_name ActionNode
extends Resource

enum Type {
	ATTACK, # 攻击
	DEFEND, # 格挡
	DODGE,  # 闪避
	WAIT    # 观望
}

@export var id: String = ""
@export var node_name: String = "Action"
@export var next_node_name: String = ""
@export var graph_position: Vector2 = Vector2.ZERO # 节点在编辑器中的位置

# Common Timing & Cost
@export var windup: float = 0.3    # 前摇
@export var active: float = 0.1    # 判定
@export var recovery: float = 0.5  # 后摇
@export var cost: float = 10.0     # 耐力消耗

# Virtual method to get type
func get_action_type() -> Type:
	return Type.WAIT

# Virtual getters for properties that might not exist on all nodes
func get_power() -> float: return 0.0
func get_toughness() -> float: return 0.0
func get_atk_range() -> float: return 0.0
func get_dash() -> float: return 0.0
func get_knockback() -> float: return 0.0
func get_backdash() -> float: return 0.0

func set_next(p_next: String) -> ActionNode:
	next_node_name = p_next
	return self
