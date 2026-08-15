extends Area3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var health := body.get_node_or_null("HealthComponent") as HealthComponent
	if health and health.is_alive:
		health.take_damage.rpc_id(body.get_multiplayer_authority(), 9999.0)
