extends Node

## Random AI Controller - Pure random baseline for benchmarking MCTS.
## Randomly selects from all legal actions with uniform probability.
## This demonstrates the worst-case performance without any strategy.

# Configuration
@export var enabled: bool = true
@export var decision_interval: float = 1.5  # Seconds between decisions
@export var show_debug: bool = true
@export var seed_value: int = -1  # -1 = random seed, otherwise deterministic

# References
var tank: Node2D = null
var healer: Node2D = null
var sniper: Node2D = null
var boss: Node2D = null

# State
var time_since_last_decision: float = 0.0
var decisions_made: int = 0
var rng: RandomNumberGenerator

# Statistics
var actions_taken: Dictionary = {
	"tank": {},
	"healer": {},
	"sniper": {}
}
var total_actions: int = 0
var start_time: int = 0
var game_duration: float = 0.0


func _ready():
	if not enabled:
		return

	# Initialize RNG
	rng = RandomNumberGenerator.new()
	if seed_value >= 0:
		rng.seed = seed_value
		print("Random AI using seed: ", seed_value)
	else:
		rng.randomize()

	await get_tree().process_frame

	# Get agent references
	tank = get_tree().get_first_node_in_group("tank")
	healer = get_tree().get_first_node_in_group("healer")
	sniper = get_tree().get_first_node_in_group("sniper")
	boss = get_tree().get_first_node_in_group("boss")

	if not tank or not healer or not sniper or not boss:
		push_error("Random AI: Missing required agents!")
		enabled = false
		return

	print("\n" + "=".repeat(60))
	print("RANDOM AI CONTROLLER ACTIVE")
	print("=".repeat(60))
	print("Pure random action selection - Baseline for MCTS comparison")
	print("Decision interval: ", decision_interval, "s")
	print("Press SPACE to toggle AI on/off")
	print("Press R to restart")
	print("=".repeat(60) + "\n")
	
	start_time = Time.get_ticks_msec()


func _process(delta):
	if not enabled:
		return

	if _is_game_over():
		_on_game_over()
		enabled = false
		return

	game_duration += delta
	time_since_last_decision += delta

	if time_since_last_decision >= decision_interval:
		time_since_last_decision = 0.0
		_make_decisions()


func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE:
				enabled = not enabled
				print("Random AI: ", "ENABLED" if enabled else "DISABLED")
			KEY_R:
				get_tree().reload_current_scene()


func _make_decisions():
	"""Make random decisions for all agents."""
	decisions_made += 1

	# Tank decision
	if _is_agent_alive(tank):
		var action = _get_random_tank_action()
		_execute_tank_action(action)
		_record_action("tank", action)
		if show_debug:
			print("[TANK] ", action)

	await get_tree().create_timer(0.15).timeout

	# Healer decision
	if _is_agent_alive(healer):
		var action = _get_random_healer_action()
		_execute_healer_action(action)
		_record_action("healer", action.ability + "_" + action.get("target", ""))
		if show_debug:
			print("[HEALER] ", action.ability, " -> ", action.get("target", ""))

	await get_tree().create_timer(0.15).timeout

	# Sniper decision
	if _is_agent_alive(sniper):
		var action = _get_random_sniper_action()
		_execute_sniper_action(action)
		_record_action("sniper", action)
		if show_debug:
			print("[SNIPER] ", action)


func _get_random_tank_action() -> String:
	"""Randomly select a valid tank action."""
	var valid_actions = ["wait"]
	
	# Melee is always available (free ability)
	if _is_agent_alive(boss):
		valid_actions.append("melee")
	
	# Taunt requires 15 stamina
	if tank.stamina >= 15 and _is_agent_alive(boss):
		valid_actions.append("taunt")
	
	# Defensive stance requires 10 stamina and not already active
	if tank.stamina >= 10 and not tank.defensive_stance_active:
		valid_actions.append("defensive")
	
	return valid_actions[rng.randi_range(0, valid_actions.size() - 1)]


func _get_random_healer_action() -> Dictionary:
	"""Randomly select a valid healer action."""
	var valid_actions = []
	
	# Wait is always available
	valid_actions.append({"ability": "wait"})
	
	# Heal is free - can target any alive agent not at max HP
	if _is_agent_alive(tank) and tank.health < tank.max_health:
		valid_actions.append({"ability": "heal", "target": "tank"})
	if _is_agent_alive(sniper) and sniper.health < sniper.max_health:
		valid_actions.append({"ability": "heal", "target": "sniper"})
	
	# Shield requires 30 stamina - target must be alive and not have shield
	if healer.stamina >= 30:
		if _is_agent_alive(tank) and not tank.has_shield:
			valid_actions.append({"ability": "shield", "target": "tank"})
		if _is_agent_alive(sniper) and not sniper.has_shield:
			valid_actions.append({"ability": "shield", "target": "sniper"})
	
	# Restore requires 50 stamina - target must be alive and not at max stamina
	if healer.stamina >= 50:
		if _is_agent_alive(tank) and tank.stamina < tank.max_stamina:
			valid_actions.append({"ability": "restore", "target": "tank"})
		if _is_agent_alive(sniper) and sniper.stamina < sniper.max_stamina:
			valid_actions.append({"ability": "restore", "target": "sniper"})
	
	return valid_actions[rng.randi_range(0, valid_actions.size() - 1)]


