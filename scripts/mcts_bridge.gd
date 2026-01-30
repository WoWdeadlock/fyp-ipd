extends Node

const COMMAND_FILE = "user://mcts_command.json"
const STATE_FILE = "user://mcts_state.json"
const RESET_FLAG_FILE = "user://mcts_reset_flag.json"
const MCTS_RESULT_FILE = "user://mcts_result.json"
const LEGAL_ACTIONS_FILE = "user://legal_actions.json"

const VALID_AGENTS: Array[String] = ["tank", "healer", "sniper"]
const VALID_ABILITIES: Dictionary = {
	"tank": ["melee", "taunt", "defensive"],
	"healer": ["heal", "shield", "restore"],
	"sniper": ["shot", "cripple", "power"],
}

# Shadow simulation state for MCTS
var last_mcts_search: MCTSSearch = null

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
		if not file:
			return
		var json_str = file.get_as_text()
		file.close()

		if json_str.is_empty():
			return  # File still being written

		var json = JSON.new()
		var parse_result = json.parse(json_str)
		if parse_result != OK:
			print("JSON parse error: ", json.get_error_message())
			# Don't delete — may be a partial write; retry next frame
			return

		var command = json.data
		if command is Dictionary:
			DirAccess.remove_absolute(COMMAND_FILE)
			_handle_command(command)
		else:
			print("JSON command is not a Dictionary, ignoring")
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
		"pause_boss":
			_pause_boss()
			_write_state()
		"unpause_boss":
			_unpause_boss()
			_write_state()
		"mcts_search":
			var iterations = cmd.get("iterations", 1000)
			var seed_value = cmd.get("seed", -1)
			var result = run_mcts_search(iterations, seed_value)
			_write_mcts_result(result)
		"get_legal_actions":
			var shadow_state = create_shadow_state()
			var legal = ActionGenerator.get_legal_actions(shadow_state)
			_write_legal_actions(legal)
		"get_shadow_state":
			var shadow_state = create_shadow_state()
			_write_shadow_state(shadow_state)

