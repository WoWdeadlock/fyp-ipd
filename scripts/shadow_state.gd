class_name ShadowState
extends RefCounted

## Core state container for MCTS shadow simulation.
## Implements step(action) -> new_state for instant state transitions.

# Agent order: [tank, healer, sniper]
var agents: Array[ShadowAgent] = []
var boss: ShadowBoss

# Turn management
var current_tick: int = 0
var micro_turn_index: int = 0  # 0=tank, 1=healer, 2=sniper

# Deterministic mode for reproducible MCTS
var deterministic_mode: bool = false
var rng: RandomNumberGenerator = null

# Constants
const TICKS_PER_SECOND: float = 2.0
const AGENT_NAMES: Array[String] = ["tank", "healer", "sniper"]

# Tick conversions for durations
const TAUNT_TICKS: int = 10      # 5 seconds
const DEFENSIVE_TICKS: int = 14  # 7 seconds
const SHIELD_TICKS: int = 12     # 6 seconds
const SLOW_TICKS: int = 16       # 8 seconds


static func create_initial() -> ShadowState:
	## Creates a fresh game state with all units at full health.
	var state = ShadowState.new()
	state.agents.append(ShadowAgent.create_tank())
	state.agents.append(ShadowAgent.create_healer())
	state.agents.append(ShadowAgent.create_sniper())
	state.boss = ShadowBoss.create()
	return state


func clone() -> ShadowState:
	## Deep copy for MCTS tree branching.
	var copy = ShadowState.new()

	for agent in agents:
		copy.agents.append(agent.clone())

	copy.boss = boss.clone()
	copy.current_tick = current_tick
	copy.micro_turn_index = micro_turn_index
	copy.deterministic_mode = deterministic_mode

	if deterministic_mode and rng:
		copy.rng = RandomNumberGenerator.new()
		copy.rng.state = rng.state

	return copy


func set_deterministic_seed(seed_value: int) -> void:
	## Enable deterministic mode with a fixed seed.
	deterministic_mode = true
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value


func step(action: Dictionary) -> ShadowState:
	## Main simulation function. Returns a NEW state after applying the action.
	## Does NOT modify this state (immutable pattern for MCTS).
	var new_state = self.clone()

	# Apply the action for the current micro-turn agent
	new_state._apply_agent_action(micro_turn_index, action)

	# Advance micro-turn
	new_state.micro_turn_index += 1

	# If all agents have acted, process boss turn and tick timers
	if new_state.micro_turn_index >= 3:
		new_state.micro_turn_index = 0
		new_state._process_boss_turn()
		new_state._tick_all_timers()
		new_state.current_tick += 1

	return new_state


func is_terminal() -> bool:
	## Check if the game has ended.
	# Victory: Boss is dead
	if boss.hp <= 0:
		return true

	# Defeat: All agents dead
	var any_alive = false
	for agent in agents:
		if agent.is_alive():
			any_alive = true
			break
	if not any_alive:
		return true

	# Unwinnable: Only healer alive (can't deal damage)
	if agents[1].is_alive() and not agents[0].is_alive() and not agents[2].is_alive():
		return true

	return false


func get_outcome() -> String:
	## Returns "victory", "defeat", or "" for non-terminal states.
	if boss.hp <= 0:
		return "victory"

	var any_alive = false
	var only_healer = agents[1].is_alive() and not agents[0].is_alive() and not agents[2].is_alive()

	for agent in agents:
		if agent.is_alive():
			any_alive = true
			break

	if not any_alive or only_healer:
		return "defeat"

	return ""


func get_current_agent_index() -> int:
	return micro_turn_index


func get_current_agent_name() -> String:
	if micro_turn_index >= 0 and micro_turn_index < AGENT_NAMES.size():
		return AGENT_NAMES[micro_turn_index]
	return ""


func get_agent_by_name(agent_name: String) -> ShadowAgent:
	match agent_name:
		"tank":
			return agents[0]
		"healer":
			return agents[1]
		"sniper":
			return agents[2]
	return null


func get_agent_index_by_name(agent_name: String) -> int:
	match agent_name:
		"tank":
			return 0
		"healer":
			return 1
		"sniper":
			return 2
	return -1


func _apply_agent_action(agent_idx: int, action: Dictionary) -> void:
	## Apply an action for the specified agent.
	var agent = agents[agent_idx]
	var ability = action.get("ability", "wait")
	var target_name = action.get("target", "")

	if ability == "wait" or not agent.is_alive():
		return

	match agent_idx:
		0:  # Tank
			_apply_tank_action(agent, ability)
		1:  # Healer
			_apply_healer_action(agent, ability, target_name)
		2:  # Sniper
			_apply_sniper_action(agent, ability)


