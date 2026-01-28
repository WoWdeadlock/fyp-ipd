extends Node

## Test script for MCTS Shadow Simulation System.
## Attach this to any node in your scene or run standalone.

func _ready():
	# Wait for scene to fully initialize
	await get_tree().process_frame
	await get_tree().process_frame

	print("\n" + "=".repeat(60))
	print("MCTS SHADOW SIMULATION TEST SUITE")
	print("=".repeat(60) + "\n")

	var all_passed = true

	all_passed = test_shadow_agent() and all_passed
	all_passed = test_shadow_boss() and all_passed
	all_passed = test_shadow_state_creation() and all_passed
	all_passed = test_clone_independence() and all_passed
	all_passed = test_step_function() and all_passed
	all_passed = test_legal_actions() and all_passed
	all_passed = test_damage_calculation() and all_passed
	all_passed = test_terminal_conditions() and all_passed
	all_passed = test_reward_calculator() and all_passed
	all_passed = test_mcts_search() and all_passed

	print("\n" + "=".repeat(60))
	if all_passed:
		print("ALL TESTS PASSED!")
	else:
		print("SOME TESTS FAILED - Check output above")
	print("=".repeat(60) + "\n")


func test_shadow_agent() -> bool:
	print("--- Test: ShadowAgent Creation ---")

	var tank = ShadowAgent.create_tank()
	var healer = ShadowAgent.create_healer()
	var sniper = ShadowAgent.create_sniper()

	var passed = true

	# Check tank stats
	if tank.max_hp != 150 or tank.max_stamina != 80:
		print("  FAIL: Tank stats incorrect")
		passed = false

	# Check healer stats
	if healer.max_hp != 100 or healer.max_stamina != 150:
		print("  FAIL: Healer stats incorrect")
		passed = false

	# Check sniper stats
	if sniper.max_hp != 80 or sniper.max_stamina != 120:
		print("  FAIL: Sniper stats incorrect")
		passed = false

	if passed:
		print("  PASS: All agent stats correct")

	return passed


func test_shadow_boss() -> bool:
	print("--- Test: ShadowBoss Creation ---")

	var boss = ShadowBoss.create()
	var passed = true

	if boss.hp != 600 or boss.max_hp != 600:
		print("  FAIL: Boss HP incorrect")
		passed = false

	if boss.RANGED_DAMAGE != 25 or boss.MELEE_DAMAGE != 45:
		print("  FAIL: Boss damage values incorrect (expected 25 ranged, 45 melee)")
		passed = false

	if passed:
		print("  PASS: Boss stats correct (buffed: 45 melee, 25 ranged)")

	return passed


func test_shadow_state_creation() -> bool:
	print("--- Test: ShadowState Creation ---")

	var state = ShadowState.create_initial()
	var passed = true

	if state.agents.size() != 3:
		print("  FAIL: Expected 3 agents, got ", state.agents.size())
		passed = false

	if state.boss == null:
		print("  FAIL: Boss is null")
		passed = false

	if state.micro_turn_index != 0:
		print("  FAIL: Initial micro_turn should be 0")
		passed = false

	if state.is_terminal():
		print("  FAIL: Initial state should not be terminal")
		passed = false

	if passed:
		print("  PASS: Initial state created correctly")
		print("    Tank: ", state.agents[0].hp, "/", state.agents[0].max_hp, " HP")
		print("    Healer: ", state.agents[1].hp, "/", state.agents[1].max_hp, " HP")
		print("    Sniper: ", state.agents[2].hp, "/", state.agents[2].max_hp, " HP")
		print("    Boss: ", state.boss.hp, "/", state.boss.max_hp, " HP")

	return passed


func test_clone_independence() -> bool:
	print("--- Test: Clone Independence ---")

	var state = ShadowState.create_initial()
	var clone = state.clone()
	var passed = true

	# Modify clone
	clone.agents[0].hp = 50
	clone.boss.hp = 100
	clone.current_tick = 99

	# Original should be unchanged
	if state.agents[0].hp != 150:
		print("  FAIL: Original tank HP changed after clone modification")
		passed = false

	if state.boss.hp != 600:
		print("  FAIL: Original boss HP changed after clone modification")
		passed = false

	if state.current_tick != 0:
		print("  FAIL: Original tick changed after clone modification")
		passed = false

	if passed:
		print("  PASS: Clone is independent of original")

	return passed


