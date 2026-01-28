extends Node2D
class_name Boss

enum State { IDLE, RANGED, MELEE, BUSY } 
var current_state: State = State.IDLE

@onready var boss_vision: Area2D = $Area2D
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var health_bar: TextureProgressBar = $HealthBar
@onready var stamina_bar: TextureProgressBar = $StaminaBar

var movement_speed: float = 120.0
var velocity: Vector2 = Vector2.ZERO
var current_target: Node2D = null
var nav_update_timer: float = 0.0
var last_target_position: Vector2 = Vector2.ZERO
var nav_update_cooldown: float = 0.35
var is_in_position: bool = false
var is_slowed: bool = false
var slow_timer: float = 0.0
var forced_target: Node2D = null
var forced_target_timer: float = 0.0

@export var max_health: int = 650
@export var max_stamina: int = 300

@export var health: int = 650:
	set(value):
		health = clamp(value, 0, max_health)
		if health_bar:
			health_bar.value = health
			
@export var stamina: int = 300:
	set(value):
		stamina = clamp(value, 0, max_stamina)
		if stamina_bar:
			stamina_bar.value = stamina

func _ready():
	add_to_group("boss")
	health_bar.max_value = max_health
	health_bar.value = health
	
	stamina_bar.max_value = max_stamina
	stamina_bar.value = stamina
	
	# Enable avoidance
	nav_agent.avoidance_enabled = true
	nav_agent.radius = 35.0
	nav_agent.velocity_computed.connect(_on_velocity_computed)

func _on_velocity_computed(safe_velocity: Vector2):
	velocity = safe_velocity

func _physics_process(_delta: float):
	# Regenerate stamina
	if stamina < max_stamina:
		stamina += 15.0 * _delta
	
	# Handle slow debuff
	if is_slowed:
		slow_timer -= _delta
		if slow_timer <= 0:
			is_slowed = false
			movement_speed = 120.0
			print("Boss: Slow effect ended")
	
	# Handle forced target (taunt)
	if forced_target:
		forced_target_timer -= _delta
		if forced_target_timer <= 0 or not is_instance_valid(forced_target):
			forced_target = null
			print("Boss: Taunt effect ended")
	
	match current_state:
		State.IDLE:
			process_idle()
		State.RANGED:
			if current_target:
				execute_ranged_attack(_delta)
		State.MELEE:
			if current_target:
				attack_target(current_target, _delta)
		State.BUSY:
			pass

	# Apply velocity to position (Boss is Node2D, not CharacterBody2D)
	global_position += velocity * _delta

func execute_ranged_attack(delta: float):
	if not current_target or not is_instance_valid(current_target):
		current_state = State.IDLE
		is_in_position = false
		return

	nav_update_timer += delta

	var desired_distance = 220.0
	var good_position_tolerance = 60.0  # Accept position within this range
	var reposition_threshold = 80.0  # Only recalculate if beyond this range
	var current_distance = global_position.distance_to(current_target.global_position)

	# If target gets too close, switch to melee instead of backing away
	if current_distance < 100.0:
		print("Target too close! Switching to MELEE")
		current_state = State.MELEE
		is_in_position = false
		return

	# Check if in good ranged position
	if abs(current_distance - desired_distance) <= good_position_tolerance:
		# In good position, stop and attack
		velocity = Vector2.ZERO
		nav_agent.set_velocity(Vector2.ZERO)
		current_state = State.BUSY
		print("State: RANGED - Drawing bow")

		if current_target.has_method("take_damage"):
			current_target.take_damage(20)
			print("Boss dealt 20 ranged damage to ", current_target.name)

		is_in_position = false
		await get_tree().create_timer(2.0).timeout

		# Check if boss is still alive after the await
		if not is_instance_valid(self) or health <= 0:
			return

		current_state = State.IDLE
		return

	# Need to reposition - only if significantly out of position
	var out_of_position = abs(current_distance - desired_distance) > reposition_threshold
	var target_moved = last_target_position.distance_to(current_target.global_position) > 40.0
	var should_update = nav_update_timer >= nav_update_cooldown and (out_of_position or (nav_agent.is_navigation_finished() and target_moved))

	if should_update:
		is_in_position = false
		var dir_away = (global_position - current_target.global_position).normalized()
		var target_point = current_target.global_position + (dir_away * desired_distance)

		if nav_agent:
			nav_agent.target_position = target_point
			last_target_position = current_target.global_position
			nav_update_timer = 0.0

	if nav_agent and not nav_agent.is_navigation_finished():
		var next_path_pos = nav_agent.get_next_path_position()
		var desired_velocity = (next_path_pos - global_position).normalized() * movement_speed
		nav_agent.set_velocity(desired_velocity)
	else:
		# Stop moving if navigation finished
		velocity = Vector2.ZERO

func execute_melee_attack():
	current_state = State.BUSY
	print("State: MELEE - Unsheathing sword")

	await get_tree().create_timer(1.0).timeout

	# Check if boss is still alive after the await
	if not is_instance_valid(self) or health <= 0:
		return

	current_state = State.IDLE

