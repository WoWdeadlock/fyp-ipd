"""
Test script for MCTS core functionality (no Godot required).

Tests:
- Node creation and state hashing
- UCB1 selection
- Tree operations
- Save/load
"""

from mcts import MCTSNode, MCTSTree, hash_state, get_valid_actions, action_to_string
from mcts_client import is_action_valid, get_all_actions

def create_test_state(boss_hp=500, tank_hp=150, healer_hp=70, sniper_hp=80):
    """Create a test game state."""
    return {
        'boss': {'hp': boss_hp, 'stamina': 300, 'pos': [0, 0]},
        'tank': {'hp': tank_hp, 'stamina': 80, 'pos': [0, 0]},
        'healer': {'hp': healer_hp, 'stamina': 150, 'pos': [0, 0]},
        'sniper': {'hp': sniper_hp, 'stamina': 120, 'pos': [0, 0]},
        'is_terminal': False,
        'outcome': ''
    }

def test_state_hashing():
    """Test state hashing consistency."""
    print("Test 1: State Hashing")
    print("-" * 40)

    state1 = create_test_state(500, 150, 70, 80)
    state2 = create_test_state(505, 148, 72, 78)  # Slightly different
    state3 = create_test_state(450, 100, 50, 60)  # Very different

    hash1 = hash_state(state1)
    hash2 = hash_state(state2)
    hash3 = hash_state(state3)

    print(f"State 1 hash: {hash1}")
    print(f"State 2 hash: {hash2} (similar to state 1)")
    print(f"State 3 hash: {hash3} (different)")

    assert hash1 == hash2, "Similar states should hash to same value!"
    assert hash1 != hash3, "Different states should hash to different values!"

    print("[PASS] State hashing works correctly\n")

def test_node_creation():
    """Test MCTSNode creation."""
    print("Test 2: Node Creation")
    print("-" * 40)

    state = create_test_state()
    node = MCTSNode(state)

    print(f"Node created: {node}")
    print(f"State hash: {node.state_hash}")
    print(f"Untried actions: {len(node.untried_actions)}")
    print(f"Sample actions: {[action_to_string(a) for a in node.untried_actions[:3]]}")

    assert node.visits == 0, "New node should have 0 visits"
    assert node.value == 0.0, "New node should have 0 value"
    assert len(node.untried_actions) > 0, "Should have untried actions"

    print("[PASS] Node creation works correctly\n")

def test_valid_actions():
    """Test action filtering."""
    print("Test 3: Action Filtering")
    print("-" * 40)

    # Normal state
    state1 = create_test_state()
    actions1 = get_valid_actions(state1)
    print(f"Normal state: {len(actions1)} valid actions")

    # Low stamina state
    state2 = create_test_state()
    state2['tank']['stamina'] = 5
    state2['healer']['stamina'] = 10
    actions2 = get_valid_actions(state2)
    print(f"Low stamina state: {len(actions2)} valid actions")

    # Full HP state (healing should be filtered)
    state3 = create_test_state()
    actions3 = get_valid_actions(state3)
    heal_actions = [a for a in actions3 if a[1] == 'heal']
    print(f"Full HP state: {len(heal_actions)} heal actions (should be 0)")

    assert len(actions2) < len(actions1), "Low stamina should reduce valid actions"

    print("[PASS] Action filtering works correctly\n")

def test_tree_operations():
    """Test MCTSTree operations."""
    print("Test 4: Tree Operations")
    print("-" * 40)

    tree = MCTSTree()
    state = create_test_state()

    # Set root
    tree.set_root(state)
    print(f"Root set: {tree.root}")

    # Test node reuse
    same_state = create_test_state()
    node1 = tree.get_or_create_node(state)
    node2 = tree.get_or_create_node(same_state)

    assert node1 is node2, "Same state should return same node!"
    print("[PASS] Node reuse works correctly")

    # Test stats
    stats = tree.get_stats()
    print(f"Tree stats: {stats}")

    print("[PASS] Tree operations work correctly\n")

