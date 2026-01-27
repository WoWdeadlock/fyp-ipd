import json
import time
from pathlib import Path

# Godot user:// directory location
# Replace "YourProjectName" with your actual project name from project.godot
GODOT_USER = Path.home() / "C:/Users/User/AppData/Roaming/Godot/app_userdata/IPD"  # Using "v1" based on your working directory
COMMAND_FILE = GODOT_USER / "mcts_command.json"
STATE_FILE = GODOT_USER / "mcts_state.json"


def wait_for_state(timeout=5.0):
	"""Wait for state file to appear"""
	start = time.time()
	while not STATE_FILE.exists():
		if time.time() - start > timeout:
			raise TimeoutError("Timeout waiting for Godot response")
		time.sleep(0.01)

def get_state():
	"""Get current game state"""
	# Clean up any old state file
	if STATE_FILE.exists():
		STATE_FILE.unlink()

	# Write command
	COMMAND_FILE.write_text(json.dumps({"type": "get_state"}))

	# Wait for response
	wait_for_state()
	state = json.loads(STATE_FILE.read_text())
	STATE_FILE.unlink()

	return state

def execute_action(agent, ability, target=""):
	"""Execute an action and get updated state"""
	# Clean up any old state file
	if STATE_FILE.exists():
		STATE_FILE.unlink()

	cmd = {
		"type": "execute_action",
		"action": {"agent": agent, "ability": ability, "target": target}
	}
	COMMAND_FILE.write_text(json.dumps(cmd))

	# Wait for response
	wait_for_state()
	state = json.loads(STATE_FILE.read_text())
	STATE_FILE.unlink()

	return state

def reset():
	"""Reset the game to initial state"""
	# Clean up any old state file
	if STATE_FILE.exists():
		STATE_FILE.unlink()

	COMMAND_FILE.write_text(json.dumps({"type": "reset"}))

	# Wait for reset to complete and get initial state
	wait_for_state(timeout=3.0)
	state = json.loads(STATE_FILE.read_text())
	STATE_FILE.unlink()

	return state

# ========== Example Usage ==========

def test_basic_operations():
	"""Test basic MCTS operations"""
	print("=== Testing MCTS Bridge ===\n")

	# Test 1: Get initial state
	print("Test 1: Getting initial state...")
	state = get_state()
	print(f"  Tank HP: {state['tank']['hp']}")
	print(f"  Boss HP: {state['boss']['hp']}")
	print(f"  Terminal: {state['is_terminal']}")
	print()

	# Test 2: Execute tank melee attack
	print("Test 2: Tank melee attack...")
	state = execute_action("tank", "melee", "boss")
	print(f"  Action executed")
	time.sleep(2)  # Wait for attack to complete
	state = get_state()
	print(f"  Boss HP after attack: {state['boss']['hp']}")
	print()

	# Test 3: Healer heals tank
	print("Test 3: Healer heals tank...")
	state = execute_action("healer", "heal", "tank")
	time.sleep(1.5)  # Wait for heal cast time
	state = get_state()
	print(f"  Tank HP after heal: {state['tank']['hp']}")
	print()

	# Test 4: Reset
	print("Test 4: Resetting game...")
	state = reset()
	print(f"  Tank HP after reset: {state['tank']['hp']}")
	print(f"  Boss HP after reset: {state['boss']['hp']}")
	print()

	print("=== All Tests Complete ===")

def run_random_episode():
	"""Run a random episode until terminal"""
	import random

	print("=== Running Random Episode ===\n")

	# Reset to start
	state = reset()
	step = 0

	actions = [
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

	while not state["is_terminal"]:
		# Random action
		agent, ability, target = random.choice(actions)
		print(f"Step {step}: {agent}.{ability}({target})")

		state = execute_action(agent, ability, target)
		step += 1

		# Print status every 10 steps
		if step % 10 == 0:
			print(f"  Status - Boss HP: {state['boss']['hp']}, Tank HP: {state['tank']['hp']}")

		time.sleep(0.1)  # Small delay between actions

		# Safety limit
		if step > 500:
			print("  Max steps reached, stopping")
			break

	print(f"\n=== Episode Complete ===")
	print(f"Outcome: {state['outcome']}")
	print(f"Total steps: {step}")

if __name__ == "__main__":
	# Make sure Godot game is running before executing this!

	print("Make sure Godot game is running with grid.tscn scene loaded!\n")
	input("Press Enter when ready...")

	# Run basic tests
	test_basic_operations()

	# Uncomment to run a full random episode
	# run_random_episode()
