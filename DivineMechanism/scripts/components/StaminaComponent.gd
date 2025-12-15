class_name StaminaComponent
extends Node

signal stamina_changed(val: float, max_val: float)
signal stamina_exhausted()

@export var max_stamina: float = 200.0
@export var stamina_regen: float = 20.0

var current_stamina: float

func _ready():
	current_stamina = max_stamina

func init(max_val: float):
	max_stamina = max_val
	current_stamina = max_val
	stamina_changed.emit(current_stamina, max_stamina)

func process_regen(delta: float):
	if current_stamina < max_stamina:
		current_stamina = min(max_stamina, current_stamina + stamina_regen * delta)
		stamina_changed.emit(current_stamina, max_stamina)

func has_enough(cost: float) -> bool:
	return current_stamina >= cost

func consume(cost: float):
	current_stamina -= cost
	if current_stamina < 0:
		current_stamina = 0
		stamina_exhausted.emit()
	stamina_changed.emit(current_stamina, max_stamina)

func get_current() -> float:
	return current_stamina

func get_max() -> float:
	return max_stamina
