class_name MCTSConfig
extends RefCounted

## Single source of truth for all MCTS parameters.
## Referenced by mcts_ai_controller.gd, mcts_search.gd, and record_progress.gd.

# Search parameters
const ITERATIONS: int = 500
const ROLLOUT_DEPTH: int = 30
const SEARCH_TIMEOUT_MS: int = 5000  # Max wall-clock time per search (ms)

# UCB1 exploration constant (in mcts_node.gd)
const EXPLORATION_CONSTANT: float = 1.414
