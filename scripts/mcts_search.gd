class_name MCTSSearch
extends RefCounted

## Monte Carlo Tree Search implementation.
## Uses UCB1 for selection and random rollouts for simulation.

var root: MCTSNode
var max_iterations: int
var max_rollout_depth: int

# Statistics
var total_simulations: int = 0
var total_nodes_created: int = 0

# RNG for rollouts (can be seeded for reproducibility)
var rng: RandomNumberGenerator = null
var use_seeded_rng: bool = false

func _init(initial_state: ShadowState, iterations: int = MCTSConfig.ITERATIONS, rollout_depth: int = MCTSConfig.ROLLOUT_DEPTH):
	root = MCTSNode.new(initial_state)
	max_iterations = iterations
	max_rollout_depth = rollout_depth
	total_nodes_created = 1


func set_seed(seed_value: int) -> void:
	## Set a seed for reproducible rollouts.
	use_seeded_rng = true
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value


func search() -> Dictionary:
	## Run MCTS and return the best action.
	for i in range(max_iterations):
		_run_iteration()

	# Return best action from root
	var best_child = root.most_visited_child()
	if best_child:
		return best_child.action
	else:
		# Fallback to wait if no children (shouldn't happen)
		return {"agent": root.state.get_current_agent_name(), "ability": "wait"}


func search_with_stats() -> Dictionary:
	## Run MCTS and return results with statistics.
	var best_action = search()

	return {
		"best_action": best_action,
		"root_visits": root.visit_count,
		"total_simulations": total_simulations,
		"total_nodes": total_nodes_created,
		"children_stats": _get_children_stats()
	}


func _run_iteration() -> void:
	## Execute one MCTS iteration: Select -> Expand -> Simulate -> Backpropagate
	total_simulations += 1

	# 1. Selection: Navigate to a leaf node
	var node = _select(root)

	# 2. Expansion: Add a new child if not terminal and not fully expanded
	if not node.is_terminal() and not node.is_fully_expanded():
		node = node.expand()
		if node:
			total_nodes_created += 1

	# 3. Simulation: Random rollout (unbiased signal for UCB1)
	var reward = _simulate(node)

	# 4. Backpropagation: Update statistics up the tree
	_backpropagate(node, reward)


func _select(node: MCTSNode) -> MCTSNode:
	## Selection phase: Use UCB1 to navigate to a promising leaf.
	while not node.is_terminal():
		if not node.is_fully_expanded():
			# Node has untried actions - stop here to expand
			return node
		# All actions tried - select best child
		var best = node.best_child()
		if best == null:
			break
		node = best
	return node


func _simulate(node: MCTSNode) -> float:
	## Simulation phase: Random rollout to estimate state value.
	if node == null:
		return 0.0

	var state = node.state.clone()
	var depth = 0

	while not state.is_terminal() and depth < max_rollout_depth:
		var actions = ActionGenerator.get_legal_actions(state)
		if actions.is_empty():
			break

		# Random action selection
		var random_idx: int
		if use_seeded_rng and rng:
			random_idx = rng.randi() % actions.size()
		else:
			random_idx = randi() % actions.size()

		var random_action = actions[random_idx]
		state = state.step(random_action)
		depth += 1

	# Evaluate final state
	return RewardCalculator.evaluate_normalized(state)


func _simulate_with_heuristic(node: MCTSNode) -> float:
	## Alternative simulation using heuristic-guided rollouts.
	## Tends to find better solutions but slower per iteration.
	if node == null:
		return 0.0

	var state = node.state.clone()
	var depth = 0

	while not state.is_terminal() and depth < max_rollout_depth:
		var actions = ActionGenerator.get_legal_actions(state)
		if actions.is_empty():
			break

		# Weighted random selection based on action value estimates
		var best_action = actions[0]
		var best_value = -INF

		for action in actions:
			var value = RewardCalculator.get_action_value_estimate(state, action)
			# Add some randomness to avoid deterministic behavior
			var noise: float
			if use_seeded_rng and rng:
				noise = rng.randf() * 5.0
			else:
				noise = randf() * 5.0
			value += noise

			if value > best_value:
				best_value = value
				best_action = action

		state = state.step(best_action)
		depth += 1

	return RewardCalculator.evaluate_normalized(state)


func _backpropagate(node: MCTSNode, reward: float) -> void:
	## Backpropagation phase: Update all nodes from leaf to root.
	while node != null:
		node.update(reward)
		node = node.parent


func _get_children_stats() -> Array[Dictionary]:
	## Get statistics for root's children (for debugging/analysis).
	var stats: Array[Dictionary] = []

	for child in root.children:
		stats.append({
			"action": child.action,
			"visits": child.visit_count,
			"avg_reward": child.get_average_reward(),
			"ucb1": child.ucb1_score() if child.visit_count > 0 else INF
		})

	# Sort by visits (most visited first)
	stats.sort_custom(func(a, b): return a.visits > b.visits)

	return stats


func get_best_action_sequence(depth: int = 5) -> Array[Dictionary]:
	## Get the best sequence of actions by following most-visited children.
	var sequence: Array[Dictionary] = []
	var node = root

	for i in range(depth):
		var best = node.most_visited_child()
		if best == null:
			break
		sequence.append(best.action)
		node = best

	return sequence


func get_tree_stats() -> Dictionary:
	## Get overall tree statistics.
	return {
		"root_visits": root.visit_count,
		"total_nodes": total_nodes_created,
		"total_simulations": total_simulations,
		"iterations_per_node": float(total_simulations) / float(total_nodes_created) if total_nodes_created > 0 else 0.0,
		"branching_factor": float(root.children.size())
	}


func prune_tree(max_depth: int = 50) -> void:
	## Prune deep nodes to save memory.
	## Useful for very long searches.
	_prune_node(root, 0, max_depth)


func _prune_node(node: MCTSNode, depth: int, max_depth: int) -> void:
	if depth > max_depth:
		node.children.clear()
		return

	for child in node.children:
		_prune_node(child, depth + 1, max_depth)


func reuse_tree(action_taken: Dictionary) -> MCTSSearch:
	## Create a new search reusing the subtree for the taken action.
	## Useful for iterative deepening or real-time play.
	var child = root.get_child_for_action(action_taken)

	if child:
		# Detach from parent and reuse
		child.parent = null
		var new_search = MCTSSearch.new(child.state, max_iterations, max_rollout_depth)
		new_search.root = child
		new_search.total_nodes_created = _count_nodes(child)
		return new_search
	else:
		# Action not in tree, create fresh search
		var new_state = root.state.step(action_taken)
		return MCTSSearch.new(new_state, max_iterations, max_rollout_depth)


func _count_nodes(node: MCTSNode) -> int:
	var count = 1
	for child in node.children:
		count += _count_nodes(child)
	return count
