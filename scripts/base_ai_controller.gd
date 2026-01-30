extends Node
class_name BaseAIController

## Base class for AI controllers. Provides shared action execution,
## game-over detection, recording support, and setup logic.

# References
var mcts_bridge: Node = null
var tank: Node2D = null
var healer: Node2D = null
var sniper: Node2D = null
var boss: Node2D = null

# Statistics
var actions_taken: Dictionary = {}
var total_damage_dealt: int = 0
var start_time: int = 0
var decisions_made: int = 0


func setup_references() -> bool:
	## Finds game nodes and MCTSBridge. Returns false if bridge not found.
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
		return false

	start_time = Time.get_ticks_msec()
	return true


func execute_action(action: Dictionary):
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


func is_game_over() -> bool:
	if not boss or not is_instance_valid(boss) or boss.health <= 0:
		return true

	var any_alive = false
	for agent in [tank, healer, sniper]:
		if agent and is_instance_valid(agent) and agent.health > 0:
			any_alive = true
			break

	return not any_alive


func check_victory() -> bool:
	if not boss or not is_instance_valid(boss):
		return true
	if boss.health <= 0:
		return true
	return false


func print_game_over_stats(victory: bool):
	var elapsed = (Time.get_ticks_msec() - start_time) / 1000.0

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


func create_legal_mask(legal_actions: Array[Dictionary]) -> Array[int]:
	var mask: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	for action in legal_actions:
		var action_id = GraphExporter.action_to_id(action)
		mask[action_id] = 1
	return mask


func record_sample(state: ShadowState, action: Dictionary, agent_idx: int) -> void:
	## Create and record a training sample.
	var graph = GraphExporter.state_to_graph(state)
	var flat_features = GraphExporter.state_to_flat_features(state)
	var action_id = GraphExporter.action_to_id(action)
	var legal_actions = ActionGenerator.get_legal_actions(state)
	var legal_mask = create_legal_mask(legal_actions)

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
