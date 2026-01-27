"""
MCTS Training Script

Main entry point for training the MCTS policy tree through self-play episodes.

Usage:
    python train_mcts.py --episodes 50 --iterations 5000
    python train_mcts.py --resume checkpoints/tree_ep10.pkl --episodes 20
    python train_mcts.py --eval-only --tree mcts_policy_tree.pkl --episodes 20
"""

import argparse
import json
import os
import time
from pathlib import Path
from datetime import datetime

import mcts_client as client
from mcts import MCTSTree, action_to_string, hash_state


def run_episode_with_mcts(tree, iterations, exploration_constant, max_steps=500):
    """
    Run one training episode using MCTS for decision making.

    Args:
        tree: MCTSTree instance
        iterations: MCTS iterations per action
        exploration_constant: UCB1 exploration parameter
        max_steps: Maximum steps per episode

    Returns:
        Episode statistics dict
    """
    print("\n=== Starting New Episode ===")

    # Reset game
    state = client.reset()
    time.sleep(2)  # Wait for reset to complete
    state = client.get_state()
    tree.set_root(state)

    # Track nodes visited during this episode for later backpropagation
    episode_nodes = [tree.root]

    steps = 0
    actions_taken = []
    episode_reward = 0.0

    while not state['is_terminal'] and steps < max_steps:
        # Run MCTS search from current state
        print(f"\nStep {steps + 1}:")
        print(f"  Boss HP: {state['boss']['hp']}, Tank HP: {state['tank']['hp']}")

        # Pause boss during MCTS search
        client.pause_boss()
        print(f"  Boss paused for MCTS search...")

        start_time = time.time()
        best_action = tree.search(iterations, exploration_constant, verbose=True)
        search_time = time.time() - start_time

        print(f"  MCTS search: {iterations} iterations in {search_time:.2f}s")

        # Unpause boss and get fresh state
        state = client.unpause_boss()
        print(f"  Boss unpaused. State: Boss HP: {state['boss']['hp']}, Tank HP: {state['tank']['hp']}")

        # Check if game ended during search
        if state['is_terminal']:
            print(f"  Game ended during MCTS search!")
            break

        print(f"  Selected action: {action_to_string(best_action)}")
        print(f"  Executing action in Godot...")

        # Execute action in Godot
        try:
            state = client.execute_action(*best_action)
            print(f"  Action executed, waiting for completion...")
        except Exception as e:
            print(f"  ERROR executing action: {e}")
            break

        actions_taken.append(best_action)

        # Wait for action to complete - different timing per action type
        action_agent, action_ability, _ = best_action

        # Melee attacks take longest (movement + attack)
        if action_ability == "melee":
            print(f"  Waiting for tank melee (movement + attack)...")
            time.sleep(5.0)  # Tank needs to move to boss and attack
        elif action_ability in ["heal", "restore"]:
            print(f"  Waiting for healer ability cast...")
            time.sleep(2.0)  # Healer cast time + safety margin
        elif action_ability in ["shot", "cripple", "power"]:
            print(f"  Waiting for sniper attack...")
            time.sleep(2.0)  # Sniper positioning + attack
        elif action_ability in ["shield", "taunt", "defensive"]:
            print(f"  Waiting for utility ability...")
            time.sleep(1.5)  # Quick abilities
        else:
            time.sleep(1.0)

        # Get updated state after action completes
        state = client.get_state()

        # Update tree root to new state
        tree.update_root_state(state)
        episode_nodes.append(tree.root)  # Track for backpropagation

        steps += 1

    # Episode complete
    outcome = state.get('outcome', 'unknown')
    print(f"\n=== Episode Complete ===")
    print(f"Outcome: {outcome}")
    print(f"Steps: {steps}")
    print(f"Boss HP: {state['boss']['hp']}")

    # Backpropagate real episode outcome through visited nodes
    if outcome == 'victory':
        real_reward = 1000.0 - steps  # Bonus for faster victories
        print(f"Victory! Backpropagating reward: {real_reward:.1f}")
    elif outcome == 'defeat':
        real_reward = -500.0
        print(f"Defeat. Backpropagating penalty: {real_reward:.1f}")
    else:
        real_reward = 0.0

    # Update all nodes in the episode path with real outcome
    for node in episode_nodes:
        if node:
            node.visits += 1
            node.value += real_reward

    return {
        'steps': steps,
        'outcome': outcome,
        'boss_hp_remaining': state['boss']['hp'],
        'agents_alive': sum([
            1 if state['tank']['hp'] > 0 else 0,
            1 if state['healer']['hp'] > 0 else 0,
            1 if state['sniper']['hp'] > 0 else 0
        ]),
        'actions': [action_to_string(a) for a in actions_taken],
        'tree_stats': tree.get_stats()
    }


