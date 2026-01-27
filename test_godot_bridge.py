"""
Simple test script to verify Godot bridge is working correctly.

This script executes a fixed sequence of actions to test:
1. Reset functionality
2. Action execution
3. State updates
4. Timing and synchronization
"""

import time
import mcts_client as client

def test_bridge():
    print("=" * 60)
    print("Godot Bridge Test")
    print("=" * 60)
    print("\nMake sure Godot is running with grid.tscn loaded!")
    input("Press Enter when ready...\n")

    try:
        # Test 1: Reset
        print("Test 1: Resetting game...")
        state = client.reset()
        time.sleep(2)  # Wait for reset
        state = client.get_state()

        print(f"  Boss HP: {state['boss']['hp']}")
        print(f"  Tank HP: {state['tank']['hp']}")
        print(f"  Healer HP: {state['healer']['hp']}")
        print(f"  Sniper HP: {state['sniper']['hp']}")
        print(f"  Terminal: {state['is_terminal']}")

        if state['is_terminal'] or state['tank']['hp'] == 0:
            print("\nERROR: Game is in terminal state after reset!")
            print("Please restart the scene in Godot manually.")
            return

        print("  [PASS] Reset works!\n")

        # Test 2: Execute tank melee attack with polling
        print("Test 2: Tank melee attack...")
        boss_hp_before = state['boss']['hp']
        print(f"  Boss HP before: {boss_hp_before}")
        print("  Executing action...")

        state = client.execute_action("tank", "melee", "")

        # Poll for state change (wait up to 8 seconds - melee takes time!)
        print("  Polling for damage (tank needs to move to boss)...")
        changed = False
        for i in range(16):
            time.sleep(0.5)
            state = client.get_state()
            if state['boss']['hp'] < boss_hp_before:
                changed = True
                print(f"    Damage detected after {(i+1)*0.5:.1f}s!")
                break
            if i % 2 == 1:  # Print every second
                print(f"    Poll {i//2+1}: Boss HP = {state['boss']['hp']}")

        print(f"  Boss HP after: {state['boss']['hp']}")

        if changed:
            damage = boss_hp_before - state['boss']['hp']
            print(f"  [PASS] Attack worked! Dealt {damage} damage\n")
        else:
            print("  [FAIL] Boss HP unchanged after 8 seconds\n")
            print("  Possible issues:")
            print("    - Tank may be stuck or unable to path to boss")
            print("    - Boss may be out of range")
            print("    - Method calls may not be working\n")

        # Test 3: Healer heals tank
        print("Test 3: Let boss attack, then heal tank...")
        print("  Waiting for boss to attack...")
        time.sleep(3.0)

        state = client.get_state()
        tank_hp_before = state['tank']['hp']
        print(f"  Tank HP: {tank_hp_before}")

        if tank_hp_before < 150:
            print("  Boss attacked! Now healing...")
            state = client.execute_action("healer", "heal", "tank")
            time.sleep(2.0)  # Heal has cast time

            state = client.get_state()
            tank_hp_after = state['tank']['hp']
            print(f"  Tank HP after heal: {tank_hp_after}")

            if tank_hp_after > tank_hp_before:
                print("  [PASS] Heal worked!\n")
            else:
                print("  [WARN] Tank HP unchanged, heal may not have worked\n")
        else:
            print("  [SKIP] Tank didn't take damage\n")

        # Test 4: Sniper power shot
        print("Test 4: Sniper power shot...")
        boss_hp_before = state['boss']['hp']
        print(f"  Boss HP before: {boss_hp_before}")

        state = client.execute_action("sniper", "power", "")

        # Wait and poll for sniper shot
        print("  Waiting for sniper to position and fire...")
        changed = False
        for i in range(8):
            time.sleep(0.5)
            state = client.get_state()
            if state['boss']['hp'] < boss_hp_before:
                changed = True
                damage = boss_hp_before - state['boss']['hp']
                print(f"  [PASS] Power shot worked! Dealt {damage} damage\n")
                break

        if not changed:
            print("  [WARN] Boss HP unchanged after 4 seconds\n")

        # Test 5: Get state multiple times
        print("Test 5: State consistency...")
        state1 = client.get_state()
        time.sleep(0.1)
        state2 = client.get_state()

        if state1['boss']['hp'] == state2['boss']['hp']:
            print("  [PASS] State reads are consistent\n")
        else:
            print("  [WARN] State changed between reads (game still running)\n")

        print("=" * 60)
        print("Bridge test complete!")
        print("=" * 60)
        print("\nIf all tests passed, you can proceed with MCTS training.")
        print("If there were warnings, check the timing delays in train_mcts.py")

    except Exception as e:
        print(f"\n[ERROR] Bridge test failed: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    test_bridge()