func _apply_tank_action(agent: ShadowAgent, ability: String) -> void:
	match ability:
		"melee":
			# Free, 35 damage to boss
			if boss.is_alive():
				boss.take_damage(35)

		"taunt":
			# 15 stamina, force boss to target tank for 5s
			if agent.spend_stamina(15) and boss.is_alive():
				boss.apply_taunt(0, TAUNT_TICKS)

		"defensive":
			# 10 stamina, 70% damage reduction for 7s
			if agent.spend_stamina(10):
				agent.defensive_stance_ticks = DEFENSIVE_TICKS


func _apply_healer_action(agent: ShadowAgent, ability: String, target_name: String) -> void:
	var target = get_agent_by_name(target_name)

	match ability:
		"heal":
			# Free, 50 HP to target
			if target and target.is_alive():
				target.heal(50)

		"shield":
			# 30 stamina, 50% damage reduction for 6s
			if target and target.is_alive() and agent.spend_stamina(30):
				target.shield_ticks = SHIELD_TICKS

		"restore":
			# 50 stamina cost, restore 60 stamina to target
			if target and target.is_alive() and agent.spend_stamina(50):
				target.restore_stamina(60)


func _apply_sniper_action(agent: ShadowAgent, ability: String) -> void:
	match ability:
		"shot":
			# Free, 45 damage to boss
			if boss.is_alive():
				boss.take_damage(45)

		"cripple":
			# 40 stamina, 25 damage + slow for 8s
			if agent.spend_stamina(40) and boss.is_alive():
				boss.take_damage(25)
				boss.apply_slow(SLOW_TICKS)

		"power":
			# 60 stamina, 85 damage
			if agent.spend_stamina(60) and boss.is_alive():
				boss.take_damage(85)


func _process_boss_turn() -> void:
	## Simulate boss AI for one turn.
	## Boss can use BOTH melee and ranged attacks if available.
	if not boss.is_alive():
		return

	# Skip if no attacks available
	if not boss.can_attack_melee() and not boss.can_attack_ranged():
		return

	# Melee attack (if available)
	if boss.can_attack_melee():
		var target_idx = _select_boss_target()
		if target_idx >= 0:
			var target = agents[target_idx]
			if target.is_alive():
				var damage = boss.do_melee_attack()
				target.take_damage(damage)

	# Ranged attack on potentially different target (if available)
	if boss.can_attack_ranged():
		var target_idx = _select_boss_target()
		if target_idx >= 0:
			var target = agents[target_idx]
			if target.is_alive():
				var damage = boss.do_ranged_attack()
				target.take_damage(damage)


func _select_boss_target() -> int:
	## Select which agent the boss will attack.
	## Returns agent index (0, 1, 2) or -1 if no valid target.

	# If taunted, must target the taunt source (tank)
	if boss.is_taunted and boss.taunt_target >= 0:
		var taunt_target = agents[boss.taunt_target]
		if taunt_target.is_alive():
			return boss.taunt_target

	# Build candidate list from alive agents
	var candidates: Array[Dictionary] = []
	for i in range(3):
		if not agents[i].is_alive():
			continue

		var agent = agents[i]
		var hp_ratio = float(agent.hp) / float(agent.max_hp)
		var hp_score = (1.0 - hp_ratio) * 100.0  # Low HP = high priority

		var role_bonus = boss.get_role_priority(i)

		# Lower score = higher priority target
		var score = -hp_score - role_bonus
		candidates.append({"idx": i, "score": score})

	if candidates.is_empty():
		return -1

	# Sort by score (ascending = best first)
	candidates.sort_custom(func(a, b): return a.score < b.score)

	# Probabilistic selection (aggressive: 75/20/5)
	var roll = _get_random_float()

	if candidates.size() == 1:
		return candidates[0].idx
	elif candidates.size() == 2:
		if roll < 0.85:
			return candidates[0].idx
		else:
			return candidates[1].idx
	else:
		if roll < 0.75:
			return candidates[0].idx
		elif roll < 0.95:
			return candidates[1].idx
		else:
			return candidates[2].idx


func _get_random_float() -> float:
	## Get a random float, using seeded RNG if in deterministic mode.
	if deterministic_mode and rng:
		return rng.randf()
	return randf()


func _tick_all_timers() -> void:
	## Called at the end of each full turn to update all timers.
	for agent in agents:
		agent.tick_timers()
	boss.tick_timers()


func to_dict() -> Dictionary:
	## Serialize state to dictionary (for debugging/logging).
	return {
		"tick": current_tick,
		"micro_turn": micro_turn_index,
		"tank": {
			"hp": agents[0].hp,
			"stamina": agents[0].stamina,
			"defensive": agents[0].defensive_stance_ticks,
			"shield": agents[0].shield_ticks
		},
		"healer": {
			"hp": agents[1].hp,
			"stamina": agents[1].stamina
		},
		"sniper": {
			"hp": agents[2].hp,
			"stamina": agents[2].stamina,
			"shield": agents[2].shield_ticks
		},
		"boss": {
			"hp": boss.hp,
			"slowed": boss.is_slowed,
			"taunted": boss.is_taunted,
			"taunt_target": boss.taunt_target
		},
		"terminal": is_terminal(),
		"outcome": get_outcome()
	}
