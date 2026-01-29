extends Node

## GAT AI Controller - Uses a trained Graph Attention Network for agent decisions.
## Connects to a Python inference server over TCP (localhost).
##
## Start the server first:
##   python inference_server.py <checkpoint_dir> --port 5555

@export var enabled: bool = true
@export var decision_interval: float = 2.0
@export var show_debug: bool = true
@export var server_port: int = 5555

# References
var mcts_bridge: Node = null
var tank: Node2D = null
var healer: Node2D = null
var sniper: Node2D = null
var boss: Node2D = null

# Networking
var tcp: StreamPeerTCP = null
var is_connected: bool = false

# State
var time_since_last_decision: float = 0.0
var decisions_made: int = 0
var is_executing: bool = false

# Statistics
var actions_taken: Dictionary = {}
var total_damage_dealt: int = 0
var start_time: int = 0
var total_inference_time_ms: int = 0


func _ready():
	if not enabled:
		return

	await get_tree().process_frame

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
	start_time = Time.get_ticks_msec()


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
		var legal_mask = _create_legal_mask(legal_actions)

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
		_execute_action(action)
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


func _create_legal_mask(legal_actions: Array[Dictionary]) -> Array[int]:
	var mask: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	for action in legal_actions:
		var action_id = GraphExporter.action_to_id(action)
		mask[action_id] = 1
	return mask


func _execute_action(action: Dictionary):
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


func _is_game_over() -> bool:
	if not boss or not is_instance_valid(boss) or boss.health <= 0:
		return true

	var any_alive = false
	for agent_node in [tank, healer, sniper]:
		if agent_node and is_instance_valid(agent_node) and agent_node.health > 0:
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

	print("\n" + "=".repeat(50))
	print("GAME OVER - ", "VICTORY!" if victory else "DEFEAT")
	print("=".repeat(50))
	print("Time: %.1f seconds" % elapsed)
	print("Decisions made: ", decisions_made)
	print("Total damage dealt: ", total_damage_dealt)
	if decisions_made > 0:
		print("Avg inference time: %.0f ms" % (float(total_inference_time_ms) / float(decisions_made * 3)))
	if boss and is_instance_valid(boss):
		print("Boss HP remaining: ", boss.health, "/650")
	print("\nAction breakdown:")
	for action_name in actions_taken:
		print("  %s: %d" % [action_name, actions_taken[action_name]])
	print("=".repeat(50))
	print("Press R to restart")
	print("=".repeat(50) + "\n")


func _exit_tree():
	if tcp:
		tcp.disconnect_from_host()
