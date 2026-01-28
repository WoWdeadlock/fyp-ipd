extends Node

## Simple AI Controller - Random/Heuristic baseline for comparison.
## Use this to see how the boss fairs against non-optimal play.

# Configuration
@export var enabled: bool = true
@export var decision_interval: float = 1.0
@export var ai_mode: String = "random"  # "random", "aggressive", "defensive"
@export var show_debug: bool = true

# References
var tank: Node2D = null
var healer: Node2D = null
var sniper: Node2D = null
var boss: Node2D = null

# State
var time_since_last_decision: float = 0.0
var decisions_made: int = 0

# Statistics
var actions_taken: Dictionary = {}
var start_time: int = 0


func _ready():
	if not enabled:
		return

	await get_tree().process_frame

	tank = get_tree().get_first_node_in_group("tank")
	healer = get_tree().get_first_node_in_group("healer")
	sniper = get_tree().get_first_node_in_group("sniper")
	boss = get_tree().get_first_node_in_group("boss")

	print("\n" + "=".repeat(50))
	print("SIMPLE AI CONTROLLER ACTIVE")
	print("=".repeat(50))
	print("Mode: ", ai_mode.to_upper())
	print("Press SPACE to toggle AI on/off")
	print("Press 1/2/3 to switch modes (random/aggressive/defensive)")
	print("=".repeat(50) + "\n")
	start_time = Time.get_ticks_msec()


func _process(delta):
	if not enabled:
		return

	if _is_game_over():
		_on_game_over()
		enabled = false
		return

	time_since_last_decision += delta

	if time_since_last_decision >= decision_interval:
		time_since_last_decision = 0.0
		_make_decisions()


func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE:
				enabled = not enabled
				print("Simple AI: ", "ENABLED" if enabled else "DISABLED")
			KEY_1:
				ai_mode = "random"
				print("Mode: RANDOM")
			KEY_2:
				ai_mode = "aggressive"
				print("Mode: AGGRESSIVE")
			KEY_3:
				ai_mode = "defensive"
				print("Mode: DEFENSIVE")
			KEY_R:
				get_tree().reload_current_scene()


func _make_decisions():
	decisions_made += 1

	# Tank decision
	if tank and is_instance_valid(tank) and tank.health > 0:
		var action = _get_tank_action()
		_execute_tank_action(action)
		if show_debug:
			print("[TANK] ", action)

	await get_tree().create_timer(0.2).timeout

	# Healer decision
	if healer and is_instance_valid(healer) and healer.health > 0:
		var action = _get_healer_action()
		_execute_healer_action(action)
		if show_debug:
			print("[HEALER] ", action.ability, " -> ", action.get("target", ""))

	await get_tree().create_timer(0.2).timeout

	# Sniper decision
	if sniper and is_instance_valid(sniper) and sniper.health > 0:
		var action = _get_sniper_action()
		_execute_sniper_action(action)
		if show_debug:
			print("[SNIPER] ", action)


func _get_tank_action() -> String:
	match ai_mode:
		"random":
			return ["melee", "melee", "taunt", "defensive", "wait"].pick_random()
		"aggressive":
			return "melee"  # Always attack
		"defensive":
			# Taunt if not active, else defensive, else melee
			if tank.stamina >= 15:
				return "taunt"
			elif tank.stamina >= 10:
				return "defensive"
			return "melee"
	return "melee"


