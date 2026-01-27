extends Node

const COMMAND_FILE = "user://mcts_command.json"
const STATE_FILE = "user://mcts_state.json"
const RESET_FLAG_FILE = "user://mcts_reset_flag.json"

func _ready():
	print("MCTS Bridge initialized")
	print("Command file: ", COMMAND_FILE)
	print("State file: ", STATE_FILE)
	print("Godot user directory: ", OS.get_user_data_dir())

	# Check if we just finished a reset
	if FileAccess.file_exists(RESET_FLAG_FILE):
		print("Reset detected, writing initial state...")
		DirAccess.remove_absolute(RESET_FLAG_FILE)
		# Wait one frame for scene to fully initialize
		await get_tree().process_frame
		_write_state()

func _process(_delta):
	# Check for command from Python
	if FileAccess.file_exists(COMMAND_FILE):
		var file = FileAccess.open(COMMAND_FILE, FileAccess.READ)
		if file:
			var json_str = file.get_as_text()
			file.close()

			var json = JSON.new()
			var parse_result = json.parse(json_str)
			if parse_result == OK:
				var command = json.data
				_handle_command(command)
			else:
				print("JSON parse error: ", json.get_error_message())

			# Delete command file after processing
			DirAccess.remove_absolute(COMMAND_FILE)

func _handle_command(cmd: Dictionary):
	match cmd.get("type", ""):
		"get_state":
			_write_state()
		"execute_action":
			execute_action(cmd.get("action", {}))
			_write_state()  # Send updated state back
		"reset":
			# Write flag file so _ready() knows to write state after reload
			var flag_file = FileAccess.open(RESET_FLAG_FILE, FileAccess.WRITE)
			if flag_file:
				flag_file.store_string("{}")
				flag_file.close()
			get_tree().reload_current_scene()

func get_state() -> Dictionary:
	var tank = get_tree().get_first_node_in_group("tank")
	var healer = get_tree().get_first_node_in_group("healer")
	var sniper = get_tree().get_first_node_in_group("sniper")
	var boss = get_tree().get_first_node_in_group("boss")

	var state = {
		"tank": _serialize_char(tank),
		"healer": _serialize_char(healer),
		"sniper": _serialize_char(sniper),
		"boss": _serialize_char(boss),
		"is_terminal": _check_terminal(),
		"outcome": _get_outcome()
	}
	return state

func _serialize_char(char: Node2D) -> Dictionary:
	if not char or not is_instance_valid(char):
		return {"pos": [0.0, 0.0], "hp": 0, "stamina": 0}
	return {
		"pos": [char.global_position.x, char.global_position.y],
		"hp": char.health,
		"stamina": char.stamina
	}

func _check_terminal() -> bool:
	var boss_alive = _is_alive("boss")
	var any_agent_alive = _is_alive("tank") or _is_alive("healer") or _is_alive("sniper")
	return not boss_alive or not any_agent_alive

func _get_outcome() -> String:
	if not _is_alive("boss"):
		return "victory"
	if not (_is_alive("tank") or _is_alive("healer") or _is_alive("sniper")):
		return "defeat"
	return ""

func _is_alive(group_name: String) -> bool:
	var char = get_tree().get_first_node_in_group(group_name)
	return char != null and is_instance_valid(char) and char.health > 0

func _write_state():
	var state = get_state()
	var file = FileAccess.open(STATE_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(state))
		file.close()
	else:
		print("Error: Could not write state file")

func execute_action(action: Dictionary) -> bool:
	var agent_name = action.get("agent", "")
	var ability = action.get("ability", "")
	var target_name = action.get("target", "")

	var agent = get_tree().get_first_node_in_group(agent_name)
	if not agent or not is_instance_valid(agent):
		print("Error: Agent '", agent_name, "' not found")
		return false

	# Execute ability based on agent type
	match [agent_name, ability]:
		["tank", "melee"]:
			if agent.has_method("attempt_melee_attack"):
				agent.attempt_melee_attack()
		["tank", "taunt"]:
			if agent.has_method("taunt_boss"):
				agent.taunt_boss()
		["tank", "defensive"]:
			if agent.has_method("activate_defensive_stance"):
				agent.activate_defensive_stance()
		["healer", "heal"]:
			if agent.has_method("heal_target"):
				agent.heal_target(target_name)
		["healer", "shield"]:
			if agent.has_method("shield_buff"):
				agent.shield_buff(target_name)
		["healer", "restore"]:
			if agent.has_method("restore_stamina"):
				agent.restore_stamina(target_name)
		["sniper", "shot"]:
			if agent.has_method("attempt_sniper_shot"):
				agent.attempt_sniper_shot()
		["sniper", "cripple"]:
			if agent.has_method("use_crippling_shot"):
				agent.use_crippling_shot()
		["sniper", "power"]:
			if agent.has_method("use_power_shot"):
				agent.use_power_shot()
		_:
			print("Unknown action: ", agent_name, ".", ability)
			return false

	return true
