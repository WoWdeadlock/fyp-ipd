class_name RewardCalculator
extends RefCounted

## Heuristic evaluation for MCTS.
## Provides meaningful scores for non-terminal states to guide rollouts.

# Terminal rewards
const WIN_REWARD: float = 1000.0
const LOSE_REWARD: float = -1000.0

# HP component weights
const TANK_HP_WEIGHT: float = 50.0
const HEALER_HP_WEIGHT: float = 80.0    # Healer most valuable
const SNIPER_HP_WEIGHT: float = 60.0
const ALIVE_BONUS: float = 100.0        # Per alive agent (increased)

# Boss damage weight (heavily prioritize killing boss)
const BOSS_DAMAGE_WEIGHT: float = 500.0

# Strategic bonus weights
const TAUNT_BONUS: float = 20.0
const SLOW_BONUS: float = 25.0
const DEFENSIVE_WITH_TAUNT_BONUS: float = 15.0
const SHIELD_ON_SQUISHY_BONUS: float = 10.0

# Stamina penalty
const LOW_STAMINA_PENALTY: float = 5.0
const LOW_STAMINA_THRESHOLD: float = 0.2

# Time penalty (encourage faster wins - increased)
const TIME_PENALTY_PER_TICK: float = 2.0

# Damage potential bonus (reward having agents that can deal damage)
const DAMAGE_POTENTIAL_WEIGHT: float = 30.0


static func evaluate(state: ShadowState) -> float:
	## Returns a score for the given state.
	## Higher is better for the agents, lower is better for the boss.

	# Terminal states get fixed rewards
	if state.is_terminal():
		return get_terminal_reward(state)

	var score: float = 0.0

	# === Boss Damage Component (most important) ===
	var boss_damage_dealt = state.boss.max_hp - state.boss.hp
	var boss_damage_ratio = float(boss_damage_dealt) / float(state.boss.max_hp)
	score += boss_damage_ratio * BOSS_DAMAGE_WEIGHT

	# Bonus for boss being close to death (urgency)
	if state.boss.hp < 200:
		score += 50.0  # Close to winning!
	if state.boss.hp < 100:
		score += 100.0  # Very close!

	# === Agent HP Component ===
	var tank = state.agents[0]
	var healer = state.agents[1]
	var sniper = state.agents[2]

	if tank.is_alive():
		var hp_ratio = float(tank.hp) / float(tank.max_hp)
		score += hp_ratio * TANK_HP_WEIGHT
		score += ALIVE_BONUS

	if healer.is_alive():
		var hp_ratio = float(healer.hp) / float(healer.max_hp)
		score += hp_ratio * HEALER_HP_WEIGHT
		score += ALIVE_BONUS

	if sniper.is_alive():
		var hp_ratio = float(sniper.hp) / float(sniper.max_hp)
		score += hp_ratio * SNIPER_HP_WEIGHT
		score += ALIVE_BONUS

	# === Damage Potential ===
	# Reward having damage dealers alive
	if tank.is_alive() and state.boss.is_alive():
		score += DAMAGE_POTENTIAL_WEIGHT
	if sniper.is_alive() and state.boss.is_alive():
		score += DAMAGE_POTENTIAL_WEIGHT * 1.5  # Sniper does more damage

	# === Strategic State Bonuses ===

	# Taunt active is good (protecting squishies)
	if state.boss.is_taunted:
		score += TAUNT_BONUS

	# Defensive stance while being targeted is excellent
	if tank.defensive_stance_ticks > 0 and state.boss.taunt_target == 0:
		score += DEFENSIVE_WITH_TAUNT_BONUS

	# Slowed boss is advantageous (fewer attacks, easier to kite)
	if state.boss.is_slowed:
		score += SLOW_BONUS

	# Shields on squishy targets
	if healer.shield_ticks > 0:
		score += SHIELD_ON_SQUISHY_BONUS
	if sniper.shield_ticks > 0:
		score += SHIELD_ON_SQUISHY_BONUS

	# === Resource Management ===
	# Penalize being low on stamina (can't use abilities)
	for agent in state.agents:
		if agent.is_alive():
			var stamina_ratio = agent.stamina / float(agent.max_stamina)
			if stamina_ratio < LOW_STAMINA_THRESHOLD:
				score -= LOW_STAMINA_PENALTY

	# === Time Penalty ===
	# Penalty per tick to encourage faster victories
	score -= state.current_tick * TIME_PENALTY_PER_TICK

	return score


static func get_terminal_reward(state: ShadowState) -> float:
	## Returns the reward for a terminal state.
	var outcome = state.get_outcome()
	match outcome:
		"victory":
			# Bonus for faster victories
			var speed_bonus = maxf(0, 100 - state.current_tick)
			return WIN_REWARD + speed_bonus
		"defeat":
			# Less penalty if we dealt significant damage
			var damage_dealt = state.boss.max_hp - state.boss.hp
			var damage_mitigation = float(damage_dealt) / float(state.boss.max_hp) * 200
			return LOSE_REWARD + damage_mitigation
		_:
			return 0.0


static func normalize_reward(raw_reward: float) -> float:
	## Normalize reward to [0, 1] range for UCB calculation.
	## Expected raw range: approximately [-1000, 1200]
	var normalized = (raw_reward + 1000.0) / 2200.0
	return clampf(normalized, 0.0, 1.0)


static func evaluate_normalized(state: ShadowState) -> float:
	## Evaluate and normalize in one call.
	return normalize_reward(evaluate(state))


static func get_action_value_estimate(state: ShadowState, action: Dictionary) -> float:
	## Quick heuristic estimate of an action's value without full simulation.
	## Useful for action ordering in MCTS expansion.
	var value: float = 0.0
	var ability = action.get("ability", "wait")

	match ability:
		"wait":
			value = -10.0  # Slight penalty for waiting (do something!)

		# Damage abilities (highly valued)
		"melee":
			value = 50.0  # Direct damage value
		"shot":
			value = 60.0
		"power":
			value = 100.0
		"cripple":
			value = 45.0 + 30.0  # Damage + slow value

		# Defensive abilities
		"taunt":
			# More valuable if squishies are low
			var healer = state.agents[1]
			var sniper = state.agents[2]
			var min_hp_ratio = 1.0
			if healer.is_alive():
				min_hp_ratio = minf(min_hp_ratio, float(healer.hp) / float(healer.max_hp))
			if sniper.is_alive():
				min_hp_ratio = minf(min_hp_ratio, float(sniper.hp) / float(sniper.max_hp))
			value = 40.0 * (1.0 - min_hp_ratio)  # More valuable when squishies hurt

		"defensive":
			# More valuable when tank is being targeted
			if state.boss.is_taunted and state.boss.taunt_target == 0:
				value = 50.0
			else:
				value = 20.0

		# Support abilities
		"heal":
			var target_name = action.get("target", "")
			var target = state.get_agent_by_name(target_name)
			if target:
				var missing_hp = target.max_hp - target.hp
				value = minf(50.0, float(missing_hp))  # Value of HP restored

		"shield":
			value = 30.0  # Shield is always decent

		"restore":
			value = 15.0  # Stamina restore is lower priority

	return value
