extends BaseAIController

## GAT AI Controller - Uses a trained Graph Attention Network for agent decisions.
## Connects to a Python inference server over TCP (localhost).
##
## Start the server first:
##   python inference_server.py <checkpoint_dir> --port 5555

@export var enabled: bool = true
@export var decision_interval: float = 2.0
@export var show_debug: bool = true
@export var server_port: int = 5555

# Networking
var tcp: StreamPeerTCP = null
var is_connected: bool = false

# State
var time_since_last_decision: float = 0.0
var is_executing: bool = false

# GAT-specific stats
var total_inference_time_ms: int = 0


func _ready():
	if not enabled:
		return

	await get_tree().process_frame

	if not setup_references():
		enabled = false
		return

	# Connect to inference server
	_connect_to_server()

	if not is_connected:
		print("ERROR: Could not connect to inference server on port %d" % server_port)
		print("Start the server first: python inference_server.py <checkpoint_dir> --port %d" % server_port)
		enabled = false
		return

	print("\n" + "=".repeat(50))
	print("GAT AI CONTROLLER ACTIVE")
	print("Connected to inference server on port %d" % server_port)
	print("=".repeat(50))


func _connect_to_server():
	tcp = StreamPeerTCP.new()
	var err = tcp.connect_to_host("127.0.0.1", server_port)
	if err != OK:
		return

	# Wait for connection (up to 5 seconds)
	var waited = 0.0
	while tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING and waited < 5.0:
		tcp.poll()
		OS.delay_msec(100)
		waited += 0.1

	tcp.poll()
	is_connected = tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED


func _process(delta):
	if not enabled or is_executing or not is_connected:
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
				print("GAT AI: ", "ENABLED" if enabled else "DISABLED")
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

		# Build graph from current state
		var graph = GraphExporter.state_to_graph(shadow_state)
		var legal_actions = ActionGenerator.get_legal_actions(shadow_state)
		var legal_mask = create_legal_mask(legal_actions)

		# Request inference
		var request = {
			"node_features": graph.node_features,
			"edge_index": graph.edge_index,
			"edge_attr": graph.edge_attr,
			"agent_idx": i,
			"legal_mask": legal_mask
		}

		var t0 = Time.get_ticks_msec()
		var response = _send_request(request)
		total_inference_time_ms += Time.get_ticks_msec() - t0

		var action: Dictionary
		if response.has("action_id"):
			var action_id = int(response.action_id)
			action = GraphExporter.id_to_action(action_id, agent_name, shadow_state)

			if show_debug:
				var confidence = response.get("confidence", 0.0)
				var ability = action.get("ability", "wait")
				var target = action.get("target", "")
				var action_str = ability + (" -> " + target if target else "")
				print("[%s] GAT: %s (conf: %.1f%%)" % [
					agent_name.to_upper(), action_str, confidence * 100
				])
		else:
			action = {"agent": agent_name, "ability": "wait"}
			if show_debug:
				print("[%s] GAT ERROR: %s" % [agent_name.to_upper(), response.get("error", "unknown")])

		actions_to_execute.append(action)
		shadow_state = shadow_state.step(action)

	for action in actions_to_execute:
		execute_action(action)
		await get_tree().create_timer(0.3).timeout

	decisions_made += 1
	is_executing = false


func _send_request(request: Dictionary) -> Dictionary:
	## Send JSON request to inference server and read JSON response.
	if not is_connected:
		return {"error": "not connected"}

	tcp.poll()
	if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		is_connected = false
		return {"error": "disconnected"}

	# Send request as newline-delimited JSON
	var json_str = JSON.stringify(request) + "\n"
	var err = tcp.put_data(json_str.to_utf8_buffer())
	if err != OK:
		return {"error": "send failed: %d" % err}

	# Read response (wait up to 10 seconds)
	var response_buf = ""
	var waited = 0.0
	while waited < 10.0:
		tcp.poll()
		var available = tcp.get_available_bytes()
		if available > 0:
			var result = tcp.get_data(available)
			if result[0] == OK:
				response_buf += result[1].get_string_from_utf8()
				if "\n" in response_buf:
					break
		OS.delay_msec(1)
		waited += 0.001

	if response_buf.is_empty():
		return {"error": "timeout"}

	var line = response_buf.split("\n")[0].strip_edges()
	var json = JSON.new()
	if json.parse(line) != OK:
		return {"error": "parse failed"}

	return json.data


func _on_game_over():
	var victory = check_victory()

	print_game_over_stats(victory)
	if decisions_made > 0:
		print("Avg inference time: %.0f ms" % (float(total_inference_time_ms) / float(decisions_made * 3)))


func _exit_tree():
	if tcp:
		tcp.disconnect_from_host()