func _get_healer_action() -> Dictionary:
	# Find most damaged ally
	var targets = []
	if tank and is_instance_valid(tank) and tank.health > 0:
		targets.append({"name": "tank", "node": tank, "missing": tank.max_health - tank.health})
	if sniper and is_instance_valid(sniper) and sniper.health > 0:
		targets.append({"name": "sniper", "node": sniper, "missing": sniper.max_health - sniper.health})

	match ai_mode:
		"random":
			var abilities = ["heal", "heal", "shield", "restore", "wait"]
			var ability = abilities.pick_random()
			var target = "tank"
			if targets.size() > 0:
				target = targets.pick_random().name
			return {"ability": ability, "target": target}

		"aggressive":
			# Heal whoever is most damaged
			if targets.size() > 0:
				targets.sort_custom(func(a, b): return a.missing > b.missing)
				if targets[0].missing > 30:
					return {"ability": "heal", "target": targets[0].name}
			return {"ability": "wait", "target": ""}

		"defensive":
			# Prioritize shields and heals
			if targets.size() > 0:
				targets.sort_custom(func(a, b): return a.missing > b.missing)
				var most_hurt = targets[0]
				if most_hurt.missing > 40:
					return {"ability": "heal", "target": most_hurt.name}
				if healer.stamina >= 30:
					return {"ability": "shield", "target": most_hurt.name}
			return {"ability": "heal", "target": "tank"}

	return {"ability": "wait", "target": ""}


func _get_sniper_action() -> String:
	match ai_mode:
		"random":
			return ["shot", "shot", "cripple", "power", "wait"].pick_random()
		"aggressive":
			# Use power shot if available, else regular shot
			if sniper.stamina >= 60:
				return "power"
			return "shot"
		"defensive":
			# Cripple to slow boss, else shot
			if sniper.stamina >= 40:
				return "cripple"
			return "shot"
	return "shot"


func _execute_tank_action(action: String):
	actions_taken[action] = actions_taken.get(action, 0) + 1

	match action:
		"melee":
			if tank.has_method("attempt_melee_attack"):
				tank.attempt_melee_attack()
		"taunt":
			if tank.has_method("taunt_boss"):
				tank.taunt_boss()
		"defensive":
			if tank.has_method("activate_defensive_stance"):
				tank.activate_defensive_stance()


func _execute_healer_action(action: Dictionary):
	var ability = action.get("ability", "wait")
	var target = action.get("target", "")

	actions_taken[ability] = actions_taken.get(ability, 0) + 1

	match ability:
		"heal":
			if healer.has_method("heal_target"):
				healer.heal_target(target)
		"shield":
			if healer.has_method("shield_buff"):
				healer.shield_buff(target)
		"restore":
			if healer.has_method("restore_stamina"):
				healer.restore_stamina(target)


func _execute_sniper_action(action: String):
	actions_taken[action] = actions_taken.get(action, 0) + 1

	match action:
		"shot":
			if sniper.has_method("attempt_sniper_shot"):
				sniper.attempt_sniper_shot()
		"cripple":
			if sniper.has_method("use_crippling_shot"):
				sniper.use_crippling_shot()
		"power":
			if sniper.has_method("use_power_shot"):
				sniper.use_power_shot()


func _is_game_over() -> bool:
	if not boss or not is_instance_valid(boss) or boss.health <= 0:
		return true

	var any_alive = false
	for agent in [tank, healer, sniper]:
		if agent and is_instance_valid(agent) and agent.health > 0:
			any_alive = true
			break

	return not any_alive


func _on_game_over():
	var elapsed = (Time.get_ticks_msec() - start_time) / 1000.0
	var victory = boss and is_instance_valid(boss) and boss.health <= 0

	print("\n" + "=".repeat(50))
	print("GAME OVER - ", "VICTORY!" if victory else "DEFEAT")
	print("=".repeat(50))
	print("AI Mode: ", ai_mode.to_upper())
	print("Time: %.1f seconds" % elapsed)
	print("Decisions made: ", decisions_made)

	if boss and is_instance_valid(boss):
		print("Boss HP remaining: ", boss.health, "/600")

	print("\nAction breakdown:")
	for action_name in actions_taken:
		print("  %s: %d" % [action_name, actions_taken[action_name]])

	print("=".repeat(50))
	print("Press R to restart, 1/2/3 to change mode")
	print("=".repeat(50) + "\n")
