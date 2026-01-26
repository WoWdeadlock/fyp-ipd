extends Area2D

@onready var boss_point = $BossPoint
var has_targeted: bool = false

func _physics_process(_delta: float) -> void:
	if has_targeted:
		return
		
	var overlapping_objects = get_overlapping_bodies()
	
	if overlapping_objects.size() > 0:
		find_best_target(overlapping_objects)
		has_targeted = true 

func find_best_target(overlapping_objects: Array) -> void:
	var best_agent: Agent = null
	var lowest_score: float = INF 
	
	for body in overlapping_objects:
		if body is Agent:
			var distance = boss_point.global_position.distance_to(body.global_position)
			var current_hp = body.health
			var score = (distance * 0.5) + (current_hp * 0.5)
			
			if score < lowest_score:
				lowest_score = score
				best_agent = body

	if best_agent:
		print("Targeting: ", best_agent.name, " with score: ", lowest_score)
