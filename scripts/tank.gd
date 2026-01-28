extends Agent
class_name Tank

var is_attacking: bool = false
var is_moving_to_target: bool = false
var target: Node2D = null
var nav_update_timer: float = 0.0
var last_target_position: Vector2 = Vector2.ZERO
var nav_update_cooldown: float = 0.25
var is_taunting: bool = false
var defensive_stance_active: bool = false
var defensive_stance_timer: float = 0.0
var has_shield: bool = false
var shield_timer: float = 0.0

func _ready():
	max_health = 150
	health = 150
	max_stamina = 80
	stamina = 80
	speed = 90.0
	super._ready()
	add_to_group("tank")

func _physics_process(delta):
	# Regenerate stamina (from base class)
	if stamina < max_stamina:
		stamina += stamina_regen_rate * delta

	# Handle defensive stance timer
	if defensive_stance_active:
		defensive_stance_timer -= delta
		if defensive_stance_timer <= 0:
			defensive_stance_active = false
			print(name, ": Defensive stance ended")

	# Handle shield timer
	if has_shield:
		shield_timer -= delta
		if shield_timer <= 0:
			has_shield = false
			print(name, ": Shield expired")

	# Handle keybind for melee attack
	if Input.is_key_pressed(KEY_V):
		if not is_attacking and not is_moving_to_target:
			attempt_melee_attack()
	# New abilities
	elif Input.is_key_pressed(KEY_KP_4):
		if not is_taunting:
			taunt_boss()
	elif Input.is_key_pressed(KEY_KP_5):
		if not defensive_stance_active:
			activate_defensive_stance()

	# Movement handling
	if is_moving_to_target and target:
		move_to_attack(delta)
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

func attempt_melee_attack():
	# Prevent spam - check if already busy
	if is_attacking or is_moving_to_target or is_taunting:
		return

	# Melee attack is now FREE (no stamina cost)
	# if stamina < 20:
	# 	print(name, ": Not enough stamina to attack!")
	# 	return

	# Find the boss
	var boss = get_tree().get_first_node_in_group("boss")
	if not boss:
		print(name, ": No boss found!")
		return

	target = boss
	is_moving_to_target = true
	print(name, ": Moving in to attack boss")

func move_to_attack(delta: float):
	if not target or not is_instance_valid(target):
		is_moving_to_target = false
		is_attacking = false
		return

	nav_update_timer += delta

	var attack_range = 80.0
	var ideal_distance = 45.0  # Preferred distance to maintain
	var reposition_threshold = 90.0  # Only recalculate if beyond this distance
	var current_distance = global_position.distance_to(target.global_position)

	# Check if in melee range
	if current_distance <= attack_range:
		# In range, stop and execute attack
		is_moving_to_target = false
		velocity = Vector2.ZERO
		nav_agent.set_velocity(Vector2.ZERO)
		execute_melee()
		return

	# Only update navigation if far from target or target moved significantly
	var target_moved = last_target_position.distance_to(target.global_position) > 70.0
	var too_far = current_distance > reposition_threshold
	var should_update = nav_update_timer >= nav_update_cooldown and (too_far or (nav_agent.is_navigation_finished() and target_moved))

	if should_update:
		# Move to ideal distance from target
		var dir_to_target = (target.global_position - global_position).normalized()
		var target_point = target.global_position - (dir_to_target * ideal_distance)

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

func execute_melee():
	is_attacking = true
	velocity = Vector2.ZERO

	# Melee attack is FREE (no stamina cost)
	# stamina -= 20

	print(name, ": Striking with melee attack!")

	if target and is_instance_valid(target) and target.has_method("take_damage"):
		target.take_damage(30)
		print(name, " dealt 30 melee damage to ", target.name)

	await get_tree().create_timer(1.2).timeout

	# Check if tank is still alive after the await
	if not is_instance_valid(self) or health <= 0:
		print(name, ": Melee attack interrupted - tank is dead")
		return

	is_attacking = false

func take_damage(amount: int):
	var final_damage = amount
	
	# Apply defensive stance reduction
	if defensive_stance_active:
		final_damage = int(final_damage * 0.3)
		print(name, ": Defensive stance reduced damage to ", final_damage)
	
	# Apply shield reduction
	if has_shield:
		final_damage = int(final_damage * 0.5)
		print(name, ": Shield reduced damage to ", final_damage)
	
	super.take_damage(final_damage)

func apply_shield():
	has_shield = true
	shield_timer = 6.0
	print(name, ": Shield active!")

func taunt_boss():
	# Prevent spam
	if is_taunting or is_attacking or is_moving_to_target:
		return

	if stamina < 15:
		print(name, ": Not enough stamina to taunt!")
		return

	is_taunting = true
	stamina -= 15
	
	var boss = get_tree().get_first_node_in_group("boss")
	if not boss:
		print(name, ": No boss found to taunt!")
		is_taunting = false
		return
	
	print(name, ": TAUNTING THE BOSS!")
	
	await get_tree().create_timer(0.5).timeout
	
	if boss and is_instance_valid(boss) and boss.has_method("force_target"):
		boss.force_target(self)
		print(name, " forced boss to target tank for 3 seconds")
	
	is_taunting = false

func activate_defensive_stance():
	# Prevent spam and don't reactivate if already active
	if defensive_stance_active or is_attacking or is_moving_to_target or is_taunting:
		return

	if stamina < 10:
		print(name, ": Not enough stamina for defensive stance!")
		return

	stamina -= 10
	defensive_stance_active = true
	defensive_stance_timer = 7.0

	print(name, ": Defensive stance activated! (70% damage reduction for 7s)")
