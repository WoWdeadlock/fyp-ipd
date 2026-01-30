extends BaseAIController

## Random AI Controller - Picks completely random legal actions for comparison with MCTS.

@export var enabled: bool = true
@export var decision_interval: float = 2.0
@export var show_debug: bool = true

# Recording configuration
@export var record_data: bool = false
@export var num_record_episodes: int = 10
@export var output_dir: String = "user://training_data_random"
@export var time_scale: float = 50.0

# State
var time_since_last_decision: float = 0.0
var is_executing: bool = false


func _ready():
	if not enabled:
		return

	await get_tree().process_frame

	if not setup_references():
		enabled = false
		return

	if record_data and not RecordProgress.is_recording:
		RecordProgress.start_recording(num_record_episodes, output_dir)
		Engine.time_scale = time_scale
		show_debug = false

	print("\n" + "=".repeat(50))
	print("RANDOM AI CONTROLLER ACTIVE")
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
				print("Random AI: ", "ENABLED" if enabled else "DISABLED")
			KEY_R:
				get_tree().reload_current_scene()


func _make_decision():
	is_executing = true

	var shadow_state = mcts_bridge.create_shadow_state()

	if shadow_state.is_terminal():
		is_executing = false
		return

	var actions_to_execute: Array[Dictionary] = []

	for i in range(3):
		var agent_name = shadow_state.AGENT_NAMES[i]
		var agent = shadow_state.agents[i]

		if not agent.is_alive():
			var wait_action = {"agent": agent_name, "ability": "wait"}
			shadow_state = shadow_state.step(wait_action)
			continue

		var legal_actions = ActionGenerator.get_legal_actions(shadow_state)

		if legal_actions.is_empty():
			var wait_action = {"agent": agent_name, "ability": "wait"}
			shadow_state = shadow_state.step(wait_action)
			continue

		# Pick a completely random legal action
		var random_action = legal_actions[randi() % legal_actions.size()]

		if record_data and RecordProgress.is_recording:
			record_sample(shadow_state, random_action, i)

		if show_debug:
			print("[%s] RANDOM: %s%s" % [
				agent_name.to_upper(),
				random_action.get("ability", "wait"),
				" -> " + random_action.get("target", "") if random_action.has("target") and random_action.target != "" else ""
			])

		actions_to_execute.append(random_action)
		shadow_state = shadow_state.step(random_action)

	for action in actions_to_execute:
		execute_action(action)
		await get_tree().create_timer(0.3).timeout

	decisions_made += 1
	is_executing = false


func _on_game_over():
	var victory = check_victory()

	if not RecordProgress.is_recording:
		print_game_over_stats(victory)
		return

	RecordProgress.record_episode_result(victory)

	if RecordProgress.has_episodes_remaining():
		get_tree().reload_current_scene()
	else:
		RecordProgress.finish_recording()
