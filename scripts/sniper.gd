extends Agent
class_name Sniper

var is_positioning: bool = false
var is_shooting: bool = false
var target: Node2D = null
var nav_update_timer: float = 0.0
var last_target_position: Vector2 = Vector2.ZERO
var nav_update_cooldown: float = 0.3
var is_using_power_shot: bool = false
var is_using_crippling_shot: bool = false
var has_shield: bool = false
var shield_timer: float = 0.0

func _ready():
	max_health = 80
	health = 80
	max_stamina = 120
	stamina = 120
	speed = 100.0
	super._ready()
	add_to_group("sniper")

func _physics_process(delta):
	# Regenerate stamina (from base class)
	if stamina < max_stamina:
		stamina += stamina_regen_rate * delta

	# Handle shield timer
	if has_shield:
		shield_timer -= delta
		if shield_timer <= 0:
			has_shield = false
			print(name, ": Shield expired")

	# Handle keybind for sniper shot
	if Input.is_action_just_pressed("ui_focus_next") or Input.is_key_pressed(KEY_Z):
		if not is_shooting and not is_positioning:
			attempt_sniper_shot()
	# New abilities
	elif Input.is_key_pressed(KEY_KP_7):
		if not is_using_crippling_shot and not is_positioning:
			attempt_crippling_shot()
	elif Input.is_key_pressed(KEY_KP_8):
		if not is_using_power_shot and not is_positioning:
			attempt_power_shot()

	# Movement handling
	if is_positioning and target:
		position_for_shot(delta)
	elif not nav_agent.is_navigation_finished():
		var next_pos = nav_agent.get_next_path_position()
		var direction = (next_pos - global_position).normalized()
		var desired_velocity = direction * speed
		nav_agent.set_velocity(desired_velocity)
	else:
		velocity = Vector2.ZERO

	# Always call move_and_slide once per frame
	move_and_slide()

func _on_velocity_computed(safe_velocity: Vector2):
	velocity = safe_velocity

func attempt_sniper_shot():
	# Find the boss
	var boss = get_tree().get_first_node_in_group("boss")
	if not boss:
		print(name, ": No boss found!")
		return
	
	target = boss
	is_positioning = true
	print(name, ": Moving into position to shoot boss")

func position_for_shot(delta: float):
	if not target or not is_instance_valid(target):
		is_positioning = false
		is_shooting = false
		return

	nav_update_timer += delta

	var desired_distance = 250.0
	var current_distance = global_position.distance_to(target.global_position)
	var good_position_tolerance = 50.0  # Accept position if within this range
	var reposition_threshold = 70.0  # Only recalculate if outside this range

	# Check if in good position
	if abs(current_distance - desired_distance) < good_position_tolerance:
		# In good position, stop moving and take the shot
		is_positioning = false
		velocity = Vector2.ZERO
		nav_agent.set_velocity(Vector2.ZERO)
		execute_shot()
		return

	# Only reposition if significantly out of position
	var out_of_position = abs(current_distance - desired_distance) > reposition_threshold
	var target_moved = last_target_position.distance_to(target.global_position) > 30.0
	var should_update = nav_update_timer >= nav_update_cooldown and (out_of_position or (nav_agent.is_navigation_finished() and target_moved))

	if should_update:
		# Move to position
		var dir_away = (global_position - target.global_position).normalized()
		var target_point = target.global_position + (dir_away * desired_distance)

		if nav_agent:
			nav_agent.target_position = target_point
			last_target_position = target.global_position
			nav_update_timer = 0.0

	if nav_agent and not nav_agent.is_navigation_finished():
		var next_path_pos = nav_agent.get_next_path_position()
		var desired_velocity = (next_path_pos - global_position).normalized() * speed
		nav_agent.set_velocity(desired_velocity)
	else:
		# Stop if navigation finished
		velocity = Vector2.ZERO

func execute_shot():
	is_shooting = true
	velocity = Vector2.ZERO
	
	print(name, ": Taking the shot!")
	
	if target and is_instance_valid(target) and target.has_method("take_damage"):
		target.take_damage(45)
		print(name, " dealt 45 sniper damage to ", target.name)
	
	await get_tree().create_timer(1.5).timeout
	is_shooting = false

func take_damage(amount: int):
	var final_damage = amount
	
	# Apply shield reduction
	if has_shield:
		final_damage = int(final_damage * 0.5)
		print(name, ": Shield reduced damage to ", final_damage)
	
	super.take_damage(final_damage)

func apply_shield():
	has_shield = true
	shield_timer = 6.0
	print(name, ": Shield active!")

func attempt_crippling_shot():
	var boss = get_tree().get_first_node_in_group("boss")
	if not boss:
		print(name, ": No boss found!")
		return
	
	if stamina < 18:
		print(name, ": Not enough stamina for crippling shot!")
		return
	
	is_using_crippling_shot = true
	stamina -= 18
	velocity = Vector2.ZERO
	
	print(name, ": Firing crippling shot!")
	
	await get_tree().create_timer(1.0).timeout
	
	if boss and is_instance_valid(boss):
		if boss.has_method("take_damage"):
			boss.take_damage(25)
		if boss.has_method("apply_slow"):
			boss.apply_slow()
			print(name, " dealt 25 damage and slowed the boss (50% speed for 8s)")
	
	is_using_crippling_shot = false

func attempt_power_shot():
	var boss = get_tree().get_first_node_in_group("boss")
	if not boss:
		print(name, ": No boss found!")
		return
	
	if stamina < 35:
		print(name, ": Not enough stamina for power shot!")
		return
	
	is_using_power_shot = true
	stamina -= 35
	velocity = Vector2.ZERO
	
	print(name, ": Charging power shot...")
	
	await get_tree().create_timer(2.0).timeout
	
	if boss and is_instance_valid(boss) and boss.has_method("take_damage"):
		boss.take_damage(85)
		print(name, " dealt MASSIVE 85 damage with power shot!")
	
	is_using_power_shot = false

# MCTS Wrapper Methods
func use_crippling_shot():
	if not is_using_crippling_shot:
		attempt_crippling_shot()

func use_power_shot():
	if not is_using_power_shot:
		attempt_power_shot()
