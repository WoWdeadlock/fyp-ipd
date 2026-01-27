"""
Simplified training approach - learn action preferences through self-play.

Instead of full MCTS tree search, this uses:
- Action statistics tracking
- Win/loss recording per action
- Gradually improving action selection based on success rates
"""

import argparse
import json
import time
import random
from pathlib import Path
from datetime import datetime
from collections import defaultdict

import mcts_client as client
from mcts import get_valid_actions, action_to_string, ACTIONS


class SimplePolicy:
    """Simple policy that learns which actions work best."""

    def __init__(self):
        self.action_wins = defaultdict(int)  # Wins when action was taken
        self.action_losses = defaultdict(int)  # Losses when action was taken
        self.action_counts = defaultdict(int)  # Total times action was taken

    def get_action_score(self, action):
        """Get success rate for an action."""
        total = self.action_counts.get(action, 0)
        if total == 0:
            return 0.5  # Unknown action, neutral score

        wins = self.action_wins.get(action, 0)
        return wins / total

    def select_action(self, state, exploration_rate=0.2):
        """Select action using epsilon-greedy strategy."""
        valid_actions = get_valid_actions(state)
        if not valid_actions:
            return ACTIONS[0]

        # Explore: random action
        if random.random() < exploration_rate:
            return random.choice(valid_actions)

        # Exploit: best action based on learned statistics
        best_action = max(valid_actions, key=self.get_action_score)
        return best_action

    def update(self, actions_taken, outcome):
        """Update statistics based on episode outcome."""
        for action in actions_taken:
            self.action_counts[action] += 1
            if outcome == 'victory':
                self.action_wins[action] += 1
            else:
                self.action_losses[action] += 1

    def save(self, filepath):
        """Save policy statistics."""
        data = {
            'wins': dict([(str(k), v) for k, v in self.action_wins.items()]),
            'losses': dict([(str(k), v) for k, v in self.action_losses.items()]),
            'counts': dict([(str(k), v) for k, v in self.action_counts.items()])
        }
        with open(filepath, 'w') as f:
            json.dump(data, f, indent=2)

    def get_stats(self):
        """Get human-readable statistics."""
        stats = []
        for action in ACTIONS:
            count = self.action_counts.get(action, 0)
            if count > 0:
                score = self.get_action_score(action)
                stats.append((action_to_string(action), score, count))

        stats.sort(key=lambda x: x[1], reverse=True)
        return stats


def run_episode(policy, exploration_rate=0.2):
    """Run one training episode."""
    print("\n=== Starting Episode ===")

    # Reset
    state = client.reset()
    time.sleep(2)
    state = client.get_state()

    actions_taken = []
    steps = 0
    max_steps = 200

    while not state['is_terminal'] and steps < max_steps:
        print(f"\nStep {steps + 1}: Boss HP: {state['boss']['hp']}, Tank HP: {state['tank']['hp']}")

        # Select action
        action = policy.select_action(state, exploration_rate)
        print(f"  Action: {action_to_string(action)}")

        # Execute
        state = client.execute_action(*action)
        actions_taken.append(action)

        # Wait for action
        _, ability, _ = action
        if ability == "melee":
            time.sleep(5.0)
        elif ability in ["heal", "restore"]:
            time.sleep(2.0)
        elif ability in ["shot", "cripple", "power"]:
            time.sleep(2.0)
        else:
            time.sleep(1.5)

        state = client.get_state()
        steps += 1

    outcome = state.get('outcome', 'unknown')
    print(f"\n=== Episode Complete: {outcome} in {steps} steps ===")

    # Update policy
    policy.update(actions_taken, outcome)

    return {
        'outcome': outcome,
        'steps': steps,
        'actions': [action_to_string(a) for a in actions_taken]
    }


def train(args):
    """Main training loop."""
    print("=" * 60)
    print("Simple Policy Training")
    print("=" * 60)

    policy = SimplePolicy()
    results = []

    # Progressive exploration: start high, decrease over time
    for episode in range(args.episodes):
        exploration_rate = max(0.1, 0.5 - (episode / args.episodes) * 0.4)

        print(f"\n{'='*60}")
        print(f"Episode {episode + 1}/{args.episodes}")
        print(f"Exploration rate: {exploration_rate:.2f}")
        print(f"{'='*60}")

        stats = run_episode(policy, exploration_rate)
        results.append(stats)

        # Calculate win rate
        wins = sum(1 for r in results if r['outcome'] == 'victory')
        win_rate = wins / len(results)

        print(f"\nCumulative Win Rate: {win_rate:.1%} ({wins}/{len(results)})")

        # Show top actions
        if (episode + 1) % 5 == 0:
            print("\nTop Actions So Far:")
            for action_str, score, count in policy.get_stats()[:5]:
                print(f"  {action_str}: {score:.2%} success ({count} uses)")

    # Save policy
    policy.save("simple_policy.json")
    print(f"\n{'='*60}")
    print(f"Training Complete!")
    print(f"Policy saved to simple_policy.json")
    print(f"Final Win Rate: {wins}/{args.episodes} = {wins/args.episodes:.1%}")
    print(f"{'='*60}")


def main():
    parser = argparse.ArgumentParser(description="Simple Policy Training")
    parser.add_argument('--episodes', type=int, default=20,
                       help='Number of training episodes')

    args = parser.parse_args()

    print("\nMake sure Godot is running with grid.tscn loaded!")
    input("Press Enter when ready...")

    try:
        # Test connection
        print("\nTesting connection...")
        state = client.reset()
        time.sleep(2)
        state = client.get_state()
        print(f"Connected! Boss HP: {state['boss']['hp']}, Tank HP: {state['tank']['hp']}")

        # Train
        train(args)

    except Exception as e:
        print(f"\nError: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()
