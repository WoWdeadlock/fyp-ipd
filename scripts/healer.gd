extends Agent
class_name Healer

var is_healing: bool = false
var is_buffing: bool = false
var is_restoring: bool = false

func _ready():
	max_health = 70
	health = 70
	max_stamina = 150
	stamina = 150
	speed = 110.0
	super._ready()
	add_to_group("healer")

func _physics_process(delta):
	# Regenerate stamina (from base class)
	if stamina < max_stamina:
		stamina += stamina_regen_rate * delta

	# Handle keybinds for healing
	if Input.is_key_pressed(KEY_X):
		if not is_healing:
			heal_target("sniper")
	elif Input.is_key_pressed(KEY_C):
		if not is_healing:
			heal_target("tank")
	# New abilities
	elif Input.is_key_pressed(KEY_KP_1):
		if not is_buffing:
			shield_buff("tank")
	elif Input.is_key_pressed(KEY_KP_2):
		if not is_restoring:
			restore_stamina("sniper")

	# Movement handling
	if not nav_agent.is_navigation_finished():
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

func heal_target(target_type: String):
	is_healing = true
	
	var target_node = null
	if target_type == "sniper":
		target_node = get_tree().get_first_node_in_group("sniper")
	elif target_type == "tank":
		target_node = get_tree().get_first_node_in_group("tank")
	
	if not target_node:
		print(name, ": Could not find ", target_type, " to heal!")
		is_healing = false
		return
	
	print(name, ": Healing ", target_node.name, "...")
	
	await get_tree().create_timer(1.0).timeout
	
	if target_node and is_instance_valid(target_node) and target_node.has_method("heal"):
		target_node.heal(40)
		print(name, " healed ", target_node.name, " for 40 HP")
	
	is_healing = false

func shield_buff(target_type: String):
	if stamina < 20:
		print(name, ": Not enough stamina for shield buff!")
		return
	
	is_buffing = true
	stamina -= 20
	
	var target_node = null
	if target_type == "sniper":
		target_node = get_tree().get_first_node_in_group("sniper")
	elif target_type == "tank":
		target_node = get_tree().get_first_node_in_group("tank")
	
	if not target_node:
		print(name, ": Could not find ", target_type, " to buff!")
		is_buffing = false
		return
	
	print(name, ":  Casting shield on ", target_node.name, "...")
	
	await get_tree().create_timer(0.8).timeout
	
	if target_node and is_instance_valid(target_node):
		if target_node.has_method("apply_shield"):
			target_node.apply_shield()
			print(name, " granted shield to ", target_node.name, " (50% damage reduction for 6s)")
	
	is_buffing = false

func restore_stamina(target_type: String):
	if stamina < 25:
		print(name, ": Not enough stamina to restore stamina!")
		return
	
	is_restoring = true
	stamina -= 25
	
	var target_node = null
	if target_type == "sniper":
		target_node = get_tree().get_first_node_in_group("sniper")
	elif target_type == "tank":
		target_node = get_tree().get_first_node_in_group("tank")
	
	if not target_node:
		print(name, ": Could not find ", target_type, " to restore!")
		is_restoring = false
		return
	
	print(name, ": Restoring stamina to ", target_node.name, "...")
	
	await get_tree().create_timer(1.0).timeout
	
	if target_node and is_instance_valid(target_node):
		var restore_amount = 50
		target_node.stamina += restore_amount
		print(name, " restored ", restore_amount, " stamina to ", target_node.name)
	
	is_restoring = false
