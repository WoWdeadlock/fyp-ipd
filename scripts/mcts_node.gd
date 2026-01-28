class_name MCTSNode
extends RefCounted

## MCTS tree node with UCB1 selection.
## Each node represents a game state after taking an action.

var state: ShadowState
var parent: MCTSNode = null
var children: Array[MCTSNode] = []
var action: Dictionary = {}  # Action that led to this node from parent

# Statistics for UCB1
var visit_count: int = 0
var total_reward: float = 0.0

# Unexpanded actions
var untried_actions: Array[Dictionary] = []

# UCB1 exploration constant (sqrt(2) is theoretically optimal)
const EXPLORATION_CONSTANT: float = 1.414


func _init(p_state: ShadowState, p_parent: MCTSNode = null, p_action: Dictionary = {}):
	state = p_state
	parent = p_parent
	action = p_action

	# Initialize untried actions if not terminal
	if not state.is_terminal():
		untried_actions = ActionGenerator.get_legal_actions(state)


func is_fully_expanded() -> bool:
	## Returns true if all legal actions have been tried.
	return untried_actions.is_empty()


func is_terminal() -> bool:
	## Returns true if this node represents a terminal game state.
	return state.is_terminal()


func is_leaf() -> bool:
	## Returns true if this node has no children.
	return children.is_empty()


func ucb1_score() -> float:
	## Calculate UCB1 score for node selection.
	## Higher score = more promising or under-explored.
	if visit_count == 0:
		return INF  # Always try unvisited nodes first

	if parent == null or parent.visit_count == 0:
		return total_reward / float(visit_count)

	var exploitation = total_reward / float(visit_count)
	var exploration = EXPLORATION_CONSTANT * sqrt(log(float(parent.visit_count)) / float(visit_count))

	return exploitation + exploration


func best_child() -> MCTSNode:
	## Select the child with the highest UCB1 score.
	## Used during the selection phase.
	var best: MCTSNode = null
	var best_score: float = -INF

	for child in children:
		var score = child.ucb1_score()
		if score > best_score:
			best_score = score
			best = child

	return best


func most_visited_child() -> MCTSNode:
	## Select the child with the most visits.
	## Used for final action selection (most robust).
	var best: MCTSNode = null
	var best_visits: int = -1

	for child in children:
		if child.visit_count > best_visits:
			best_visits = child.visit_count
			best = child

	return best


func highest_value_child() -> MCTSNode:
	## Select the child with the highest average reward.
	## Alternative to most_visited for final selection.
	var best: MCTSNode = null
	var best_value: float = -INF

	for child in children:
		if child.visit_count > 0:
			var avg_value = child.total_reward / float(child.visit_count)
			if avg_value > best_value:
				best_value = avg_value
				best = child

	return best


func expand() -> MCTSNode:
	## Expand the node by trying one untried action.
	## Returns the new child node.
	if untried_actions.is_empty():
		return null

	# Pop an action (could be randomized for better exploration)
	var action_to_try = untried_actions.pop_back()

	# Create new state by applying action
	var new_state = state.step(action_to_try)

	# Create child node
	var child_node = MCTSNode.new(new_state, self, action_to_try)
	children.append(child_node)

	return child_node


func expand_with_action(action_to_try: Dictionary) -> MCTSNode:
	## Expand with a specific action (for ordered expansion).
	# Remove from untried if present
	for i in range(untried_actions.size()):
		if _actions_equal(untried_actions[i], action_to_try):
			untried_actions.remove_at(i)
			break

	var new_state = state.step(action_to_try)
	var child_node = MCTSNode.new(new_state, self, action_to_try)
	children.append(child_node)

	return child_node


func get_child_for_action(action_to_find: Dictionary) -> MCTSNode:
	## Find an existing child that matches the given action.
	for child in children:
		if _actions_equal(child.action, action_to_find):
			return child
	return null


func _actions_equal(a: Dictionary, b: Dictionary) -> bool:
	## Compare two action dictionaries.
	if a.get("agent") != b.get("agent"):
		return false
	if a.get("ability") != b.get("ability"):
		return false
	if a.get("target", "") != b.get("target", ""):
		return false
	return true


func update(reward: float) -> void:
	## Update this node's statistics with a simulation result.
	visit_count += 1
	total_reward += reward


func get_average_reward() -> float:
	## Get the average reward for this node.
	if visit_count == 0:
		return 0.0
	return total_reward / float(visit_count)


func get_depth() -> int:
	## Get the depth of this node in the tree.
	var depth = 0
	var node = self
	while node.parent != null:
		depth += 1
		node = node.parent
	return depth


func to_string_recursive(max_depth: int = 3, indent: String = "") -> String:
	## Debug string representation of the tree.
	var s = indent + "Node: visits=%d, avg=%.2f, action=%s\n" % [
		visit_count,
		get_average_reward(),
		str(action)
	]

	if max_depth > 0:
		for child in children:
			s += child.to_string_recursive(max_depth - 1, indent + "  ")

	return s
