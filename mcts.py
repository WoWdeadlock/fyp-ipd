"""
MCTS (Monte Carlo Tree Search) implementation for Godot combat optimization.

This module provides a persistent MCTS tree that learns across multiple episodes
to build an adaptive strategy selector for beating the Boss.
"""

import math
import random
import pickle
import copy
from typing import Dict, List, Tuple, Optional

# Action space definition
ACTIONS = [
    ("tank", "melee", ""),
    ("tank", "taunt", ""),
    ("tank", "defensive", ""),
    ("healer", "heal", "tank"),
    ("healer", "heal", "sniper"),
    ("healer", "shield", "tank"),
    ("healer", "restore", "sniper"),
    ("sniper", "shot", ""),
    ("sniper", "cripple", ""),
    ("sniper", "power", ""),
]

# Action costs (stamina) and metadata
ACTION_COSTS = {
    ("tank", "melee", ""): 20,
    ("tank", "taunt", ""): 15,
    ("tank", "defensive", ""): 10,
    ("healer", "heal", "tank"): 40,
    ("healer", "heal", "sniper"): 40,
    ("healer", "shield", "tank"): 30,
    ("healer", "restore", "sniper"): 50,
    ("sniper", "shot", ""): 25,
    ("sniper", "cripple", ""): 40,
    ("sniper", "power", ""): 60,
}

# Tiered action priorities for heuristic rollouts
TIER1_ACTIONS = [  # Offensive (60% chance)
    ("tank", "melee", ""),
    ("sniper", "shot", ""),
    ("sniper", "power", ""),
]

TIER2_ACTIONS = [  # Support (25% chance)
    ("healer", "heal", "tank"),
    ("healer", "shield", "tank"),
    ("sniper", "cripple", ""),
]

TIER3_ACTIONS = [  # Defensive/utility (15% chance)
    ("tank", "defensive", ""),
    ("tank", "taunt", ""),
    ("healer", "heal", "sniper"),
    ("healer", "restore", "sniper"),
]


def hash_state(state: Dict) -> Tuple:
    """
    Create hashable state key for node lookup and tree reuse.
    Uses aggressive discretization to reduce state space.

    Args:
        state: Game state dict from Godot

    Returns:
        Tuple representing discretized state
    """
    # HP bucketing: 20 HP per bucket
    boss_hp_bucket = min(max(round(state['boss']['hp'] / 20), 0), 25)
    tank_hp_bucket = min(max(round(state['tank']['hp'] / 20), 0), 7)
    healer_hp_bucket = min(max(round(state['healer']['hp'] / 20), 0), 3)
    sniper_hp_bucket = min(max(round(state['sniper']['hp'] / 20), 0), 4)

    # Stamina: coarse bucketing (50 stamina per bucket)
    tank_stam = min(max(round(state['tank']['stamina'] / 50), 0), 2)
    healer_stam = min(max(round(state['healer']['stamina'] / 50), 0), 3)

    # Track which agents are alive
    agents_alive = (
        1 if state['tank']['hp'] > 0 else 0,
        1 if state['healer']['hp'] > 0 else 0,
        1 if state['sniper']['hp'] > 0 else 0
    )

    return (
        boss_hp_bucket,
        tank_hp_bucket, healer_hp_bucket, sniper_hp_bucket,
        tank_stam, healer_stam,
        agents_alive
    )


def get_valid_actions(state: Dict) -> List[Tuple[str, str, str]]:
    """
    Filter actions based on current state (stamina, HP, etc.).

    Args:
        state: Current game state

    Returns:
        List of valid actions
    """
    valid = []

    for action in ACTIONS:
        agent_name, ability, target = action

        # Check if agent is alive
        if state[agent_name]['hp'] <= 0:
            continue

        # Check stamina cost
        cost = ACTION_COSTS.get(action, 0)
        if state[agent_name]['stamina'] < cost:
            continue

        # Check if target is alive (for targeted abilities)
        if target and state[target]['hp'] <= 0:
            continue

        # Don't heal if target is at full HP
        if ability == "heal":
            target_max_hp = {"tank": 150, "healer": 70, "sniper": 80}
            if state[target]['hp'] >= target_max_hp[target]:
                continue

        # Don't restore if target stamina is full
        if ability == "restore":
            if state[target]['stamina'] >= 120:  # Sniper max stamina
                continue

        valid.append(action)

    return valid if valid else [ACTIONS[0]]  # Always return at least one action


