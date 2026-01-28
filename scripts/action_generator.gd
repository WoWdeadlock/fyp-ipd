class_name ActionGenerator
extends RefCounted

## Generates legal actions for MCTS, pruning invalid moves.
## This prevents the tree from growing dead branches (e.g., casting with 0 stamina).


static func get_legal_actions(state: ShadowState) -> Array[Dictionary]:
	## Returns only valid actions for the current micro-turn agent.
	var agent_idx = state.micro_turn_index
	var agent = state.agents[agent_idx]
	var agent_name = state.AGENT_NAMES[agent_idx]
	var actions: Array[Dictionary] = []

	# Dead agents can only wait
	if not agent.is_alive():
		actions.append({"agent": agent_name, "ability": "wait"})
		return actions

	# Always can wait (important for strategic timing)
	actions.append({"agent": agent_name, "ability": "wait"})

	# Generate agent-specific actions
	match agent_idx:
		0:  # Tank
			actions.append_array(_get_tank_actions(agent, state))
		1:  # Healer
			actions.append_array(_get_healer_actions(agent, state))
		2:  # Sniper
			actions.append_array(_get_sniper_actions(agent, state))

	return actions


static func _get_tank_actions(agent: ShadowAgent, state: ShadowState) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []

	# Melee - always available if boss is alive (free ability)
	if state.boss.is_alive():
		actions.append({"agent": "tank", "ability": "melee"})

	# Taunt - requires 15 stamina, boss must be alive
	if agent.stamina >= 15 and state.boss.is_alive():
		actions.append({"agent": "tank", "ability": "taunt"})

	# Defensive stance - requires 10 stamina, not already active
	if agent.stamina >= 10 and agent.defensive_stance_ticks <= 0:
		actions.append({"agent": "tank", "ability": "defensive"})

	return actions


static func _get_healer_actions(agent: ShadowAgent, state: ShadowState) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var tank = state.agents[0]
	var sniper = state.agents[2]

	# Heal - free, target must be alive and not at max HP
	if tank.is_alive() and tank.hp < tank.max_hp:
		actions.append({"agent": "healer", "ability": "heal", "target": "tank"})
	if sniper.is_alive() and sniper.hp < sniper.max_hp:
		actions.append({"agent": "healer", "ability": "heal", "target": "sniper"})

	# Shield - 30 stamina, target alive and doesn't have shield active
	if agent.stamina >= 30:
		if tank.is_alive() and tank.shield_ticks <= 0:
			actions.append({"agent": "healer", "ability": "shield", "target": "tank"})
		if sniper.is_alive() and sniper.shield_ticks <= 0:
			actions.append({"agent": "healer", "ability": "shield", "target": "sniper"})

	# Restore stamina - 50 stamina, target alive and not at max stamina
	if agent.stamina >= 50:
		if tank.is_alive() and tank.stamina < float(tank.max_stamina):
			actions.append({"agent": "healer", "ability": "restore", "target": "tank"})
		if sniper.is_alive() and sniper.stamina < float(sniper.max_stamina):
			actions.append({"agent": "healer", "ability": "restore", "target": "sniper"})

	return actions


static func _get_sniper_actions(agent: ShadowAgent, state: ShadowState) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []

	# Shot - free, boss must be alive
	if state.boss.is_alive():
		actions.append({"agent": "sniper", "ability": "shot"})

	# Crippling shot - 40 stamina, boss alive
	if agent.stamina >= 40 and state.boss.is_alive():
		actions.append({"agent": "sniper", "ability": "cripple"})

	# Power shot - 60 stamina, boss alive
	if agent.stamina >= 60 and state.boss.is_alive():
		actions.append({"agent": "sniper", "ability": "power"})

	return actions


static func get_action_count(state: ShadowState) -> int:
	## Returns the number of legal actions without building the full array.
	## Useful for quick checks.
	return get_legal_actions(state).size()


static func has_damage_actions(state: ShadowState) -> bool:
	## Returns true if any agent can deal damage to the boss.
	## Used for early termination detection.
	if not state.boss.is_alive():
		return false

	# Tank can always melee if alive
	if state.agents[0].is_alive():
		return true

	# Sniper can always shoot if alive
	if state.agents[2].is_alive():
		return true

	# Healer cannot deal damage
	return false
