extends Node2D

enum State { IDLE, RANGED, MELEE, BUSY } # Added BUSY state
var current_state: State = State.IDLE

@onready var boss_vision: Area2D = $Area2D

func _physics_process(_delta: float):
	match current_state:
		State.IDLE:
			process_idle()
		State.RANGED:
			execute_ranged_attack()
		State.MELEE:
			execute_melee_attack()
		State.BUSY:
			pass

func execute_ranged_attack():
	current_state = State.BUSY
	print("State: RANGED - Drawing bow")
	
	await get_tree().create_timer(2.0).timeout
	
	current_state = State.IDLE

func execute_melee_attack():
	current_state = State.BUSY
	print("State: MELEE - Unsheathing sword")
	
	await get_tree().create_timer(1.0).timeout
	
	current_state = State.IDLE

func process_idle():
	var bodies = boss_vision.get_overlapping_bodies()
	var candidates = []

	for body in bodies:
		if body is Agent:
			var distance = global_position.distance_to(body.global_position)
			var score = (distance * 0.5) + (body.health * 0.5)
			candidates.append({"target": body, "score": score})

	if candidates.size() == 0:
		return

	candidates.sort_custom(func(a, b): return a.score < b.score)

	var top_candidates = candidates.slice(0, min(candidates.size(), 3))
	
	var best_target = null
	var roll = randf()

	if top_candidates.size() == 1:
		best_target = top_candidates[0].target
	elif top_candidates.size() == 2:
		best_target = top_candidates[0].target if roll < 0.7 else top_candidates[1].target
	else:
		if roll < 0.6:
			best_target = top_candidates[0].target
		elif roll < 0.9:
			best_target = top_candidates[1].target
		else:
			best_target = top_candidates[2].target
	_decide_attack_state(best_target)

func _decide_attack_state(target):
	var dist_to_target = global_position.distance_to(target.global_position)
	var roll = randf() 

	if dist_to_target > 150:
		current_state = State.RANGED if roll < 0.8 else State.MELEE
	else:
		current_state = State.MELEE
			
	print("Targeting: ", target.name, " | State Selected: ", current_state)
