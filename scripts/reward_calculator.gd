class_name RewardCalculator
extends RefCounted

## Ability-agnostic evaluation for MCTS.
## Scores states using only generic signals (HP, survival, time).
## No per-ability heuristics — new abilities are valued automatically
## through one-step simulation delta in get_action_value_estimate().

# Terminal rewards
const WIN_REWARD: float = 1000.0
const LOSE_REWARD: float = -1000.0

# Weights
const BOSS_DAMAGE_WEIGHT: float = 500.0
const AGENT_HP_WEIGHT: float = 50.0
const ALIVE_BONUS: float = 100.0
const LOW_STAMINA_PENALTY: float = 5.0
const LOW_STAMINA_THRESHOLD: float = 0.2
const TIME_PENALTY_PER_TICK: float = 2.0


static func evaluate(state: ShadowState) -> float:
	## Returns a score for the given state.
	## Uses only ability-agnostic signals: HP ratios, survival, time.

	if state.is_terminal():
		return get_terminal_reward(state)

	var score: float = 0.0

	# === Boss Damage (primary objective) ===
	var boss_dmg_ratio = 1.0 - (float(state.boss.hp) / float(state.boss.max_hp))
	score += boss_dmg_ratio * BOSS_DAMAGE_WEIGHT

	# === Agent Survival ===
	for agent in state.agents:
		if agent.is_alive():
			score += ALIVE_BONUS
			score += (float(agent.hp) / float(agent.max_hp)) * AGENT_HP_WEIGHT

	# === Resource Availability ===
	for agent in state.agents:
		if agent.is_alive():
			if agent.stamina / float(agent.max_stamina) < LOW_STAMINA_THRESHOLD:
				score -= LOW_STAMINA_PENALTY

	# === Time Pressure ===
	score -= state.current_tick * TIME_PENALTY_PER_TICK

	return score


static func get_terminal_reward(state: ShadowState) -> float:
	## Returns the reward for a terminal state.
	var outcome = state.get_outcome()
	match outcome:
		"victory":
			var speed_bonus = maxf(0, 100 - state.current_tick)
			return WIN_REWARD + speed_bonus
		"defeat":
			var damage_dealt = state.boss.max_hp - state.boss.hp
			var damage_mitigation = float(damage_dealt) / float(state.boss.max_hp) * 200
			return LOSE_REWARD + damage_mitigation
		_:
			return 0.0


static func normalize_reward(raw_reward: float) -> float:
	## Normalize reward to [0, 1] range for UCB calculation.
	var normalized = (raw_reward + 1000.0) / 2200.0
	return clampf(normalized, 0.0, 1.0)


static func evaluate_normalized(state: ShadowState) -> float:
	## Evaluate and normalize in one call.
	return normalize_reward(evaluate(state))


static func get_action_value_estimate(state: ShadowState, action: Dictionary) -> float:
	## Estimate action value by simulating forward to the end of the current tick.
	## Applies the action, fills remaining micro-turns with wait, then lets the
	## boss act and timers tick. This captures delayed effects (slow, taunt, etc.)
	## without naming any specific ability.
	var score_before = evaluate(state)

	# Apply the action
	var sim = state.step(action)

	# Fill remaining micro-turns with wait so the full tick completes
	while sim.micro_turn_index != 0 and not sim.is_terminal():
		var agent_name = sim.AGENT_NAMES[sim.micro_turn_index]
		sim = sim.step({"agent": agent_name, "ability": "wait"})

	return (evaluate(sim) - score_before) * 10.0
