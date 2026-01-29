extends Node

## MCTS AI Controller - Plays the game in real-time with MCTS decisions.
## Optionally records training data from live gameplay.

# Configuration
@export var enabled: bool = true
@export var mcts_iterations: int = MCTSConfig.ITERATIONS
@export var decision_interval: float = 2.0  # Seconds between decisions
@export var use_deterministic: bool = false
@export var show_debug: bool = true

# Recording configuration
@export var record_data: bool = false
@export var num_record_episodes: int = 10
@export var output_dir: String = "user://training_data"
@export var time_scale: float = 3.0

# References
var mcts_bridge: Node = null
var tank: Node2D = null
var healer: Node2D = null
var sniper: Node2D = null
var boss: Node2D = null

# State
var time_since_last_decision: float = 0.0
var current_seed: int = 0
var decisions_made: int = 0
var is_executing: bool = false

# Statistics
var actions_taken: Dictionary = {}
var total_damage_dealt: int = 0
var start_time: int = 0


func _ready():
	if not enabled:
		return

	# Wait for scene to initialize
	await get_tree().process_frame

	# Get references
	tank = get_tree().get_first_node_in_group("tank")
	healer = get_tree().get_first_node_in_group("healer")
	sniper = get_tree().get_first_node_in_group("sniper")
	boss = get_tree().get_first_node_in_group("boss")
	mcts_bridge = get_node_or_null("../MCTSBridge")

	if not mcts_bridge:
		mcts_bridge = get_tree().get_first_node_in_group("mcts_bridge")

	if not mcts_bridge:
		for child in get_parent().get_children():
			if child.has_method("run_mcts_search"):
				mcts_bridge = child
				break

	if not mcts_bridge:
		print("ERROR: Could not find MCTSBridge!")
		enabled = false
		return

	# Override settings from command line (for parallel runs)
	_parse_cmdline_args()

	# Start recording if enabled
	if record_data and not RecordProgress.is_recording:
		RecordProgress.start_recording(num_record_episodes, output_dir)
		Engine.time_scale = time_scale
		show_debug = false  # Reduce noise during batch recording

	print("\n" + "=".repeat(50))
	print("MCTS AI CONTROLLER ACTIVE")
	if RecordProgress.is_recording:
		print("RECORDING: Episode %d/%d | Time scale: %.1fx" % [
			RecordProgress.current_episode + 1,
			RecordProgress.num_episodes,
			time_scale
		])
	print("=".repeat(50))
	start_time = Time.get_ticks_msec()


func _process(delta):
	if not enabled or is_executing:
		return

	if _is_game_over():
		_on_game_over()
		enabled = false
		return

	time_since_last_decision += delta

	if time_since_last_decision >= decision_interval:
		time_since_last_decision = 0.0
		_make_decision()


func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE:
				enabled = not enabled
				print("AI Controller: ", "ENABLED" if enabled else "DISABLED")
			KEY_R:
				get_tree().reload_current_scene()


func _make_decision():
	## Run MCTS and execute the best action for each agent.
	is_executing = true

	# Create shadow state from live game
	var shadow_state = mcts_bridge.create_shadow_state()

	if shadow_state.is_terminal():
		is_executing = false
		return

	# Get decisions for all 3 agents in sequence (micro-turns)
	var actions_to_execute: Array[Dictionary] = []

	for i in range(3):
		var agent_name = shadow_state.AGENT_NAMES[i]
		var agent = shadow_state.agents[i]

		if not agent.is_alive():
			var wait_action = {"agent": agent_name, "ability": "wait"}
			shadow_state = shadow_state.step(wait_action)
			continue

		if shadow_state.micro_turn_index != i:
			print("WARNING: micro_turn mismatch! Expected ", i, " got ", shadow_state.micro_turn_index)

		# Run MCTS
		var seed_val = -1
		if use_deterministic:
			current_seed += 1
			seed_val = current_seed

		var search = MCTSSearch.new(shadow_state, mcts_iterations)
		if seed_val >= 0:
			search.set_seed(seed_val)

		var result = search.search_with_stats()
		var best_action = result.best_action

		# Record training sample before advancing state
		if RecordProgress.is_recording:
			_record_sample(shadow_state, best_action, i)

		if best_action.get("ability") == "wait":
			var legal = ActionGenerator.get_legal_actions(shadow_state)
			var non_wait = legal.filter(func(a): return a.get("ability") != "wait")
			if non_wait.size() > 0 and show_debug:
				print("  WARNING: Chose wait but had options: ", non_wait)

		if show_debug:
			_print_decision(agent_name, result)

		actions_to_execute.append(best_action)
		shadow_state = shadow_state.step(best_action)

	# Execute all actions in the real game
	for action in actions_to_execute:
		_execute_action(action)
		await get_tree().create_timer(0.3).timeout

	decisions_made += 1
	is_executing = false


