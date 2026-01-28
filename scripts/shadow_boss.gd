class_name ShadowBoss
extends RefCounted

## Pure-data boss representation for MCTS shadow simulation.
## No Godot nodes, physics, or navigation - just integers and floats.

var hp: int = 650
var max_hp: int = 650
var stamina: float = 300.0
var max_stamina: int = 300
var stamina_regen: float = 7.5  # Per tick (15/s at 2 ticks/s)

# Attack cooldowns (in ticks)
var ranged_cooldown: int = 0  # 2 seconds = 4 ticks
var melee_cooldown: int = 0   # 1 second = 2 ticks

# Status effects (ticks remaining)
var is_slowed: bool = false
var slow_ticks: int = 0       # 8 seconds = 16 ticks

var is_taunted: bool = false
var taunt_ticks: int = 0      # 5 seconds = 10 ticks
var taunt_target: int = -1    # Agent index: 0=tank, 1=healer, 2=sniper

# Attack damage values
const RANGED_DAMAGE: int = 20
const MELEE_DAMAGE: int = 30
const RANGED_COOLDOWN_TICKS: int = 3
const MELEE_COOLDOWN_TICKS: int = 2

# Targeting weights
const HEALER_PRIORITY: float = 25.0
const SNIPER_PRIORITY: float = 15.0
const TANK_PRIORITY: float = 0.0


static func create() -> ShadowBoss:
	return ShadowBoss.new()


func clone() -> ShadowBoss:
	var copy = ShadowBoss.new()
	copy.hp = hp
	copy.max_hp = max_hp
	copy.stamina = stamina
	copy.max_stamina = max_stamina
	copy.stamina_regen = stamina_regen
	copy.ranged_cooldown = ranged_cooldown
	copy.melee_cooldown = melee_cooldown
	copy.is_slowed = is_slowed
	copy.slow_ticks = slow_ticks
	copy.is_taunted = is_taunted
	copy.taunt_ticks = taunt_ticks
	copy.taunt_target = taunt_target
	return copy


func is_alive() -> bool:
	return hp > 0


func take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)


func apply_slow(duration_ticks: int = 16) -> void:
	is_slowed = true
	slow_ticks = duration_ticks


func apply_taunt(agent_index: int, duration_ticks: int = 10) -> void:
	is_taunted = true
	taunt_ticks = duration_ticks
	taunt_target = agent_index


func can_attack_ranged() -> bool:
	return ranged_cooldown <= 0


func can_attack_melee() -> bool:
	return melee_cooldown <= 0


func do_ranged_attack() -> int:
	ranged_cooldown = RANGED_COOLDOWN_TICKS
	return RANGED_DAMAGE


func do_melee_attack() -> int:
	melee_cooldown = MELEE_COOLDOWN_TICKS
	return MELEE_DAMAGE


func tick_timers() -> void:
	## Called once per tick to update all timers.
	if not is_alive():
		return

	# Stamina regeneration
	stamina = minf(stamina + stamina_regen, float(max_stamina))

	# Attack cooldowns
	if ranged_cooldown > 0:
		ranged_cooldown -= 1
	if melee_cooldown > 0:
		melee_cooldown -= 1

	# Slow effect
	if slow_ticks > 0:
		slow_ticks -= 1
		if slow_ticks <= 0:
			is_slowed = false

	# Taunt effect
	if taunt_ticks > 0:
		taunt_ticks -= 1
		if taunt_ticks <= 0:
			is_taunted = false
			taunt_target = -1


func get_role_priority(agent_index: int) -> float:
	## Returns the targeting priority bonus for an agent type.
	## Higher = more likely to be targeted.
	match agent_index:
		0:  # Tank
			return TANK_PRIORITY
		1:  # Healer
			return HEALER_PRIORITY
		2:  # Sniper
			return SNIPER_PRIORITY
	return 0.0