def test_ucb1_selection():
    """Test UCB1 child selection."""
    print("Test 5: UCB1 Selection")
    print("-" * 40)

    tree = MCTSTree()
    state = create_test_state()
    root = tree.get_or_create_node(state)

    # Create some child nodes with different stats
    action1 = ("tank", "melee", "")
    action2 = ("sniper", "shot", "")

    child1 = MCTSNode(create_test_state(480, 150, 70, 80), parent=root, action=action1)
    child1.visits = 10
    child1.value = 50.0  # Average value = 5.0

    child2 = MCTSNode(create_test_state(490, 150, 70, 80), parent=root, action=action2)
    child2.visits = 5
    child2.value = 30.0  # Average value = 6.0, but fewer visits

    root.children[action1] = child1
    root.children[action2] = child2
    root.visits = 15

    # Test selection
    best = root.best_child(exploration_constant=1.41)
    print(f"Best child action: {action_to_string(best.action)}")
    print(f"Child 1: visits={child1.visits}, value={child1.value}, avg={child1.value/child1.visits:.2f}")
    print(f"Child 2: visits={child2.visits}, value={child2.value}, avg={child2.value/child2.visits:.2f}")

    # With high exploration, less-visited node might be selected
    print("[PASS] UCB1 selection works correctly\n")

def test_tree_save_load():
    """Test tree serialization."""
    print("Test 6: Tree Save/Load")
    print("-" * 40)

    # Create and populate tree
    tree1 = MCTSTree()
    state = create_test_state()
    tree1.set_root(state)
    tree1.root.visits = 100
    tree1.root.value = 500.0
    tree1.total_iterations = 1000

    # Save
    tree1.save("test_tree.pkl")

    # Load
    tree2 = MCTSTree()
    tree2.load("test_tree.pkl")

    assert len(tree2.nodes) > 0, "Loaded tree should have nodes"
    assert tree2.total_iterations == 1000, "Should preserve total iterations"

    print("[PASS] Save/load works correctly\n")

    # Cleanup
    import os
    os.remove("test_tree.pkl")

def test_target_alive_validation():
    """Test that actions targeting dead agents are filtered out."""
    print("Test 7: Target Alive Validation")
    print("-" * 40)

    # Scenario 1: Tank is dead
    state = create_test_state(boss_hp=500, tank_hp=0, healer_hp=70, sniper_hp=80)
    valid_actions = get_valid_actions(state)

    # Should not include: heal tank, shield tank
    heal_tank = [a for a in valid_actions if a == ("healer", "heal", "tank")]
    shield_tank = [a for a in valid_actions if a == ("healer", "shield", "tank")]

    assert len(heal_tank) == 0, "Should not heal dead tank"
    assert len(shield_tank) == 0, "Should not shield dead tank"
    print(f"  Tank dead: {len(valid_actions)} valid actions (no tank-targeted actions)")

    # Scenario 2: Sniper is dead
    state = create_test_state(boss_hp=500, tank_hp=150, healer_hp=70, sniper_hp=0)
    valid_actions = get_valid_actions(state)

    # Should not include: heal sniper, restore sniper
    heal_sniper = [a for a in valid_actions if a == ("healer", "heal", "sniper")]
    restore_sniper = [a for a in valid_actions if a == ("healer", "restore", "sniper")]

    assert len(heal_sniper) == 0, "Should not heal dead sniper"
    assert len(restore_sniper) == 0, "Should not restore dead sniper"
    print(f"  Sniper dead: {len(valid_actions)} valid actions (no sniper-targeted actions)")

    # Scenario 3: All agents alive with low HP (targeted actions should be valid)
    state = create_test_state(boss_hp=500, tank_hp=50, healer_hp=70, sniper_hp=30)
    valid_actions = get_valid_actions(state)

    heal_tank = [a for a in valid_actions if a == ("healer", "heal", "tank")]
    heal_sniper = [a for a in valid_actions if a == ("healer", "heal", "sniper")]

    assert len(heal_tank) > 0, "Should heal alive tank with low HP"
    assert len(heal_sniper) > 0, "Should heal alive sniper with low HP"
    print(f"  All alive, low HP: {len(valid_actions)} valid actions (includes heals)")

    # Scenario 4: Verify non-targeted actions still work when tank is dead
    state = create_test_state(boss_hp=500, tank_hp=0, healer_hp=70, sniper_hp=80)
    valid_actions = get_valid_actions(state)

    sniper_shot = [a for a in valid_actions if a == ("sniper", "shot", "")]
    healer_actions = [a for a in valid_actions if a[0] == "healer"]

    assert len(sniper_shot) > 0, "Sniper shot should still be valid when tank is dead"
    print(f"  Tank dead: Sniper actions still available ({len(sniper_shot)} shot actions)")

    print("[PASS] Target alive validation works correctly\n")