func _get_random_sniper_action() -> String:
	"""Randomly select a valid sniper action."""
	var valid_actions = ["wait"]
	
	# Shot is free - always available
	if _is_agent_alive(boss):
		valid_actions.append("shot")
	
	# Crippling shot requires 40 stamina
	if sniper.stamina >= 40 and _is_agent_alive(boss):
		valid_actions.append("cripple")
	
	# Power shot requires 60 stamina
	if sniper.stamina >= 60 and _is_agent_alive(boss):
		valid_actions.append("power")
	
	return valid_actions[rng.randi_range(0, valid_actions.size() - 1)]


func _execute_tank_action(action: String):
	"""Execute tank action in the game."""
	match action:
		"melee":
			tank.attempt_melee_attack()
		"taunt":
			tank.taunt_boss()
		"defensive":
			tank.activate_defensive_stance()
		"wait":
			pass  # Do nothing


func _execute_healer_action(action: Dictionary):
	"""Execute healer action in the game."""
	var ability = action.ability
	var target = action.get("target", "")
	
	match ability:
		"heal":
			healer.heal_target(target)
		"shield":
			healer.shield_buff(target)
		"restore":
			healer.restore_stamina(target)
		"wait":
			pass  # Do nothing


func _execute_sniper_action(action: String):
	"""Execute sniper action in the game."""
	match action:
		"shot":
			sniper.attempt_sniper_shot()
		"cripple":
			sniper.attempt_crippling_shot()
		"power":
			sniper.attempt_power_shot()
		"wait":
			pass  # Do nothing


func _is_agent_alive(agent) -> bool:
	"""Check if agent is alive and valid."""
	if not agent:
		return false
	if not is_instance_valid(agent):
		return false
	if not agent.has_method("get") or not "health" in agent:
		return false
	return agent.health > 0


func _is_game_over() -> bool:
	"""Check if the game has ended."""
	var agents_alive = 0
	if _is_agent_alive(tank):
		agents_alive += 1
	if _is_agent_alive(healer):
		agents_alive += 1
	if _is_agent_alive(sniper):
		agents_alive += 1
	
	# Game over if all agents dead or boss is dead
	return agents_alive == 0 or not _is_agent_alive(boss)


func _on_game_over():
	"""Handle game over - print statistics."""
	var end_time = Time.get_ticks_msec()
	var duration_sec = (end_time - start_time) / 1000.0
	
	print("\n" + "=".repeat(60))
	print("RANDOM AI - GAME OVER")
	print("=".repeat(60))
	print("Duration: ", "%.2f" % duration_sec, " seconds")
	print("Decisions made: ", decisions_made)
	print("Total actions: ", total_actions)
	print()
	
	# Determine winner
	if _is_agent_alive(boss):
		print("Result: BOSS WINS")
		var surviving_agents = []
		if not _is_agent_alive(tank):
			surviving_agents.append("Tank")
		if not _is_agent_alive(healer):
			surviving_agents.append("Healer")
		if not _is_agent_alive(sniper):
			surviving_agents.append("Sniper")
		print("Agents defeated: ", ", ".join(surviving_agents))
	else:
		print("Result: AGENTS WIN")
		var survivors = []
		if _is_agent_alive(tank):
			survivors.append("Tank (%d/%d HP)" % [tank.health, tank.max_health])
		if _is_agent_alive(healer):
			survivors.append("Healer (%d/%d HP)" % [healer.health, healer.max_health])
		if _is_agent_alive(sniper):
			survivors.append("Sniper (%d/%d HP)" % [sniper.health, sniper.max_health])
		print("Survivors: ", ", ".join(survivors))
	
	print()
	print("Action Distribution:")
	for agent_name in actions_taken.keys():
		print("  ", agent_name.to_upper(), ":")
		var agent_actions = actions_taken[agent_name]
		var sorted_actions = agent_actions.keys()
		sorted_actions.sort()
		for action in sorted_actions:
			var count = agent_actions[action]
			var percentage = (count * 100.0) / decisions_made if decisions_made > 0 else 0
			print("    ", action, ": ", count, " (%.1f%%)" % percentage)
	
	print("=".repeat(60) + "\n")


func _record_action(agent: String, action: String):
	"""Record action for statistics."""
	total_actions += 1
	if not actions_taken[agent].has(action):
		actions_taken[agent][action] = 0
	actions_taken[agent][action] += 1
