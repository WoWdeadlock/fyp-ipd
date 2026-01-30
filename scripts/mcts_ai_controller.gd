extends BaseAIController

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

# State
var time_since_last_decision: float = 0.0
var current_seed: int = 0
var is_executing: bool = false


func _ready():
	if not enabled:
		return

	await get_tree().process_frame

	if not setup_references():
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


func _process(delta):
	if not enabled or is_executing:
		return

	if is_game_over():
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
			record_sample(shadow_state, best_action, i)

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
		execute_action(action)
		await get_tree().create_timer(0.3).timeout

	decisions_made += 1
	is_executing = false


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


func _on_game_over():
	var victory = check_victory()

	if not RecordProgress.is_recording:
		print_game_over_stats(victory)
		return

	# Recording mode: log result and auto-restart
	RecordProgress.record_episode_result(victory)

	if RecordProgress.has_episodes_remaining():
		get_tree().reload_current_scene()
	else:
		RecordProgress.finish_recording()
		if _should_quit_on_finish():
			get_tree().quit()


func _parse_cmdline_args():
	## Parse command line args for parallel batch runs.
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
