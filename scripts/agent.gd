extends CharacterBody2D
class_name Agent

@export var speed := 120.0
@export var max_health: int = 100
@export var max_stamina: int = 100
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

@export var health: int = 75:
	set(value):
		health = clamp(value, 0, max_health)
		if health_bar:
			health_bar.value = health
			
@export var stamina: int = 45:
	set(value):
		stamina = clamp(value, 0, max_stamina)
		if stamina_bar:
			stamina_bar.value = stamina

@onready var health_bar: TextureProgressBar = $HealthBar
@onready var stamina_bar: TextureProgressBar = $StaminaBar
func _ready():
	health_bar.max_value = max_health
	health_bar.value = health
	
	stamina_bar.max_value = max_stamina
	stamina_bar.value = stamina
	
	nav_agent.velocity_computed.connect(_on_velocity_computed)

func _physics_process(delta):
	if nav_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var next_pos = nav_agent.get_next_path_position()
	var direction = (next_pos - global_position).normalized()
	velocity = direction * speed
	move_and_slide()

func _on_velocity_computed(safe_velocity: Vector2):
	velocity = safe_velocity