func _record_sample(state: ShadowState, action: Dictionary, agent_idx: int) -> void:
	## Create and record a training sample from live game state.
	var graph = GraphExporter.state_to_graph(state)
	var flat_features = GraphExporter.state_to_flat_features(state)
	var action_id = GraphExporter.action_to_id(action)
	var legal_actions = ActionGenerator.get_legal_actions(state)
	var legal_mask = _create_legal_mask(legal_actions)

	var target_idx = -1
	if action.has("target"):
		match action.target:
			"tank": target_idx = 0
			"sniper": target_idx = 2

	var sample = {
		"node_features": graph.node_features,
		"edge_index": graph.edge_index,
		"edge_attr": graph.edge_attr,
		"flat_features": flat_features,
		"agent_idx": agent_idx,
		"action_id": action_id,
		"target_idx": target_idx,
		"legal_mask": legal_mask,
		"tick": decisions_made,
		"boss_hp_ratio": float(state.boss.hp) / float(state.boss.max_hp)
	}

	RecordProgress.add_sample(sample)


func _create_legal_mask(legal_actions: Array[Dictionary]) -> Array[int]:
	var mask: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	for action in legal_actions:
		var action_id = GraphExporter.action_to_id(action)
		mask[action_id] = 1
	return mask


func _execute_action(action: Dictionary):
	## Execute an action in the real game.
	var agent_name = action.get("agent", "")
	var ability = action.get("ability", "wait")
	var target = action.get("target", "")

	if ability == "wait":
		return

	actions_taken[ability] = actions_taken.get(ability, 0) + 1

	var agent: Node2D = null
	match agent_name:
		"tank": agent = tank
		"healer": agent = healer
		"sniper": agent = sniper

	if not agent or not is_instance_valid(agent) or agent.health <= 0:
		return

	match [agent_name, ability]:
		["tank", "melee"]:
			if agent.has_method("attempt_melee_attack"):
				agent.attempt_melee_attack()
				total_damage_dealt += 35
		["tank", "taunt"]:
			if agent.has_method("taunt_boss"):
				agent.taunt_boss()
		["tank", "defensive"]:
			if agent.has_method("activate_defensive_stance"):
				agent.activate_defensive_stance()

		["healer", "heal"]:
			if agent.has_method("heal_target"):
				agent.heal_target(target)
		["healer", "shield"]:
			if agent.has_method("shield_buff"):
				agent.shield_buff(target)
		["healer", "restore"]:
			if agent.has_method("restore_stamina"):
				agent.restore_stamina(target)

		["sniper", "shot"]:
			if agent.has_method("attempt_sniper_shot"):
				agent.attempt_sniper_shot()
				total_damage_dealt += 45
		["sniper", "cripple"]:
			if agent.has_method("use_crippling_shot"):
				agent.use_crippling_shot()
				total_damage_dealt += 25
		["sniper", "power"]:
			if agent.has_method("use_power_shot"):
				agent.use_power_shot()
				total_damage_dealt += 85


func _print_decision(agent_name: String, result: Dictionary):
	var action = result.best_action
	var ability = action.get("ability", "wait")
	var target = action.get("target", "")

	var action_str = ability
	if target:
		action_str += " -> " + target

	print("[%s] %s (visits: %d)" % [
		agent_name.to_upper(),
		action_str,
		result.root_visits
	])

	if result.has("children_stats") and result.children_stats.size() > 1:
		var alts = []
		for i in range(mini(3, result.children_stats.size())):
			var child = result.children_stats[i]
			alts.append("%s: %.0f%%" % [
				child.action.get("ability", "?"),
				child.avg_reward * 100
			])
		print("  Alternatives: ", ", ".join(alts))


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

	var victory = false
	if not boss or not is_instance_valid(boss):
		victory = true
	elif boss.health <= 0:
		victory = true

	if not RecordProgress.is_recording:
		# Normal game over display
		print("\n" + "=".repeat(50))
		print("GAME OVER - ", "VICTORY!" if victory else "DEFEAT")
		print("=".repeat(50))
		print("Time: %.1f seconds" % elapsed)
		print("Decisions made: ", decisions_made)
		print("Total damage dealt: ", total_damage_dealt)
		if boss and is_instance_valid(boss):
			print("Boss HP remaining: ", boss.health, "/650")
		print("\nAction breakdown:")
		for action_name in actions_taken:
			print("  %s: %d" % [action_name, actions_taken[action_name]])
		print("=".repeat(50))
		print("Press R to restart")
		print("=".repeat(50) + "\n")
		return

	# Recording mode: log result and auto-restart
	RecordProgress.record_episode_result(victory)

	if RecordProgress.has_episodes_remaining():
		# Auto-restart for next episode
		get_tree().reload_current_scene()
	else:
		RecordProgress.finish_recording()
		if _should_quit_on_finish():
			get_tree().quit()


func _parse_cmdline_args():
	## Parse command line args for parallel batch runs.
	## Usage: godot --path <project> -- --record --episodes 50 --output user://training_data/worker_0
	var args = OS.get_cmdline_user_args()
	var i = 0
	while i < args.size():
		match args[i]:
			"--record":
				record_data = true
			"--episodes":
				i += 1
				if i < args.size():
					num_record_episodes = int(args[i])
			"--output":
				i += 1
				if i < args.size():
					output_dir = args[i]
			"--timescale":
				i += 1
				if i < args.size():
					time_scale = float(args[i])
		i += 1


func _should_quit_on_finish() -> bool:
	return OS.get_cmdline_user_args().has("--record")
