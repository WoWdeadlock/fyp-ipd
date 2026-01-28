extends Node

## Data Generator for GAT Training.
## Runs MCTS simulations and exports (state, action) pairs.

# Configuration
@export var num_episodes: int = 10
@export var mcts_iterations: int = 100
@export var max_steps_per_episode: int = 400
@export var output_dir: String = "user://training_data"
@export var samples_per_file: int = 1000
@export var use_deterministic: bool = true
@export var start_seed: int = 42

# Statistics
var total_samples: int = 0
var current_episode: int = 0
var victories: int = 0
var defeats: int = 0

# Data buffer
var data_buffer: Array[Dictionary] = []
var file_counter: int = 0

# Progress tracking
var start_time: int = 0
var is_generating: bool = false


func _ready():
	# Create output directory
	DirAccess.make_dir_recursive_absolute(output_dir)
	print("Data Generator initialized")
	print("Output directory: ", output_dir)
	print("Configuration:")
	print("  Episodes: ", num_episodes)
	print("  MCTS iterations: ", mcts_iterations)
	print("  Max steps/episode: ", max_steps_per_episode)


func start_generation():
	## Start the data generation process.
	if is_generating:
		print("Already generating!")
		return

	is_generating = true
	start_time = Time.get_ticks_msec()
	current_episode = 0
	total_samples = 0
	victories = 0
	defeats = 0
	data_buffer.clear()
	file_counter = 0

	print("\n" + "=".repeat(60))
	print("STARTING DATA GENERATION")
	print("=".repeat(60))

	# Run generation in batches to avoid blocking
	_generate_batch()


func _generate_batch():
	## Generate a batch of episodes.
	var batch_size = mini(5, num_episodes - current_episode)

	for i in range(batch_size):
		if current_episode >= num_episodes:
			break

		print("\n[Episode ", current_episode + 1, "/", num_episodes, "] Starting...")
		_run_episode(current_episode)
		current_episode += 1
		print("[Episode ", current_episode, "/", num_episodes, "] Complete. Samples: ", data_buffer.size())

		# Yield to prevent freezing
		await get_tree().process_frame

	# Continue or finish
	if current_episode < num_episodes:
		# Schedule next batch
		call_deferred("_generate_batch")
	else:
		_finish_generation()


func _run_episode(episode_idx: int):
	## Run a single episode, collecting (state, action) pairs.

	# Create initial state with optional deterministic seed
	var state = ShadowState.create_initial()
	if use_deterministic:
		state.set_deterministic_seed(start_seed + episode_idx)

	var step = 0

	while not state.is_terminal() and step < max_steps_per_episode:
		# Get current agent
		var agent_idx = state.micro_turn_index
		var agent_name = state.AGENT_NAMES[agent_idx]

		# Skip dead agents
		if not state.agents[agent_idx].is_alive():
			var wait_action = {"agent": agent_name, "ability": "wait"}
			state = state.step(wait_action)
			step += 1
			continue

		# Run MCTS to find optimal action
		var search = MCTSSearch.new(state, mcts_iterations)
		if use_deterministic:
			search.set_seed(start_seed + episode_idx * 1000 + step)

		var best_action = search.search()

		# Export state and action as training sample
		var sample = _create_sample(state, best_action, agent_idx)
		data_buffer.append(sample)
		total_samples += 1

		# Check if buffer needs flushing
		if data_buffer.size() >= samples_per_file:
			_flush_buffer()

		# Apply action
		state = state.step(best_action)
		step += 1

	# Record outcome
	if state.get_outcome() == "victory":
		victories += 1
	else:
		defeats += 1


func _create_sample(state: ShadowState, action: Dictionary, agent_idx: int) -> Dictionary:
	## Create a training sample dictionary.

	# Get graph representation
	var graph = GraphExporter.state_to_graph(state)

	# Get flat features (alternative representation)
	var flat_features = GraphExporter.state_to_flat_features(state)

	# Get action as ID
	var action_id = GraphExporter.action_to_id(action)

	# Get legal actions mask
	var legal_actions = ActionGenerator.get_legal_actions(state)
	var legal_mask = _create_legal_mask(legal_actions, agent_idx)

	# Get target for healer abilities
	var target_idx = -1
	if action.has("target"):
		match action.target:
			"tank": target_idx = 0
			"sniper": target_idx = 2

	return {
		# Graph data
		"node_features": graph.node_features,
		"edge_index": graph.edge_index,
		"edge_attr": graph.edge_attr,

		# Flat features (alternative)
		"flat_features": flat_features,

		# Labels
		"agent_idx": agent_idx,
		"action_id": action_id,
		"target_idx": target_idx,

		# Metadata
		"legal_mask": legal_mask,
		"tick": state.current_tick,
		"boss_hp_ratio": float(state.boss.hp) / float(state.boss.max_hp)
	}


