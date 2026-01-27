"""
Test training with random action selection (no MCTS).
This verifies the bridge and training loop work without MCTS complexity.
"""

import time
import random
import mcts_client as client
from mcts import get_valid_actions, action_to_string

def run_random_episode():
    """Run one episode with random action selection."""
    print("\n=== Starting Random Episode ===")

    # Reset game
    state = client.reset()
    time.sleep(2)
    state = client.get_state()

    print(f"Initial state: Boss HP: {state['boss']['hp']}, Tank HP: {state['tank']['hp']}")

    steps = 0
    max_steps = 100

    while not state['is_terminal'] and steps < max_steps:
        print(f"\nStep {steps + 1}:")
        print(f"  Boss HP: {state['boss']['hp']}, Tank HP: {state['tank']['hp']}")

        # Get valid actions
        valid_actions = get_valid_actions(state)
        if not valid_actions:
            print("  No valid actions! Game over.")
            break

        # Random action selection
        action = random.choice(valid_actions)
        print(f"  Random action: {action_to_string(action)}")

        # Execute action
        state = client.execute_action(*action)

        # Wait for action
        action_agent, action_ability, _ = action
        if action_ability == "melee":
            time.sleep(5.0)
        elif action_ability in ["heal", "restore"]:
            time.sleep(2.0)
        elif action_ability in ["shot", "cripple", "power"]:
            time.sleep(2.0)
        else:
            time.sleep(1.5)

        # Get updated state
        state = client.get_state()
        steps += 1

    # Episode complete
    outcome = state.get('outcome', 'unknown')
    print(f"\n=== Episode Complete ===")
    print(f"Outcome: {outcome}")
    print(f"Steps: {steps}")
    print(f"Boss HP: {state['boss']['hp']}")

    return outcome

if __name__ == "__main__":
    print("Random Action Training Test")
    print("=" * 60)
    print("\nMake sure Godot is running with grid.tscn loaded!")
    input("Press Enter when ready...\n")

    # Run 3 random episodes
    for episode in range(3):
        print(f"\n{'='*60}")
        print(f"Episode {episode + 1}/3")
        print(f"{'='*60}")

        outcome = run_random_episode()
        time.sleep(2)  # Brief pause between episodes

    print("\n" + "=" * 60)
    print("Random training test complete!")
    print("If this worked, the bridge is functioning correctly.")
    print("=" * 60)