def train_mcts(args):
    """
    Main training loop.
    """
    print("=" * 60)
    print("MCTS Training for Boss Combat Optimization")
    print("=" * 60)

    # Create checkpoint directory
    checkpoint_dir = Path("checkpoints")
    checkpoint_dir.mkdir(exist_ok=True)

    # Initialize or load tree
    tree = MCTSTree()
    start_episode = 0

    if args.resume:
        print(f"\nLoading tree from {args.resume}...")
        tree.load(args.resume)
        # Extract episode number from filename
        try:
            start_episode = int(args.resume.split('_ep')[1].split('.')[0])
        except:
            start_episode = 0
    else:
        print("\nInitializing new MCTS tree...")

    # Training log
    log_file = Path("training_log.jsonl")
    print(f"Logging to {log_file}")

    # Progressive exploration schedule
    def get_exploration_constant(episode_num):
        total_episodes = args.episodes
        if episode_num < total_episodes * 0.2:  # Warm-up (first 20%)
            return 2.0
        elif episode_num < total_episodes * 0.8:  # Training (20-80%)
            return 1.41
        else:  # Refinement (last 20%)
            return 1.0

    # Training loop
    win_count = 0
    for episode in range(start_episode, start_episode + args.episodes):
        print(f"\n{'='*60}")
        print(f"Episode {episode + 1}/{start_episode + args.episodes}")
        print(f"{'='*60}")

        exploration = get_exploration_constant(episode - start_episode)
        print(f"Exploration constant: {exploration}")

        # Run episode
        start_time = time.time()
        stats = run_episode_with_mcts(
            tree,
            args.iterations,
            exploration,
            max_steps=500
        )
        episode_time = time.time() - start_time

        # Update win count
        if stats['outcome'] == 'victory':
            win_count += 1

        # Log statistics
        log_entry = {
            'episode': episode + 1,
            'outcome': stats['outcome'],
            'steps': stats['steps'],
            'boss_hp': stats['boss_hp_remaining'],
            'agents_alive': stats['agents_alive'],
            'win_rate': win_count / (episode - start_episode + 1),
            'episode_time': episode_time,
            'tree_nodes': stats['tree_stats']['total_nodes'],
            'tree_iterations': stats['tree_stats']['total_iterations'],
            'timestamp': datetime.now().isoformat()
        }

        with open(log_file, 'a') as f:
            f.write(json.dumps(log_entry) + '\n')

        print(f"\nCumulative Win Rate: {log_entry['win_rate']:.1%} ({win_count}/{episode - start_episode + 1})")
        print(f"Tree size: {stats['tree_stats']['total_nodes']} nodes")

        # Save checkpoint
        if (episode + 1) % args.checkpoint_every == 0:
            checkpoint_path = checkpoint_dir / f"tree_ep{episode + 1}.pkl"
            tree.save(str(checkpoint_path))

    # Save final tree
    final_path = "mcts_policy_tree.pkl"
    tree.save(final_path)
    print(f"\n{'='*60}")
    print(f"Training complete! Final tree saved to {final_path}")
    print(f"Final win rate: {win_count}/{args.episodes} = {win_count/args.episodes:.1%}")
    print(f"{'='*60}")


def evaluate_policy(args):
    """
    Evaluate a trained policy tree.
    """
    print("=" * 60)
    print("MCTS Policy Evaluation")
    print("=" * 60)

    # Load tree
    tree = MCTSTree()
    print(f"\nLoading tree from {args.tree}...")
    tree.load(args.tree)

    # Run evaluation episodes
    win_count = 0
    total_steps = []

    for episode in range(args.episodes):
        print(f"\n{'='*60}")
        print(f"Evaluation Episode {episode + 1}/{args.episodes}")
        print(f"{'='*60}")

        stats = run_episode_with_mcts(
            tree,
            args.eval_iterations,  # Fewer iterations for evaluation
            exploration_constant=0.5,  # Low exploration, mostly exploitation
            max_steps=500
        )

        if stats['outcome'] == 'victory':
            win_count += 1
            total_steps.append(stats['steps'])

        print(f"\nCurrent Win Rate: {win_count}/{episode + 1} = {win_count/(episode + 1):.1%}")

    # Final results
    print(f"\n{'='*60}")
    print("Evaluation Results:")
    print(f"  Win Rate: {win_count}/{args.episodes} = {win_count/args.episodes:.1%}")
    if total_steps:
        print(f"  Avg Steps to Victory: {sum(total_steps)/len(total_steps):.1f}")
        print(f"  Min Steps: {min(total_steps)}")
        print(f"  Max Steps: {max(total_steps)}")
    print(f"{'='*60}")


def main():
    parser = argparse.ArgumentParser(description="MCTS Training for Boss Combat")

    # Training parameters
    parser.add_argument('--episodes', type=int, default=50,
                       help='Number of training episodes (default: 50)')
    parser.add_argument('--iterations', type=int, default=20,
                       help='MCTS iterations per action (default: 20 for fast testing, increase for better quality)')
    parser.add_argument('--checkpoint-every', type=int, default=10,
                       help='Save checkpoint every N episodes (default: 10)')

    # Resume training
    parser.add_argument('--resume', type=str, default=None,
                       help='Resume from checkpoint file')

    # Evaluation mode
    parser.add_argument('--eval-only', action='store_true',
                       help='Evaluation mode: test trained policy without training')
    parser.add_argument('--tree', type=str, default='mcts_policy_tree.pkl',
                       help='Tree file to load for evaluation')
    parser.add_argument('--eval-iterations', type=int, default=1000,
                       help='MCTS iterations for evaluation (default: 1000)')

    args = parser.parse_args()

    # Check Godot connection
    print("\nMake sure Godot is running with grid.tscn loaded!")
    input("Press Enter when ready...")

    try:
        # Test connection and reset to fresh state
        print("\nTesting connection to Godot...")
        print("Resetting game to initial state...")
        state = client.reset()
        time.sleep(2)  # Wait for scene to fully reload
        state = client.get_state()
        print(f"Connected! Boss HP: {state['boss']['hp']}, Tank HP: {state['tank']['hp']}")

        if state['tank']['hp'] == 0 or state['is_terminal']:
            print("\nWARNING: Game appears to be in a terminal state after reset!")
            print("Please manually restart the scene in Godot and try again.")
            return

        # Run training or evaluation
        if args.eval_only:
            evaluate_policy(args)
        else:
            train_mcts(args)

    except Exception as e:
        print(f"\nError: {e}")
        print("Make sure Godot is running with the game scene loaded!")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()
