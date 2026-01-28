class_name GraphExporter
extends RefCounted

## Converts ShadowState to graph format for Graph Attention Networks.
##
## Graph Structure:
##   Nodes: [Tank, Healer, Sniper, Boss] (indices 0, 1, 2, 3)
##   Node Features: HP ratio, stamina ratio, buffs, debuffs, role encoding
##   Edges: Relationships between entities (targeting, support links)
##   Edge Features: Edge type encoding

# Node indices
const NODE_TANK: int = 0
const NODE_HEALER: int = 1
const NODE_SNIPER: int = 2
const NODE_BOSS: int = 3
const NUM_NODES: int = 4

# Edge types
const EDGE_BOSS_TARGETING: int = 0    # Boss -> Target
const EDGE_CAN_HEAL: int = 1          # Healer -> Ally
const EDGE_CAN_SHIELD: int = 2        # Healer -> Ally
const EDGE_CAN_ATTACK: int = 3        # Agent -> Boss
const EDGE_TAUNT_ACTIVE: int = 4      # Tank -> Boss (forced targeting)

# Action encoding (for labels)
const ACTION_TO_ID: Dictionary = {
	"wait": 0,
	"melee": 1,
	"taunt": 2,
	"defensive": 3,
	"heal": 4,
	"shield": 5,
	"restore": 6,
	"shot": 7,
	"cripple": 8,
	"power": 9
}

const ID_TO_ACTION: Array[String] = [
	"wait", "melee", "taunt", "defensive",
	"heal", "shield", "restore",
	"shot", "cripple", "power"
]

const NUM_ACTIONS: int = 10


static func state_to_graph(state: ShadowState) -> Dictionary:
	## Convert a ShadowState to a graph dictionary.
	## Returns: {node_features, edge_index, edge_attr, ...}

	var node_features = _extract_node_features(state)
	var edge_data = _extract_edges(state)

	return {
		"node_features": node_features,      # [4, num_features] - 4 nodes
		"edge_index": edge_data.edge_index,  # [2, num_edges] - COO format
		"edge_attr": edge_data.edge_attr,    # [num_edges, edge_features]
		"num_nodes": NUM_NODES,
		"num_edges": edge_data.edge_index[0].size()
	}


static func state_to_flat_features(state: ShadowState) -> Array[float]:
	## Convert state to a flat feature vector (alternative to graph).
	## Useful for simpler models or debugging.

	var features: Array[float] = []

	# Tank features (8 features)
	var tank = state.agents[0]
	features.append(float(tank.hp) / float(tank.max_hp))
	features.append(tank.stamina / float(tank.max_stamina))
	features.append(1.0 if tank.is_alive() else 0.0)
	features.append(1.0 if tank.defensive_stance_ticks > 0 else 0.0)
	features.append(1.0 if tank.shield_ticks > 0 else 0.0)
	features.append(float(tank.defensive_stance_ticks) / 14.0)  # Normalized
	features.append(float(tank.shield_ticks) / 12.0)
	features.append(1.0)  # Is tank (role encoding)

	# Healer features (6 features)
	var healer = state.agents[1]
	features.append(float(healer.hp) / float(healer.max_hp))
	features.append(healer.stamina / float(healer.max_stamina))
	features.append(1.0 if healer.is_alive() else 0.0)
	features.append(0.0)  # No defensive stance
	features.append(0.0)  # No shield (healer doesn't get shielded typically)
	features.append(1.0)  # Is healer

	# Sniper features (7 features)
	var sniper = state.agents[2]
	features.append(float(sniper.hp) / float(sniper.max_hp))
	features.append(sniper.stamina / float(sniper.max_stamina))
	features.append(1.0 if sniper.is_alive() else 0.0)
	features.append(1.0 if sniper.shield_ticks > 0 else 0.0)
	features.append(float(sniper.shield_ticks) / 12.0)
	features.append(0.0)  # No defensive
	features.append(1.0)  # Is sniper

	# Boss features (8 features)
	var boss = state.boss
	features.append(float(boss.hp) / float(boss.max_hp))
	features.append(boss.stamina / float(boss.max_stamina))
	features.append(1.0 if boss.is_alive() else 0.0)
	features.append(1.0 if boss.is_slowed else 0.0)
	features.append(1.0 if boss.is_taunted else 0.0)
	features.append(float(boss.slow_ticks) / 16.0)
	features.append(float(boss.taunt_ticks) / 10.0)
	features.append(float(boss.taunt_target) / 2.0 if boss.taunt_target >= 0 else -1.0)

	# Global features (3 features)
	features.append(float(state.current_tick) / 100.0)  # Normalized tick
	features.append(float(state.micro_turn_index) / 2.0)  # Current agent turn
	features.append(1.0 if state.is_terminal() else 0.0)

	return features