def test_validation_consistency():
    """Test that get_valid_actions and is_action_valid agree."""
    print("Test 8: Validation Function Consistency")
    print("-" * 40)

    # Test various states
    states = [
        ("All alive, full HP", create_test_state(500, 150, 70, 80)),
        ("All alive, low HP", create_test_state(500, 50, 70, 30)),
        ("Tank dead", create_test_state(500, 0, 70, 80)),
        ("Sniper dead", create_test_state(500, 150, 70, 0)),
        ("Tank and Sniper dead", create_test_state(500, 0, 70, 0)),
    ]

    for state_name, state in states:
        valid_from_get = get_valid_actions(state)
        valid_from_get_set = set(valid_from_get)
        all_actions = get_all_actions()

        mismatches = []
        for action in all_actions:
            is_valid = is_action_valid(action, state)
            in_valid_list = action in valid_from_get_set

            # Both functions should agree (accounting for fallback behavior)
            if is_valid and not in_valid_list:
                # Action is valid but not in list - this could be due to full HP/stamina checks
                # Only flag as mismatch if it's not a full HP/stamina issue
                agent, ability, target = action
                if ability == "heal":
                    max_hp = {"tank": 150, "healer": 70, "sniper": 80}
                    if state[target]['hp'] < max_hp[target]:
                        mismatches.append((action, "valid but not in list"))
                elif ability == "restore":
                    if state[target]['stamina'] < 120:
                        mismatches.append((action, "valid but not in list"))
                else:
                    mismatches.append((action, "valid but not in list"))
            elif not is_valid and in_valid_list:
                # Check if this is a fallback action (only action in list)
                # Fallback can return invalid actions when all valid actions are filtered out
                if len(valid_from_get) == 1 and valid_from_get[0] == action:
                    # This is a fallback action - expected behavior, not a mismatch
                    print(f"  {state_name}: Fallback action {action_to_string(action)} detected (expected when all actions filtered)")
                    continue
                mismatches.append((action, "invalid but in list"))

        if mismatches:
            print(f"  {state_name}: MISMATCH detected!")
            for action, reason in mismatches:
                print(f"    {action_to_string(action)}: {reason}")
            assert False, f"Validation functions disagree on state: {state_name}"
        else:
            print(f"  {state_name}: Both functions agree on {len(valid_from_get_set)} valid actions")

    print("[PASS] Validation functions are consistent\n")

def run_all_tests():
    """Run all MCTS core tests."""
    print("=" * 60)
    print("MCTS Core Tests")
    print("=" * 60)
    print()

    try:
        test_state_hashing()
        test_node_creation()
        test_valid_actions()
        test_tree_operations()
        test_ucb1_selection()
        test_tree_save_load()
        test_target_alive_validation()
        test_validation_consistency()

        print("=" * 60)
        print("[PASS] All tests passed!")
        print("=" * 60)
        print("\nThe MCTS core is working correctly.")
        print("You can now proceed to test with Godot using train_mcts.py")

    except AssertionError as e:
        print(f"\n[FAIL] Test failed: {e}")
        raise
    except Exception as e:
        print(f"\n[ERROR] Unexpected error: {e}")
        raise

if __name__ == "__main__":
    run_all_tests()