func test_step_function() -> bool:
	print("--- Test: Step Function ---")

	var state = ShadowState.create_initial()
	var passed = true

	# Tank melee (micro-turn 0)
	var action1 = {"agent": "tank", "ability": "melee"}
	var state2 = state.step(action1)

	if state2.boss.hp != 565:  # 600 - 35
		print("  FAIL: Tank melee didn't deal 35 damage. Boss HP: ", state2.boss.hp)
		passed = false

	if state2.micro_turn_index != 1:
		print("  FAIL: Micro-turn didn't advance to 1")
		passed = false

	# Original state unchanged
	if state.boss.hp != 600:
		print("  FAIL: Original state was modified by step()")
		passed = false

	# Healer heal tank (micro-turn 1) - tank at full HP so no effect
	var action2 = {"agent": "healer", "ability": "wait"}
	var state3 = state2.step(action2)

	if state3.micro_turn_index != 2:
		print("  FAIL: Micro-turn didn't advance to 2")
		passed = false

	# Sniper shot (micro-turn 2) - completes full turn
	var action3 = {"agent": "sniper", "ability": "shot"}
	var state4 = state3.step(action3)

	if state4.boss.hp != 520:  # 565 - 45
		print("  FAIL: Sniper shot didn't deal 45 damage. Boss HP: ", state4.boss.hp)
		passed = false

	if state4.micro_turn_index != 0:
		print("  FAIL: Micro-turn didn't reset to 0 after full turn")
		passed = false

	if state4.current_tick != 1:
		print("  FAIL: Tick didn't advance after full turn")
		passed = false

	if passed:
		print("  PASS: Step function works correctly")
		print("    Damage dealt: 80 (35 melee + 45 shot)")
		print("    Boss HP: 600 -> 520")

	return passed


func test_legal_actions() -> bool:
	print("--- Test: Legal Actions ---")

	var state = ShadowState.create_initial()
	var passed = true

	# Tank actions (micro-turn 0)
	var tank_actions = ActionGenerator.get_legal_actions(state)

	# Should have: wait, melee, taunt, defensive
	if tank_actions.size() != 4:
		print("  FAIL: Expected 4 tank actions, got ", tank_actions.size())
		print("    Actions: ", tank_actions)
		passed = false

	# Drain tank stamina
	state.agents[0].stamina = 5
	var limited_actions = ActionGenerator.get_legal_actions(state)

	# Should have: wait, melee (taunt needs 15, defensive needs 10)
	if limited_actions.size() != 2:
		print("  FAIL: Expected 2 actions with low stamina, got ", limited_actions.size())
		print("    Actions: ", limited_actions)
		passed = false

	# Test dead agent
	state.agents[0].hp = 0
	var dead_actions = ActionGenerator.get_legal_actions(state)

	if dead_actions.size() != 1 or dead_actions[0].ability != "wait":
		print("  FAIL: Dead agent should only have 'wait' action")
		passed = false

	if passed:
		print("  PASS: Legal action generation correct")
		print("    Full stamina tank: 4 actions")
		print("    Low stamina tank: 2 actions")
		print("    Dead agent: 1 action (wait)")

	return passed


func test_damage_calculation() -> bool:
	print("--- Test: Damage Calculation ---")

	var agent = ShadowAgent.create_tank()
	var passed = true

	# No buffs - full damage
	agent.take_damage(100)
	if agent.hp != 50:
		print("  FAIL: No-buff damage incorrect. HP: ", agent.hp)
		passed = false

	# Reset and test defensive stance (70% reduction = 30% damage)
	agent.hp = 150
	agent.defensive_stance_ticks = 10
	agent.take_damage(100)
	if agent.hp != 120:  # 150 - 30
		print("  FAIL: Defensive stance damage incorrect. HP: ", agent.hp, " (expected 120)")
		passed = false

	# Reset and test shield (50% reduction)
	agent.hp = 150
	agent.defensive_stance_ticks = 0
	agent.shield_ticks = 10
	agent.take_damage(100)
	if agent.hp != 100:  # 150 - 50
		print("  FAIL: Shield damage incorrect. HP: ", agent.hp, " (expected 100)")
		passed = false

	# Reset and test both (30% * 50% = 15% damage)
	agent.hp = 150
	agent.defensive_stance_ticks = 10
	agent.shield_ticks = 10
	agent.take_damage(100)
	if agent.hp != 135:  # 150 - 15
		print("  FAIL: Stacked reduction incorrect. HP: ", agent.hp, " (expected 135)")
		passed = false

	if passed:
		print("  PASS: Damage calculation correct")
		print("    No buff: 100 damage")
		print("    Defensive (70% reduction): 30 damage")
		print("    Shield (50% reduction): 50 damage")
		print("    Both stacked: 15 damage")

	return passed


