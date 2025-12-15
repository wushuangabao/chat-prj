class_name PoiseComponent
extends Node

signal poise_changed(accumulator: float, max_toughness: float)
signal stunned(duration: float)

var poise_damage_accumulator: float = 0.0
var current_toughness: float = 0.0

func reset_accumulator():
	poise_damage_accumulator = 0.0
	poise_changed.emit(0.0, current_toughness)

func set_toughness(val: float):
	current_toughness = val
	poise_changed.emit(poise_damage_accumulator, current_toughness)

func get_accumulator() -> float:
	return poise_damage_accumulator

func take_poise_damage(damage: float) -> bool:
	poise_damage_accumulator += damage
	poise_changed.emit(poise_damage_accumulator, current_toughness)
	
	if poise_damage_accumulator > current_toughness:
		# 僵直计算优化：使用非线性曲线 (Ease-Out)
		# 公式：stun = min + (max - min) * (1 - (1 - t)^3)
		# 其中 t = clamp(damage / 100.0, 0, 1)
		var t = clamp(damage / 100.0, 0.0, 1.0)
		var curve_factor = 1.0 - pow(1.0 - t, 3.0) # Cubic Ease Out
		var actual_stun = 0.5 + (1.5 * curve_factor) # Range: 0.5s -> 2.0s
		
		stunned.emit(actual_stun)
		reset_accumulator()
		return true # 被打断
	
	return false