def action_to_string(action: Tuple[str, str, str]) -> str:
    """Pretty print action."""
    agent, ability, target = action
    if target:
        return f"{agent}.{ability}({target})"
    return f"{agent}.{ability}()"


class MCTSNode:
    """
    MCTS tree node representing a game state.
    """

    def __init__(self, state: Dict, parent: Optional['MCTSNode'] = None,
                 action: Optional[Tuple[str, str, str]] = None):
        self.state = state
        self.state_hash = hash_state(state)
        self.parent = parent
        self.action = action  # Action that led to this state
        self.children = {}  # Dict: action -> child node
        self.visits = 0
        self.value = 0.0
        self.terminal = state.get('is_terminal', False)

        # Initialize untried actions
        if not self.terminal:
            self.untried_actions = get_valid_actions(state)
        else:
            self.untried_actions = []

    def is_fully_expanded(self) -> bool:
        """Check if all valid actions have been tried."""
        return len(self.untried_actions) == 0

    def best_child(self, exploration_constant: float = 1.41) -> 'MCTSNode':
        """
        Select best child using UCB1 formula.

        Args:
            exploration_constant: Exploration parameter (c in UCB1)

        Returns:
            Child node with highest UCB1 value
        """
        if not self.children:
            raise ValueError("Cannot select best child: node has no children")

        best_value = -float('inf')
        best_nodes = []

        for child in self.children.values():
            if child.visits == 0:
                ucb_value = float('inf')
            else:
                exploit = child.value / child.visits
                explore = exploration_constant * math.sqrt(math.log(self.visits) / child.visits)
                ucb_value = exploit + explore

            if ucb_value > best_value:
                best_value = ucb_value
                best_nodes = [child]
            elif ucb_value == best_value:
                best_nodes.append(child)

        if not best_nodes:
            raise ValueError("No valid children found")

        return random.choice(best_nodes)

    def most_visited_child(self) -> Optional['MCTSNode']:
        """Return child with most visits (best action)."""
        if not self.children:
            return None
        return max(self.children.values(), key=lambda n: n.visits)

    def __repr__(self):
        return f"MCTSNode(visits={self.visits}, value={self.value:.2f}, children={len(self.children)})"