func get_state() -> Dictionary:
	var tank = get_tree().get_first_node_in_group("tank")
	var healer = get_tree().get_first_node_in_group("healer")
	var sniper = get_tree().get_first_node_in_group("sniper")
	var boss = get_tree().get_first_node_in_group("boss")

	var state = {
		"tank": _serialize_tank(tank),
		"healer": _serialize_char(healer),
		"sniper": _serialize_char(sniper),
		"boss": _serialize_boss(boss),
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

func _serialize_tank(tank: Node2D) -> Dictionary:
	if not tank or not is_instance_valid(tank):
		return {"pos": [0.0, 0.0], "hp": 0, "stamina": 0, "has_shield": false, "defensive_active": false}
	return {
		"pos": [tank.global_position.x, tank.global_position.y],
		"hp": tank.health,
		"stamina": tank.stamina,
		"has_shield": tank.has_shield if "has_shield" in tank else false,
		"defensive_active": tank.defensive_stance_active if "defensive_stance_active" in tank else false
	}

func _serialize_boss(boss: Node2D) -> Dictionary:
	if not boss or not is_instance_valid(boss):
		return {"pos": [0.0, 0.0], "hp": 0, "stamina": 0, "current_target_name": "", "is_slowed": false}

	# Get boss current target name
	var target_name = ""
	if "current_target" in boss and boss.current_target and is_instance_valid(boss.current_target):
		var target = boss.current_target
		if target.is_in_group("tank"):
			target_name = "tank"
		elif target.is_in_group("healer"):
			target_name = "healer"
		elif target.is_in_group("sniper"):
			target_name = "sniper"

	return {
		"pos": [boss.global_position.x, boss.global_position.y],
		"hp": boss.health,
		"stamina": boss.stamina,
		"current_target_name": target_name,
		"is_slowed": boss.is_slowed if "is_slowed" in boss else false
	}

func _check_terminal() -> bool:
	var boss_alive = _is_alive("boss")
	var any_agent_alive = _is_alive("tank") or _is_alive("healer") or _is_alive("sniper")

	# Check for unwinnable solo states
	# Only healer alive is unwinnable (healer has no damage abilities)
	# Tank and Sniper CAN win solo now that melee/shot are FREE
	var only_healer_alive = _is_alive("healer") and not _is_alive("tank") and not _is_alive("sniper")

	return not boss_alive or not any_agent_alive or only_healer_alive

func _get_outcome() -> String:
	if not _is_alive("boss"):
		return "victory"
	if not (_is_alive("tank") or _is_alive("healer") or _is_alive("sniper")):
		return "defeat"
	# Check for unwinnable solo states
	# Only healer alive is unwinnable (healer has no damage abilities)
	# Tank and Sniper CAN win solo now that melee/shot are FREE
	if _is_alive("healer") and not _is_alive("tank") and not _is_alive("sniper"):
		return "defeat"
	return ""

func _is_alive(group_name: String) -> bool:
	var char = get_tree().get_first_node_in_group(group_name)
	return char != null and is_instance_valid(char) and char.health > 0

func _atomic_write(path: String, content: String) -> bool:
	## Write to a temp file then rename for atomicity.
	var tmp_path = path + ".tmp"
	var file = FileAccess.open(tmp_path, FileAccess.WRITE)
	if not file:
		print("Error: Could not open temp file for writing: ", tmp_path)
		return false
	file.store_string(content)
	file.close()
	# Rename tmp to target (atomic on most filesystems)
	var dir = DirAccess.open("user://")
	if dir:
		var from_name = tmp_path.get_file()
		var to_name = path.get_file()
		dir.rename(from_name, to_name)
	return true

func _write_state():
	var state = get_state()
	_atomic_write(STATE_FILE, JSON.stringify(state))

func execute_action(action: Dictionary) -> bool:
	var agent_name = action.get("agent", "")
	var ability = action.get("ability", "")
	var target_name = action.get("target", "")

	# Validate agent name
	if agent_name not in VALID_AGENTS:
		print("Error: Invalid agent name '", agent_name, "'")
		return false

	# Validate ability for agent
	if ability not in VALID_ABILITIES.get(agent_name, []):
		print("Error: Invalid ability '", ability, "' for agent '", agent_name, "'")
		return false

	var agent = get_tree().get_first_node_in_group(agent_name)
	if not agent or not is_instance_valid(agent):
		print("Error: Agent '", agent_name, "' not found")
		return false

	if agent.health <= 0:
		print("Error: Agent '", agent_name, "' is dead (HP: ", agent.health, ")")
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

func _pause_boss():
	# Pause boss AI during MCTS search
	var boss = get_tree().get_first_node_in_group("boss")
	if boss:
		boss.set_process(false)
		boss.set_physics_process(false)
		print("Boss paused for MCTS search")

func _unpause_boss():
	# Unpause boss AI after MCTS search
	var boss = get_tree().get_first_node_in_group("boss")
	if boss:
		boss.set_process(true)
		boss.set_physics_process(true)
		print("Boss unpaused")


# ============================================================================
# SHADOW SIMULATION INTEGRATION
# ============================================================================

func create_shadow_state() -> ShadowState:
	## Convert current real game state to a shadow state for MCTS.
	var shadow = ShadowState.new()

	var tank = get_tree().get_first_node_in_group("tank")
	var healer = get_tree().get_first_node_in_group("healer")
	var sniper = get_tree().get_first_node_in_group("sniper")
	var boss_node = get_tree().get_first_node_in_group("boss")

	# Create shadow agents
	shadow.agents.append(_create_shadow_tank(tank))
	shadow.agents.append(_create_shadow_healer(healer))
	shadow.agents.append(_create_shadow_sniper(sniper))
	shadow.boss = _create_shadow_boss(boss_node)

	return shadow


func _create_shadow_tank(tank: Node2D) -> ShadowAgent:
	var shadow = ShadowAgent.create_tank()

	if tank and is_instance_valid(tank) and tank.health > 0:
		shadow.hp = tank.health
		shadow.stamina = tank.stamina

		# Check for defensive stance
		if "defensive_stance_active" in tank and tank.defensive_stance_active:
			if "defensive_stance_timer" in tank:
				shadow.defensive_stance_ticks = int(tank.defensive_stance_timer * 2.0)
			else:
				shadow.defensive_stance_ticks = 14  # Default 7 seconds

		# Check for shield
		if "has_shield" in tank and tank.has_shield:
			if "shield_timer" in tank:
				shadow.shield_ticks = int(tank.shield_timer * 2.0)
			else:
				shadow.shield_ticks = 12  # Default 6 seconds
	else:
		shadow.hp = 0

	return shadow


func _create_shadow_healer(healer: Node2D) -> ShadowAgent:
	var shadow = ShadowAgent.create_healer()

	if healer and is_instance_valid(healer) and healer.health > 0:
		shadow.hp = healer.health
		shadow.stamina = healer.stamina
	else:
		shadow.hp = 0

	return shadow


func _create_shadow_sniper(sniper: Node2D) -> ShadowAgent:
	var shadow = ShadowAgent.create_sniper()

	if sniper and is_instance_valid(sniper) and sniper.health > 0:
		shadow.hp = sniper.health
		shadow.stamina = sniper.stamina

		# Check for shield
		if "has_shield" in sniper and sniper.has_shield:
			if "shield_timer" in sniper:
				shadow.shield_ticks = int(sniper.shield_timer * 2.0)
			else:
				shadow.shield_ticks = 12  # Default 6 seconds
	else:
		shadow.hp = 0

	return shadow


func _create_shadow_boss(boss_node: Node2D) -> ShadowBoss:
	var shadow = ShadowBoss.create()

	if boss_node and is_instance_valid(boss_node) and boss_node.health > 0:
		shadow.hp = boss_node.health
		shadow.stamina = boss_node.stamina

		# Check for slow effect
		if "is_slowed" in boss_node and boss_node.is_slowed:
			shadow.is_slowed = true
			if "slow_timer" in boss_node:
				shadow.slow_ticks = int(boss_node.slow_timer * 2.0)
			else:
				shadow.slow_ticks = 16  # Default 8 seconds

		# Check for taunt/forced target
		if "forced_target" in boss_node and boss_node.forced_target:
			shadow.is_taunted = true
			if "forced_target_timer" in boss_node:
				shadow.taunt_ticks = int(boss_node.forced_target_timer * 2.0)
			else:
				shadow.taunt_ticks = 10  # Default 5 seconds

			# Determine which agent is the taunt target
			var target = boss_node.forced_target
			if target.is_in_group("tank"):
				shadow.taunt_target = 0
			elif target.is_in_group("healer"):
				shadow.taunt_target = 1
			elif target.is_in_group("sniper"):
				shadow.taunt_target = 2
	else:
		shadow.hp = 0

	return shadow


func run_mcts_search(iterations: int = 1000, deterministic_seed: int = -1) -> Dictionary:
	## Run MCTS search on shadow state and return the best action with stats.
	var shadow_state = create_shadow_state()

	# Set deterministic seed if provided
	if deterministic_seed >= 0:
		shadow_state.set_deterministic_seed(deterministic_seed)

	# Create and run search
	last_mcts_search = MCTSSearch.new(shadow_state, iterations)

	if deterministic_seed >= 0:
		last_mcts_search.set_seed(deterministic_seed)

	var result = last_mcts_search.search_with_stats()

	print("MCTS Search complete: ", result.root_visits, " visits, best action: ", result.best_action)

	return result


func _write_mcts_result(result: Dictionary):
	_atomic_write(MCTS_RESULT_FILE, JSON.stringify(result))


func _write_legal_actions(actions: Array):
	_atomic_write(LEGAL_ACTIONS_FILE, JSON.stringify({"actions": actions}))


func _write_shadow_state(shadow_state: ShadowState):
	_atomic_write(STATE_FILE, JSON.stringify(shadow_state.to_dict()))