func test_terminal_conditions() -> bool:
	print("--- Test: Terminal Conditions ---")

	var state = ShadowState.create_initial()
	var passed = true

	# Normal state - not terminal
	if state.is_terminal():
		print("  FAIL: Initial state should not be terminal")
		passed = false

	# Victory - boss dead
	state.boss.hp = 0
	if not state.is_terminal() or state.get_outcome() != "victory":
		print("  FAIL: Boss dead should be victory")
		passed = false

	# Reset boss, kill all agents
	state.boss.hp = 600
	state.agents[0].hp = 0
	state.agents[1].hp = 0
	state.agents[2].hp = 0
	if not state.is_terminal() or state.get_outcome() != "defeat":
		print("  FAIL: All agents dead should be defeat")
		passed = false

	# Only healer alive - unwinnable
	state.agents[0].hp = 0
	state.agents[1].hp = 100
	state.agents[2].hp = 0
	if not state.is_terminal() or state.get_outcome() != "defeat":
		print("  FAIL: Only healer alive should be defeat (unwinnable)")
		passed = false

	if passed:
		print("  PASS: Terminal conditions correct")
		print("    Boss dead: Victory")
		print("    All agents dead: Defeat")
		print("    Only healer alive: Defeat (unwinnable)")

	return passed


func test_reward_calculator() -> bool:
	print("--- Test: Reward Calculator ---")

	var passed = true

	# Victory state (at tick 0 gets speed bonus of 100)
	var win_state = ShadowState.create_initial()
	win_state.boss.hp = 0
	var win_reward = RewardCalculator.evaluate(win_state)
	# Base 1000 + speed bonus (100 - current_tick) = 1100 at tick 0
	if win_reward < 1000.0:
		print("  FAIL: Victory reward should be >= 1000, got ", win_reward)
		passed = false

	# Defeat state (boss at full HP = 0 damage mitigation)
	var lose_state = ShadowState.create_initial()
	lose_state.agents[0].hp = 0
	lose_state.agents[1].hp = 0
	lose_state.agents[2].hp = 0
	var lose_reward = RewardCalculator.evaluate(lose_state)
	# Base -1000 + damage mitigation (0 if boss at full HP)
	if lose_reward > -800.0:
		print("  FAIL: Defeat reward should be <= -800, got ", lose_reward)
		passed = false

	# Mid-game state - should be positive (agents alive, boss damaged)
	var mid_state = ShadowState.create_initial()
	mid_state.boss.hp = 300  # Half health
	var mid_reward = RewardCalculator.evaluate(mid_state)
	if mid_reward <= 0:
		print("  FAIL: Mid-game with boss half-dead should be positive, got ", mid_reward)
		passed = false

	# Normalization
	var normalized = RewardCalculator.normalize_reward(500.0)
	if normalized < 0.5 or normalized > 1.0:
		print("  FAIL: Normalized reward out of range: ", normalized)
		passed = false

	if passed:
		print("  PASS: Reward calculator works")
		print("    Victory (tick 0): ", win_reward, " (1000 base + speed bonus)")
		print("    Defeat: ", lose_reward)
		print("    Mid-game (boss at 50%): ", mid_reward)

	return passed


func test_mcts_search() -> bool:
	print("--- Test: MCTS Search ---")

	var state = ShadowState.create_initial()
	var passed = true

	# Run small search
	var search = MCTSSearch.new(state, 100)  # 100 iterations for quick test
	search.set_seed(42)  # Deterministic

	var start_time = Time.get_ticks_msec()
	var result = search.search_with_stats()
	var elapsed = Time.get_ticks_msec() - start_time

	if result.best_action.is_empty():
		print("  FAIL: No best action returned")
		passed = false

	if result.root_visits != 100:
		print("  FAIL: Expected 100 root visits, got ", result.root_visits)
		passed = false

	# Best action should be for tank (micro-turn 0)
	if result.best_action.get("agent") != "tank":
		print("  FAIL: First action should be for tank, got ", result.best_action.get("agent"))
		passed = false

	if passed:
		print("  PASS: MCTS search completed in ", elapsed, "ms")
		print("    Best action: ", result.best_action)
		print("    Root visits: ", result.root_visits)
		print("    Total nodes: ", result.total_nodes)

		print("    Top children:")
		for i in range(mini(3, result.children_stats.size())):
			var child = result.children_stats[i]
			print("      ", child.action.ability, ": ", child.visits, " visits, avg=", snapped(child.avg_reward, 0.01))

	return passed