static func _extract_node_features(state: ShadowState) -> Array[Array]:
	## Extract feature vectors for each node.
	## Returns array of [num_nodes][num_features]

	var features: Array[Array] = []

	# Tank node (index 0)
	var tank = state.agents[0]
	features.append([
		float(tank.hp) / float(tank.max_hp),           # HP ratio
		tank.stamina / float(tank.max_stamina),        # Stamina ratio
		1.0 if tank.is_alive() else 0.0,               # Alive
		1.0 if tank.defensive_stance_ticks > 0 else 0.0,  # Has defensive
		1.0 if tank.shield_ticks > 0 else 0.0,         # Has shield
		float(tank.defensive_stance_ticks) / 14.0,     # Defensive remaining
		float(tank.shield_ticks) / 12.0,               # Shield remaining
		1.0, 0.0, 0.0, 0.0                             # One-hot: Tank
	])

	# Healer node (index 1)
	var healer = state.agents[1]
	features.append([
		float(healer.hp) / float(healer.max_hp),
		healer.stamina / float(healer.max_stamina),
		1.0 if healer.is_alive() else 0.0,
		0.0,  # No defensive stance
		0.0,  # No shield
		0.0,
		0.0,
		0.0, 1.0, 0.0, 0.0                             # One-hot: Healer
	])

	# Sniper node (index 2)
	var sniper = state.agents[2]
	features.append([
		float(sniper.hp) / float(sniper.max_hp),
		sniper.stamina / float(sniper.max_stamina),
		1.0 if sniper.is_alive() else 0.0,
		0.0,  # No defensive
		1.0 if sniper.shield_ticks > 0 else 0.0,
		0.0,
		float(sniper.shield_ticks) / 12.0,
		0.0, 0.0, 1.0, 0.0                             # One-hot: Sniper
	])

	# Boss node (index 3)
	var boss = state.boss
	features.append([
		float(boss.hp) / float(boss.max_hp),
		boss.stamina / float(boss.max_stamina),
		1.0 if boss.is_alive() else 0.0,
		1.0 if boss.is_slowed else 0.0,
		1.0 if boss.is_taunted else 0.0,
		float(boss.slow_ticks) / 16.0,
		float(boss.taunt_ticks) / 10.0,
		0.0, 0.0, 0.0, 1.0                             # One-hot: Boss
	])

	return features