func attack_target(enemy: Node2D, delta: float) -> void:
	if not enemy or not is_instance_valid(enemy):
		current_state = State.IDLE
		return

	nav_update_timer += delta

	var attack_range = 70.0  # Attack when within this distance
	var ideal_distance = 40.0  # Try to get this close
	var reposition_threshold = 85.0  # Only recalculate path if beyond this
	var current_distance = global_position.distance_to(enemy.global_position)

	# Check if in melee range
	if current_distance <= attack_range:
		# In range, stop and execute attack
		velocity = Vector2.ZERO
		nav_agent.set_velocity(Vector2.ZERO)
		current_state = State.BUSY
		# Deal melee damage to the target
		if enemy and is_instance_valid(enemy) and enemy.has_method("take_damage"):
			enemy.take_damage(30)
			print("Boss dealt 30 damage to ", enemy.name)
		await get_tree().create_timer(1.0).timeout

		# Check if boss is still alive after the await
		if not is_instance_valid(self) or health <= 0:
			return

		current_state = State.IDLE
	else:
		# Only update navigation if far from target or target moved significantly
		var too_far = current_distance > reposition_threshold
		var target_moved = last_target_position.distance_to(enemy.global_position) > 50.0
		var should_update = nav_update_timer >= nav_update_cooldown and (too_far or (nav_agent.is_navigation_finished() and target_moved))

		if should_update:
			# Move to ideal distance
			var dir_to_enemy = (enemy.global_position - global_position).normalized()
			var target_point = enemy.global_position - (dir_to_enemy * ideal_distance)

			if nav_agent:
				nav_agent.target_position = target_point
				last_target_position = enemy.global_position
				nav_update_timer = 0.0

		if nav_agent and not nav_agent.is_navigation_finished():
			var next_path_pos = nav_agent.get_next_path_position()
			var desired_velocity = (next_path_pos - global_position).normalized() * movement_speed
			nav_agent.set_velocity(desired_velocity)
		else:
			# Stop if navigation finished
			velocity = Vector2.ZERO

func process_idle():
	# If taunted, always target the forced target
	if forced_target and is_instance_valid(forced_target):
		current_target = forced_target
		_decide_attack_state(forced_target)
		return
	
	var bodies = boss_vision.get_overlapping_bodies()
	var candidates = []

	# AGGRESSIVE targeting logic (matches virtual_simulator.py)
	for body in bodies:
		if body is Agent:
			var distance = global_position.distance_to(body.global_position)

			# Base score: lower HP = MUCH higher priority
			var hp_ratio = float(body.health) / float(body.max_health)
			var hp_score = (1.0 - hp_ratio) * 100.0  # 0-100 points, low HP favored

			# Distance penalty (prefer closer targets)
			var distance_penalty = (distance / 100.0) * 5.0

			# Role priority: Moderate healer priority (nerfed for balance)
			var role_bonus = 0.0
			if body.is_in_group("healer"):
				role_bonus = 25.0  # Healer is priority target (reduced from 50)
			elif body.is_in_group("sniper"):
				role_bonus = 15.0  # Sniper second priority (high damage)
			# Tank gets no bonus (lowest priority)

			# Lower score = higher priority
			var score = distance_penalty - hp_score - role_bonus
			candidates.append({"target": body, "score": score})

	if candidates.size() == 0:
		return

	candidates.sort_custom(func(a, b): return a.score < b.score)

	var top_candidates = candidates.slice(0, min(candidates.size(), 3))

	var best_target = null
	var roll = randf()

	# AGGRESSIVE probabilistic selection (heavily favor best target)
	if top_candidates.size() == 1:
		best_target = top_candidates[0].target
	elif top_candidates.size() == 2:
		best_target = top_candidates[0].target if roll < 0.85 else top_candidates[1].target  # 85% best
	else:
		if roll < 0.75:  # 75% best target
			best_target = top_candidates[0].target
		elif roll < 0.95:  # 20% second best
			best_target = top_candidates[1].target
		else:  # 5% worst target
			best_target = top_candidates[2].target
	current_target = best_target
	_decide_attack_state(best_target)

func take_damage(amount: int):
	health -= amount
	if health <= 0:
		queue_free()
		print("Boss has been defeated!")

func _decide_attack_state(target):
	var dist_to_target = global_position.distance_to(target.global_position)
	var roll = randf() 

	if dist_to_target > 150:
		current_state = State.RANGED if roll < 0.55 else State.MELEE
	else:
		current_state = State.MELEE 
			
	print("Targeting: ", target.name, " | State Selected: ", current_state)

func force_target(target: Node2D):
	forced_target = target
	forced_target_timer = 5.0
	current_target = target
	current_state = State.IDLE
	print("Boss: Taunted! Forced to target ", target.name)

func apply_slow():
	is_slowed = true
	slow_timer = 8.0
	movement_speed = 60.0
	print("Boss: Slowed! Movement speed reduced by 50%")
