class_name ShadowAgent
extends RefCounted

## Pure-data agent representation for MCTS shadow simulation.
## No Godot nodes, physics, or navigation - just integers and floats.

enum AgentType { TANK, HEALER, SNIPER }

var type: AgentType
var hp: int
var max_hp: int
var stamina: float
var max_stamina: int
var stamina_regen: float = 20.0  # Per tick (40/s at 2 ticks/s)

# Active buffs (ticks remaining)
var defensive_stance_ticks: int = 0  # Tank only: 70% damage reduction
var shield_ticks: int = 0            # 50% damage reduction

# Busy state (executing an action)
var is_busy: bool = false


static func create_tank() -> ShadowAgent:
	var agent = ShadowAgent.new()
	agent.type = AgentType.TANK
	agent.hp = 150
	agent.max_hp = 150
	agent.stamina = 80.0
	agent.max_stamina = 80
	return agent


static func create_healer() -> ShadowAgent:
	var agent = ShadowAgent.new()
	agent.type = AgentType.HEALER
	agent.hp = 100
	agent.max_hp = 100
	agent.stamina = 150.0
	agent.max_stamina = 150
	return agent


static func create_sniper() -> ShadowAgent:
	var agent = ShadowAgent.new()
	agent.type = AgentType.SNIPER
	agent.hp = 80
	agent.max_hp = 80
	agent.stamina = 120.0
	agent.max_stamina = 120
	return agent


func clone() -> ShadowAgent:
	var copy = ShadowAgent.new()
	copy.type = type
	copy.hp = hp
	copy.max_hp = max_hp
	copy.stamina = stamina
	copy.max_stamina = max_stamina
	copy.stamina_regen = stamina_regen
	copy.defensive_stance_ticks = defensive_stance_ticks
	copy.shield_ticks = shield_ticks
	copy.is_busy = is_busy
	return copy


func is_alive() -> bool:
	return hp > 0


func get_damage_multiplier() -> float:
	## Returns the multiplier applied to incoming damage.
	## Lower = better (more reduction).
	var multiplier: float = 1.0

	# Defensive stance: 70% reduction (0.3 multiplier)
	if defensive_stance_ticks > 0:
		multiplier *= 0.3

	# Shield: 50% reduction (0.5 multiplier)
	if shield_ticks > 0:
		multiplier *= 0.5

	return multiplier


func take_damage(amount: int) -> void:
	var final_damage = int(float(amount) * get_damage_multiplier())
	hp = maxi(0, hp - final_damage)


func heal(amount: int) -> void:
	hp = mini(hp + amount, max_hp)


func restore_stamina(amount: float) -> void:
	stamina = minf(stamina + amount, float(max_stamina))


func spend_stamina(amount: float) -> bool:
	if stamina >= amount:
		stamina -= amount
		return true
	return false


func tick_timers() -> void:
	## Called once per tick to update all timers and regeneration.
	if not is_alive():
		return

	# Stamina regeneration
	stamina = minf(stamina + stamina_regen, float(max_stamina))

	# Decrement buff timers
	if defensive_stance_ticks > 0:
		defensive_stance_ticks -= 1

	if shield_ticks > 0:
		shield_ticks -= 1

	# Clear busy state each tick (simplified model)
	is_busy = false


func get_type_name() -> String:
	match type:
		AgentType.TANK:
			return "tank"
		AgentType.HEALER:
			return "healer"
		AgentType.SNIPER:
			return "sniper"
	return "unknown"