static func _extract_edges(state: ShadowState) -> Dictionary:
	## Extract edge list and edge features.
	## Returns: {edge_index: [[src], [dst]], edge_attr: [[features]]}

	var src_nodes: Array[int] = []
	var dst_nodes: Array[int] = []
	var edge_attrs: Array[Array] = []

	var boss = state.boss
	var tank = state.agents[0]
	var healer = state.agents[1]
	var sniper = state.agents[2]

	# Boss targeting edges
	if boss.is_alive():
		var target_idx = boss.taunt_target if boss.is_taunted else -1

		# If taunted, add strong edge to taunt target
		if boss.is_taunted and target_idx >= 0:
			src_nodes.append(NODE_BOSS)
			dst_nodes.append(target_idx)
			edge_attrs.append(_make_edge_attr(EDGE_TAUNT_ACTIVE, 1.0))

		# Add potential targeting edges to all alive agents
		for i in range(3):
			if state.agents[i].is_alive():
				src_nodes.append(NODE_BOSS)
				dst_nodes.append(i)
				var weight = 1.0 if (target_idx == i or target_idx < 0) else 0.3
				edge_attrs.append(_make_edge_attr(EDGE_BOSS_TARGETING, weight))

	# Healer support edges
	if healer.is_alive():
		# Can heal tank
		if tank.is_alive():
			src_nodes.append(NODE_HEALER)
			dst_nodes.append(NODE_TANK)
			var need = 1.0 - (float(tank.hp) / float(tank.max_hp))
			edge_attrs.append(_make_edge_attr(EDGE_CAN_HEAL, need))

			# Can shield tank
			if tank.shield_ticks <= 0:
				src_nodes.append(NODE_HEALER)
				dst_nodes.append(NODE_TANK)
				edge_attrs.append(_make_edge_attr(EDGE_CAN_SHIELD, 1.0))

		# Can heal sniper
		if sniper.is_alive():
			src_nodes.append(NODE_HEALER)
			dst_nodes.append(NODE_SNIPER)
			var need = 1.0 - (float(sniper.hp) / float(sniper.max_hp))
			edge_attrs.append(_make_edge_attr(EDGE_CAN_HEAL, need))

			# Can shield sniper
			if sniper.shield_ticks <= 0:
				src_nodes.append(NODE_HEALER)
				dst_nodes.append(NODE_SNIPER)
				edge_attrs.append(_make_edge_attr(EDGE_CAN_SHIELD, 1.0))

	# Attack edges (agents -> boss)
	if boss.is_alive():
		if tank.is_alive():
			src_nodes.append(NODE_TANK)
			dst_nodes.append(NODE_BOSS)
			edge_attrs.append(_make_edge_attr(EDGE_CAN_ATTACK, 1.0))

		if sniper.is_alive():
			src_nodes.append(NODE_SNIPER)
			dst_nodes.append(NODE_BOSS)
			edge_attrs.append(_make_edge_attr(EDGE_CAN_ATTACK, 1.0))

	return {
		"edge_index": [src_nodes, dst_nodes],
		"edge_attr": edge_attrs
	}


static func _make_edge_attr(edge_type: int, weight: float) -> Array:
	## Create edge feature vector.
	## One-hot edge type + weight
	var attr: Array = [0.0, 0.0, 0.0, 0.0, 0.0, weight]
	attr[edge_type] = 1.0
	return attr


static func action_to_id(action: Dictionary) -> int:
	## Convert action dictionary to integer ID.
	var ability = action.get("ability", "wait")
	return ACTION_TO_ID.get(ability, 0)


static func id_to_action(action_id: int, agent_name: String, state: ShadowState = null) -> Dictionary:
	## Convert action ID back to action dictionary.
	var ability = ID_TO_ACTION[action_id] if action_id < ID_TO_ACTION.size() else "wait"
	var action = {"agent": agent_name, "ability": ability}

	# Add target for healer abilities
	if agent_name == "healer" and ability in ["heal", "shield", "restore"]:
		# Default target selection (could be smarter)
		if state:
			var tank = state.agents[0]
			var sniper = state.agents[2]
			# Prioritize lower HP target for heals
			if ability == "heal":
				if tank.is_alive() and sniper.is_alive():
					action["target"] = "tank" if tank.hp < sniper.hp else "sniper"
				elif tank.is_alive():
					action["target"] = "tank"
				else:
					action["target"] = "sniper"
			else:
				action["target"] = "tank"  # Default to tank for shield/restore
		else:
			action["target"] = "tank"

	return action


static func get_agent_action_mask(agent_idx: int) -> Array[int]:
	## Get valid action IDs for an agent type.
	match agent_idx:
		0:  # Tank
			return [0, 1, 2, 3]  # wait, melee, taunt, defensive
		1:  # Healer
			return [0, 4, 5, 6]  # wait, heal, shield, restore
		2:  # Sniper
			return [0, 7, 8, 9]  # wait, shot, cripple, power
	return [0]
