extends Node

## Autoload singleton that persists training data across scene reloads.
## Registered as "RecordProgress" in Project Settings > Autoload.

var current_episode: int = 0
var num_episodes: int = 100
var victories: int = 0
var defeats: int = 0
var total_samples: int = 0
var is_recording: bool = false
var start_time: int = 0

# Buffer + file management
var data_buffer: Array[Dictionary] = []
var file_counter: int = 0
var samples_per_file: int = 5000
var output_dir: String = "user://training_data"


func start_recording(episodes: int, out_dir: String) -> void:
	current_episode = 0
	num_episodes = episodes
	victories = 0
	defeats = 0
	total_samples = 0
	data_buffer.clear()
	file_counter = 0
	output_dir = out_dir
	is_recording = true
	start_time = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(output_dir)
	print("\n" + "=".repeat(60))
	print("LIVE DATA RECORDING STARTED")
	print("Episodes: ", episodes, " | Output: ", output_dir)
	print("=".repeat(60))


func add_sample(sample: Dictionary) -> void:
	if not is_recording:
		return
	data_buffer.append(sample)
	total_samples += 1
	if data_buffer.size() >= samples_per_file:
		flush_buffer()


func record_episode_result(victory: bool) -> void:
	if not is_recording:
		return
	if victory:
		victories += 1
	else:
		defeats += 1
	current_episode += 1
	# Flush after each episode to avoid data loss
	flush_buffer()

	var win_rate = float(victories) / float(current_episode) * 100.0
	print("[Episode %d/%d] %s | Win rate: %.1f%% | Samples: %d" % [
		current_episode, num_episodes,
		"VICTORY" if victory else "DEFEAT",
		win_rate, total_samples
	])


func has_episodes_remaining() -> bool:
	return is_recording and current_episode < num_episodes


func finish_recording() -> void:
	if not is_recording:
		return
	flush_buffer()
	_write_metadata()
	is_recording = false

	var elapsed = (Time.get_ticks_msec() - start_time) / 1000.0
	print("\n" + "=".repeat(60))
	print("LIVE DATA RECORDING COMPLETE")
	print("=".repeat(60))
	print("Episodes: ", current_episode)
	print("Total samples: ", total_samples)
	print("Win rate: %.1f%%" % (float(victories) / maxi(current_episode, 1) * 100))
	print("Time: %.1f seconds" % elapsed)
	print("Output: ", output_dir)
	print("Files: ", file_counter, " data files + metadata.json")
	print("=".repeat(60))

	Engine.time_scale = 1.0


func flush_buffer() -> void:
	if data_buffer.is_empty():
		return
	var filename = "data_%04d.json" % file_counter
	var filepath = output_dir + "/" + filename
	var file = FileAccess.open(filepath, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data_buffer))
		file.close()
	else:
		print("ERROR: Could not write to ", filepath)
	data_buffer.clear()
	file_counter += 1


func _write_metadata() -> void:
	var elapsed = (Time.get_ticks_msec() - start_time) / 1000.0
	var metadata = {
		"total_episodes": current_episode,
		"total_samples": total_samples,
		"victories": victories,
		"defeats": defeats,
		"win_rate": float(victories) / maxi(current_episode, 1),
		"mcts_iterations": MCTSConfig.ITERATIONS,
		"generation_time_seconds": elapsed,
		"num_files": file_counter,
		"samples_per_file": samples_per_file,
		"node_feature_dim": 11,
		"edge_feature_dim": 6,
		"num_actions": 10,
		"action_names": GraphExporter.ID_TO_ACTION,
		"source": "live_game"
	}
	var file = FileAccess.open(output_dir + "/metadata.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(metadata, "\t"))
		file.close()
