class_name RewardCalculator
extends RefCounted

## Ability-agnostic evaluation for MCTS.
## Scores states using only generic signals (HP, survival, time).

# Terminal rewards
const WIN_REWARD: float = 1000.0
const LOSE_REWARD: float = -1000.0

# Weights
const BOSS_DAMAGE_WEIGHT: float = 800.0
const AGENT_HP_WEIGHT: float = 10.0
const ALIVE_BONUS: float = 50.0
const LOW_STAMINA_PENALTY: float = 0.0
const LOW_STAMINA_THRESHOLD: float = 0.2
const TIME_PENALTY_PER_TICK: float = 0.5


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
	## Range: worst = LOSE_REWARD (-1000), best = WIN_REWARD + speed (1100)
	## Non-terminal range roughly [-300, 1000] with current weights
	var normalized = (raw_reward + 1000.0) / 2100.0
	return clampf(normalized, 0.0, 1.0)


static func evaluate_normalized(state: ShadowState) -> float:
	## Evaluate and normalize in one call.
	return normalize_reward(evaluate(state))
