extends Area3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_multiplayer_authority():
		return
	var health := body.get_node_or_null("HealthComponent") as HealthComponent
	if health and health.is_alive:
		health.take_damage(9999.0)