func _create_legal_mask(legal_actions: Array[Dictionary], agent_idx: int) -> Array[int]:
	## Create a binary mask of legal actions.
	var mask: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]  # 10 actions

	for action in legal_actions:
		var action_id = GraphExporter.action_to_id(action)
		mask[action_id] = 1

	return mask


func _flush_buffer():
	## Write buffer to file and clear.
	if data_buffer.is_empty():
		return

	var filename = "data_%04d.json" % file_counter
	var filepath = output_dir + "/" + filename

	var file = FileAccess.open(filepath, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data_buffer))
		file.close()
		print("  Saved ", data_buffer.size(), " samples to ", filename)
	else:
		print("  ERROR: Could not write to ", filepath)

	data_buffer.clear()
	file_counter += 1


func _print_progress():
	## Print progress update.
	var elapsed = (Time.get_ticks_msec() - start_time) / 1000.0
	var eps_per_sec = current_episode / elapsed if elapsed > 0 else 0
	var eta = (num_episodes - current_episode) / eps_per_sec if eps_per_sec > 0 else 0

	print("Episode %d/%d | Samples: %d | Win rate: %.1f%% | %.1f ep/s | ETA: %.0fs" % [
		current_episode, num_episodes,
		total_samples,
		(float(victories) / current_episode * 100) if current_episode > 0 else 0,
		eps_per_sec,
		eta
	])


func _finish_generation():
	## Finalize generation and save metadata.
	is_generating = false

	# Flush remaining data
	_flush_buffer()

	var elapsed = (Time.get_ticks_msec() - start_time) / 1000.0

	# Save metadata
	var metadata = {
		"total_episodes": num_episodes,
		"total_samples": total_samples,
		"victories": victories,
		"defeats": defeats,
		"win_rate": float(victories) / num_episodes if num_episodes > 0 else 0,
		"mcts_iterations": mcts_iterations,
		"generation_time_seconds": elapsed,
		"num_files": file_counter,
		"samples_per_file": samples_per_file,
		"node_feature_dim": 11,  # Features per node
		"edge_feature_dim": 6,   # Features per edge
		"num_actions": 10,
		"action_names": GraphExporter.ID_TO_ACTION
	}

	var meta_file = FileAccess.open(output_dir + "/metadata.json", FileAccess.WRITE)
	if meta_file:
		meta_file.store_string(JSON.stringify(metadata, "\t"))
		meta_file.close()

	print("\n" + "=".repeat(60))
	print("DATA GENERATION COMPLETE")
	print("=".repeat(60))
	print("Episodes: ", num_episodes)
	print("Total samples: ", total_samples)
	print("Win rate: %.1f%%" % (float(victories) / num_episodes * 100))
	print("Time: %.1f seconds" % elapsed)
	print("Output: ", output_dir)
	print("Files: ", file_counter, " data files + metadata.json")
	print("=".repeat(60))


func _input(event):
	# Press G to start generation
	if event is InputEventKey and event.pressed and event.keycode == KEY_G:
		start_generation()


# Callable from external scripts
func generate_sync(episodes: int = -1) -> Dictionary:
	## Synchronous generation (blocks until complete).
	## Returns metadata dictionary.

	if episodes > 0:
		num_episodes = episodes

	current_episode = 0
	total_samples = 0
	victories = 0
	defeats = 0
	data_buffer.clear()
	file_counter = 0
	start_time = Time.get_ticks_msec()

	for ep in range(num_episodes):
		_run_episode(ep)
		current_episode = ep + 1

		if current_episode % 50 == 0:
			_print_progress()

	_finish_generation()

	return {
		"total_samples": total_samples,
		"victories": victories,
		"defeats": defeats,
		"output_dir": output_dir
	}
