extends Node2D

@onready var pixel_bot = $PixelBot
@onready var flesh_wall = $FleshWall

func _process(_delta):
	if Input.is_action_just_pressed("ui_accept"): # Spacebar
		# Hit Pixel Bot (It's at 0,0 usually)
		var r1 = Vector2(randf_range(100, 400), randf_range(100, 400))
		pixel_bot.apply_damage(pixel_bot.to_global(r1))
		
		# Hit Flesh Wall (Wherever it is)
		# We pick a random point relative to ITS position
		var r2 = Vector2(randf_range(100, 400), randf_range(100, 400))
		
		# to_global converts (0,0) to (600,0). 
		# So to_global(r2) adds the wall's position automatically.
		flesh_wall.apply_damage(flesh_wall.to_global(r2))