class MCTSTree:
    """
    Persistent MCTS tree that grows across episodes.
    """

    def __init__(self):
        self.nodes = {}  # Dict: state_hash -> MCTSNode
        self.root = None
        self.total_iterations = 0

    def get_or_create_node(self, state: Dict, parent: Optional[MCTSNode] = None,
                          action: Optional[Tuple[str, str, str]] = None) -> MCTSNode:
        """
        Get existing node for state or create new one.
        Enables tree reuse across similar states.
        """
        state_hash = hash_state(state)

        if state_hash in self.nodes:
            return self.nodes[state_hash]

        node = MCTSNode(state, parent, action)
        self.nodes[state_hash] = node
        return node

    def set_root(self, state: Dict):
        """Set root node for current search."""
        self.root = self.get_or_create_node(state)

    def search(self, iterations: int, exploration_constant: float = 1.41,
               rollout_depth: int = 150, verbose: bool = False) -> Tuple[str, str, str]:
        """
        Run MCTS iterations from current root.

        Args:
            iterations: Number of MCTS iterations to run
            exploration_constant: UCB1 exploration parameter
            rollout_depth: Maximum depth for rollout simulations
            verbose: Print progress every 10% of iterations

        Returns:
            Best action to take from root
        """
        if self.root is None:
            raise ValueError("Root node not set. Call set_root() first.")

        progress_interval = max(1, iterations // 10)  # Report every 10%

        for i in range(iterations):
            try:
                # 1. Selection: traverse tree using UCB1
                node = self._select(self.root, exploration_constant)

                # 2. Expansion: add one child if not terminal
                if not node.terminal and not node.is_fully_expanded():
                    node = self._expand(node)

                # 3. Simulation: rollout from node
                reward = self._simulate(node, rollout_depth)

                # 4. Backpropagation: update ancestors
                self._backpropagate(node, reward)

                self.total_iterations += 1

                # Progress indicator
                if verbose and (i + 1) % progress_interval == 0:
                    pct = ((i + 1) / iterations) * 100
                    print(f"    MCTS progress: {pct:.0f}% ({i+1}/{iterations} iterations)")

            except Exception as e:
                print(f"    Warning: MCTS iteration {i+1} failed: {e}")
                # Continue with next iteration
                continue

        # Return best action (highest visit count)
        return self.get_best_action()

    def _select(self, node: MCTSNode, exploration_constant: float) -> MCTSNode:
        """Selection phase: traverse tree using UCB1."""
        max_depth = 100  # Safety limit to prevent infinite loops
        depth = 0

        while not node.terminal and depth < max_depth:
            if not node.is_fully_expanded():
                return node
            if not node.children:  # No children, can't go deeper
                return node
            node = node.best_child(exploration_constant)
            depth += 1

        return node

    def _simulate_action(self, state: Dict, action: Tuple[str, str, str]) -> Dict:
        """
        Simulate the effect of an action on the state.
        This creates an estimated next state without executing in Godot.

        Args:
            state: Current game state
            action: Action tuple (agent, ability, target)

        Returns:
            Estimated next state after action
        """
        # Deep copy state to avoid modifying original
        new_state = copy.deepcopy(state)

        agent_name, ability, target = action

        # Deduct stamina cost
        cost = ACTION_COSTS.get(action, 0)
        new_state[agent_name]['stamina'] = max(0, new_state[agent_name]['stamina'] - cost)

        # Estimate action effects
        if ability == "melee":
            # Tank melee: ~25 damage to boss
            new_state['boss']['hp'] = max(0, new_state['boss']['hp'] - 25)

        elif ability == "shot":
            # Sniper shot: ~20 damage
            new_state['boss']['hp'] = max(0, new_state['boss']['hp'] - 20)

        elif ability == "power":
            # Sniper power shot: ~40 damage
            new_state['boss']['hp'] = max(0, new_state['boss']['hp'] - 40)

        elif ability == "cripple":
            # Sniper cripple: ~15 damage + slow effect (not modeled)
            new_state['boss']['hp'] = max(0, new_state['boss']['hp'] - 15)

        elif ability == "heal":
            # Healer heal: restore ~40 HP
            target_max_hp = {"tank": 150, "healer": 70, "sniper": 80}
            current_hp = new_state[target]['hp']
            new_state[target]['hp'] = min(target_max_hp[target], current_hp + 40)

        elif ability == "shield":
            # Shield buff applied (damage reduction not modeled in state)
            pass

        elif ability == "restore":
            # Restore stamina: ~60 stamina
            new_state[target]['stamina'] = min(120, new_state[target]['stamina'] + 60)

        elif ability == "taunt":
            # Taunt effect (aggro not modeled in state)
            pass

        elif ability == "defensive":
            # Defensive stance (damage reduction not modeled)
            pass

        # Simulate boss retaliation (simplified)
        # Boss attacks tank most of the time
        if new_state['boss']['hp'] > 0 and new_state['tank']['hp'] > 0:
            boss_damage = random.randint(15, 25)  # Boss does 15-25 damage
            new_state['tank']['hp'] = max(0, new_state['tank']['hp'] - boss_damage)

        # Add small stamina regeneration
        for agent in ['tank', 'healer', 'sniper']:
            if new_state[agent]['hp'] > 0:
                max_stamina = {"tank": 80, "healer": 150, "sniper": 120}
                new_state[agent]['stamina'] = min(
                    max_stamina[agent],
                    new_state[agent]['stamina'] + 5
                )

        # Check terminal conditions
        if new_state['boss']['hp'] <= 0:
            new_state['is_terminal'] = True
            new_state['outcome'] = 'victory'
        elif (new_state['tank']['hp'] <= 0 and
              new_state['healer']['hp'] <= 0 and
              new_state['sniper']['hp'] <= 0):
            new_state['is_terminal'] = True
            new_state['outcome'] = 'defeat'

        return new_state

    def _expand(self, node: MCTSNode) -> MCTSNode:
        """Expansion phase: add one untried action as child."""
        action = random.choice(node.untried_actions)
        node.untried_actions.remove(action)

        # Create a simulated child state by estimating the effect of the action
        child_state = self._simulate_action(node.state, action)

        # Always create a new child node during expansion (don't reuse from global dict)
        # This ensures the tree actually grows during search
        child_node = MCTSNode(child_state, parent=node, action=action)
        node.children[action] = child_node

        return child_node

    def _simulate(self, node: MCTSNode, max_depth: int) -> float:
        """
        Simulation phase: rollout using heuristic policy.

        NOTE: This is a simplified simulation without actually executing in Godot.
        It estimates reward based on state changes and heuristics.
        For accurate simulation, would need to execute actions in Godot during training.
        """
        # For terminal nodes, return immediate reward
        if node.terminal:
            outcome = node.state.get('outcome', '')
            if outcome == 'victory':
                return 1000.0
            elif outcome == 'defeat':
                return -500.0
            return 0.0

        # Heuristic reward estimation based on state
        reward = self._estimate_reward(node.state)

        # Add some randomness to encourage exploration
        reward += random.uniform(-10, 10)

        return reward

    def _estimate_reward(self, state: Dict) -> float:
        """
        Estimate reward for a state using heuristics.
        """
        reward = 0.0

        # Boss damage dealt (positive)
        boss_hp = state['boss']['hp']
        reward += (500 - boss_hp)  # More damage = higher reward

        # Agent health (negative for damage taken)
        tank_hp = state['tank']['hp']
        healer_hp = state['healer']['hp']
        sniper_hp = state['sniper']['hp']

        reward -= (150 - tank_hp) * 2  # Tank HP important
        reward -= (70 - healer_hp) * 3  # Healer HP critical
        reward -= (80 - sniper_hp) * 2  # Sniper HP important

        # Terminal state rewards
        if state.get('is_terminal'):
            if state.get('outcome') == 'victory':
                reward += 1000
            elif state.get('outcome') == 'defeat':
                reward -= 500

        return reward

    def _backpropagate(self, node: MCTSNode, reward: float):
        """Backpropagation phase: update node and ancestors."""
        while node is not None:
            node.visits += 1
            node.value += reward
            node = node.parent

    def get_best_action(self) -> Tuple[str, str, str]:
        """Return action with highest visit count from root."""
        if self.root is None:
            print("    Warning: Root is None, using fallback action")
            return ACTIONS[0]

        if not self.root.children:
            # No children created, fallback to random valid action
            print("    Warning: No children in tree, using random valid action")
            valid_actions = get_valid_actions(self.root.state)
            if not valid_actions:
                print("    Warning: No valid actions, using default action")
                return ACTIONS[0]
            return random.choice(valid_actions)

        best_child = self.root.most_visited_child()
        if best_child is None or best_child.action is None:
            print("    Warning: No best child found, using random valid action")
            valid_actions = get_valid_actions(self.root.state)
            return valid_actions[0] if valid_actions else ACTIONS[0]

        return best_child.action

    def advance_to_child(self, action: Tuple[str, str, str]):
        """Move root to child node after taking action."""
        if action in self.root.children:
            self.root = self.root.children[action]
            self.root.parent = None  # Detach from old parent
        else:
            # Action not in tree, create new node
            # This happens when exploring new states
            print(f"Warning: Action {action_to_string(action)} not in tree, will need new root")

    def update_root_state(self, new_state: Dict):
        """Update root to match new state from environment."""
        self.root = self.get_or_create_node(new_state)

    def save(self, filepath: str):
        """Serialize tree to file."""
        with open(filepath, 'wb') as f:
            pickle.dump({
                'nodes': self.nodes,
                'total_iterations': self.total_iterations
            }, f)
        print(f"Tree saved to {filepath} ({len(self.nodes)} nodes, {self.total_iterations} iterations)")

    def load(self, filepath: str):
        """Load tree from file."""
        with open(filepath, 'rb') as f:
            data = pickle.load(f)
            self.nodes = data['nodes']
            self.total_iterations = data.get('total_iterations', 0)
        print(f"Tree loaded from {filepath} ({len(self.nodes)} nodes, {self.total_iterations} iterations)")

    def get_stats(self) -> Dict:
        """Get tree statistics."""
        return {
            'total_nodes': len(self.nodes),
            'total_iterations': self.total_iterations,
            'root_visits': self.root.visits if self.root else 0,
            'root_children': len(self.root.children) if self.root else 0,
        }


def select_action_heuristic(state: Dict) -> Tuple[str, str, str]:
    """
    Heuristic action selection for rollouts.
    Uses tiered priority system.
    """
    valid_actions = get_valid_actions(state)

    # Separate actions by tier
    tier1 = [a for a in valid_actions if a in TIER1_ACTIONS]
    tier2 = [a for a in valid_actions if a in TIER2_ACTIONS]
    tier3 = [a for a in valid_actions if a in TIER3_ACTIONS]

    # Select tier based on probability
    rand = random.random()
    if rand < 0.6 and tier1:
        return random.choice(tier1)
    elif rand < 0.85 and tier2:
        return random.choice(tier2)
    elif tier3:
        return random.choice(tier3)

    # Fallback to any valid action
    return random.choice(valid_actions) if valid_actions else ACTIONS[0]
