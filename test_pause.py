"""
Test boss pause/unpause functionality with long pauses to verify visually.
"""

import time
import mcts_client as client

def test_pause_unpause():
    print("=" * 60)
    print("Boss Pause/Unpause Visual Test")
    print("=" * 60)
    print("\nMake sure Godot is running with grid.tscn loaded!")
    print("WATCH THE GAME WINDOW - Boss should freeze when paused!\n")
    input("Press Enter when ready...\n")

    # Reset to fresh state
    print("Resetting game...")
    state = client.reset()
    time.sleep(2)
    state = client.get_state()
    print(f"Boss HP: {state['boss']['hp']}, Tank HP: {state['tank']['hp']}\n")

    # Test 1: Long pause (10 seconds)
    print("TEST 1: Pausing boss for 10 seconds...")
    print("  WATCH THE GAME - Boss should be FROZEN")
    print("  Tank/Healer/Sniper should still move normally")

    client.pause_boss()
    print("  Boss paused! Waiting 10 seconds...")

    for i in range(10):
        time.sleep(1)
        print(f"    {i+1}/10 seconds elapsed (boss should be frozen)...")

    state = client.unpause_boss()
    print("  Boss unpaused! Boss should move again.\n")

    # Wait to see boss resume
    time.sleep(3)

    # Test 2: Multiple pause/unpause cycles
    print("TEST 2: Multiple pause/unpause cycles...")
    for cycle in range(3):
        print(f"\n  Cycle {cycle + 1}/3:")

        # Pause for 5 seconds
        print("    Pausing...")
        client.pause_boss()
        time.sleep(5)

        # Unpause for 5 seconds
        print("    Unpausing...")
        state = client.unpause_boss()
        time.sleep(5)

    print("\n" + "=" * 60)
    print("Test Complete!")
    print("=" * 60)
    print("\nDid you see the boss freeze during pauses?")
    response = input("Enter 'yes' or 'no': ").strip().lower()

    if response == 'yes':
        print("\n[SUCCESS] Pause/unpause is working correctly!")
        print("You can proceed with MCTS training.")
    else:
        print("\n[PROBLEM] Pause/unpause may not be working.")
        print("Check:")
        print("  1. Godot console for 'Boss paused' messages")
        print("  2. Script errors in Godot output")
        print("  3. That the scene has been reloaded after script changes")

if __name__ == "__main__":
    test_pause_unpause()
