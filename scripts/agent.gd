extends CharacterBody2D
class_name Agent

@export var speed := 120.0
@export var max_health: int = 100
@export var max_stamina: int = 100
@export var stamina_regen_rate: float = 40.0
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

@export var health: int = 75:
	set(value):
		var new_health = clamp(value, 0, max_health)
		if health != new_health:
			health = new_health
			if health_bar:
				health_bar.value = health
			
@export var stamina: int = 45:
	set(value):
		var new_stamina = clamp(value, 0, max_stamina)
		if stamina != new_stamina:
			stamina = new_stamina
			if stamina_bar:
				stamina_bar.value = stamina

@onready var health_bar: TextureProgressBar = $HealthBar
@onready var stamina_bar: TextureProgressBar = $StaminaBar

func _ready():
	health_bar.max_value = max_health
	health_bar.value = health
	
	stamina_bar.max_value = max_stamina
	stamina_bar.value = stamina
	
	# Enable avoidance
	nav_agent.avoidance_enabled = true
	nav_agent.radius = 25.0
	nav_agent.velocity_computed.connect(_on_velocity_computed)

func _physics_process(delta):
	# Regenerate stamina
	if stamina < max_stamina:
		var old_stamina = stamina
		stamina += stamina_regen_rate * delta
		if int(old_stamina) != int(stamina):
			print(name, " stamina: ", int(stamina), "/", max_stamina)

	if nav_agent.is_navigation_finished():
		velocity = Vector2.ZERO
	else:
		var next_pos = nav_agent.get_next_path_position()
		var direction = (next_pos - global_position).normalized()
		var desired_velocity = direction * speed
		nav_agent.set_velocity(desired_velocity)

	move_and_slide()

func _on_velocity_computed(safe_velocity: Vector2):
	velocity = safe_velocity

func take_damage(amount: int):
	health -= amount
	if health <= 0:
		queue_free()
		print(name, " has been defeated!")

func heal(amount: int):
	health += amount
	print(name, " healed for ", amount, " HP (Current: ", health, "/", max_health, ")")
