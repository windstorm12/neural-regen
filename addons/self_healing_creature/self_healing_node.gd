@tool 
extends Node2D

# --- INSPECTOR SETTINGS ---
@export_group("Creature Settings")
@export var target_texture: Texture2D:
	set(value):
		target_texture = value
		if Engine.is_editor_hint() and output_texture_rect:
			output_texture_rect.texture = value
			
@export_range(0.1, 10.0) var growth_speed: float = 2.0
@export var heal_color: Color = Color(0.0, 1.0, 0.2)

@export_group("Visual Style")
@export var pixel_art_mode: bool = false 
@export_range(0.1, 0.95) var pixel_heal_threshold: float = 0.8 

@export_group("Simulation")
@export var simulation_fps: int = 60
@export var enable_random_damage: bool = false

@export_group("Internal (Advanced)")
@export_file("*.bin") var weights_file_path: String = ""
@export_file("*.glsl") var compute_shader_path: String = ""
@export_file("*.gdshader") var display_shader_path: String = ""

# Internal vars
var rd: RenderingDevice
var shader_rid: RID
var pipeline: RID
var buffer_target: RID
var buffer_weights: RID
var texture_display: RID 
var uniform_set_a_to_b: RID
var uniform_set_b_to_a: RID

var buffer_state_a: RID
var buffer_state_b: RID

var output_texture_rect: TextureRect
var output_material: ShaderMaterial

const GRID_W = 40
const GRID_H = 40
const CHANNELS = 16

var ping_pong := true
var time_accum := 0.0
var damage_timer := 0.0 
var external_damage_pos: Vector2 = Vector2(-1, -1)
var stun_timer: float = 0.0 

# SAFETY FLAG
var is_initialized: bool = false

func _ready():
	var base_dir = get_script().resource_path.get_base_dir()
	
	var final_weight_path = weights_file_path if weights_file_path != "" else base_dir + "/nca_weights.bin"
	var final_compute_path = compute_shader_path if compute_shader_path != "" else base_dir + "/shaders/nca.glsl"
	var final_display_path = display_shader_path if display_shader_path != "" else base_dir + "/shaders/display_mask.gdshader"
	
	# --- EDITOR SETUP ---
	if Engine.is_editor_hint():
		if get_child_count() == 0:
			output_texture_rect = TextureRect.new()
			add_child(output_texture_rect)
		else:
			output_texture_rect = get_child(0)
			
		output_texture_rect.texture = target_texture
		output_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		output_texture_rect.custom_minimum_size = Vector2(512, 512)
		output_texture_rect.size = Vector2(512, 512)
		return

	# --- RUNTIME SETUP ---
	if target_texture == null:
		push_error("SelfHealingCreature: No Target Texture assigned!")
		return

	rd = RenderingServer.get_rendering_device()
	
	if not FileAccess.file_exists(final_weight_path):
		push_error("CRITICAL ERROR: Weights not found at: " + final_weight_path)
		return
		
	var weight_file = FileAccess.open(final_weight_path, FileAccess.READ)
	var weight_bytes = weight_file.get_buffer(weight_file.get_length())
	buffer_weights = rd.storage_buffer_create(weight_bytes.size(), weight_bytes)
	
	if not FileAccess.file_exists(final_compute_path):
		push_error("CRITICAL ERROR: Compute Shader not found at: " + final_compute_path)
		return

	var shader_src = load(final_compute_path)
	var shader_spirv = shader_src.get_spirv()
	shader_rid = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader_rid)
	
	var img = target_texture.get_image()
	if img == null:
		push_error("SelfHealingCreature ERROR: Could not get image data.")
		return

	img.resize(GRID_W, GRID_H) 
	var target_data = PackedFloat32Array()
	target_data.resize(GRID_W * GRID_H)
	for y in range(GRID_H):
		for x in range(GRID_W):
			var alpha = img.get_pixel(x, y).a
			target_data[y * GRID_W + x] = 1.0 if alpha > 0.1 else 0.0
	var target_bytes = target_data.to_byte_array()
	buffer_target = rd.storage_buffer_create(target_bytes.size(), target_bytes)

	var state_size = GRID_W * GRID_H * CHANNELS * 4
	var zeros = PackedByteArray()
	zeros.resize(state_size)
	zeros.fill(0)
	buffer_state_a = rd.storage_buffer_create(state_size, zeros)
	buffer_state_b = rd.storage_buffer_create(state_size, zeros)

	var fmt = RDTextureFormat.new()
	fmt.width = GRID_W
	fmt.height = GRID_H
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	texture_display = rd.texture_create(fmt, RDTextureView.new(), [])
	
	var u_target = _make_uniform(buffer_target, 1)
	var u_weights = _make_uniform(buffer_weights, 2)
	var u_display = _make_uniform_tex(texture_display, 4)
	var u_in_a = _make_uniform(buffer_state_a, 0)
	var u_out_b = _make_uniform(buffer_state_b, 3)
	uniform_set_a_to_b = rd.uniform_set_create([u_in_a, u_target, u_weights, u_out_b, u_display], shader_rid, 0)
	var u_in_b = _make_uniform(buffer_state_b, 0)
	var u_out_a = _make_uniform(buffer_state_a, 3)
	uniform_set_b_to_a = rd.uniform_set_create([u_in_b, u_target, u_weights, u_out_a, u_display], shader_rid, 0)
	
	output_texture_rect = TextureRect.new()
	output_texture_rect.texture = target_texture
	output_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	output_texture_rect.custom_minimum_size = Vector2(512, 512)
	output_texture_rect.size = Vector2(512, 512)
	
	if not FileAccess.file_exists(final_display_path):
		push_error("Visual Shader not found at: " + final_display_path)
		return
		
	output_material = ShaderMaterial.new()
	output_material.shader = load(final_display_path)
	
	var tex_rd = Texture2DRD.new()
	tex_rd.texture_rd_rid = texture_display
	
	output_material.set_shader_parameter("nca_mask", tex_rd)
	output_material.set_shader_parameter("heal_color", heal_color)
	output_material.set_shader_parameter("pixel_mode", pixel_art_mode)
	output_material.set_shader_parameter("pixel_heal_threshold", pixel_heal_threshold)
	
	output_texture_rect.material = output_material
	
	if pixel_art_mode:
		output_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	else:
		output_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		
	add_child(output_texture_rect)
	
	# EVERYTHING LOADED OKAY
	is_initialized = true

func _make_uniform(rid, binding):
	var u = RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = binding
	u.add_id(rid)
	return u

func _make_uniform_tex(rid, binding):
	var u = RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(rid)
	return u

func apply_damage(global_pos: Vector2):
	if not is_initialized or output_texture_rect == null: return
	var local_pos = to_local(global_pos)
	var rect_size = output_texture_rect.size
	var grid_x = (local_pos.x / rect_size.x) * GRID_W
	var grid_y = (local_pos.y / rect_size.y) * GRID_H
	external_damage_pos = Vector2(grid_x, grid_y)
	stun_timer = 0.15

func _process(delta):
	if Engine.is_editor_hint(): return 
	if not is_initialized: return # STOP HERE IF LOAD FAILED
	
	# Live updates
	if output_material:
		output_material.set_shader_parameter("heal_color", heal_color)
		output_material.set_shader_parameter("pixel_mode", pixel_art_mode)
		output_material.set_shader_parameter("pixel_heal_threshold", pixel_heal_threshold)
		if pixel_art_mode:
			output_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		else:
			output_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			
	if enable_random_damage:
		damage_timer += delta
		if damage_timer > 0.5: 
			damage_timer = 0.0
			var rx = randf_range(100, 400)
			var ry = randf_range(100, 400)
			apply_damage(to_global(Vector2(rx, ry)))
	
	
	if stun_timer > 0.0:
		stun_timer -= delta

	var frame_time = 1.0 / float(simulation_fps)
	time_accum += delta
	if time_accum >= frame_time:
		_run_nca_step()
		time_accum -= frame_time

func _run_nca_step():
	var grid_x = 0.0
	var grid_y = 0.0
	var mouse_mode = 0.0
	var effective_speed = growth_speed * 0.1
	
	if stun_timer > 0.0:
		grid_x = external_damage_pos.x
		grid_y = external_damage_pos.y
		mouse_mode = 2.0 
		effective_speed = 0.0 
		
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var m_pos = get_local_mouse_position()
		grid_x = int((m_pos.x / 512.0) * GRID_W)
		grid_y = int((m_pos.y / 512.0) * GRID_H)
		mouse_mode = 2.0 
		effective_speed = 0.0 
	
	var push_constant = PackedFloat32Array([effective_speed, float(grid_x), float(grid_y), mouse_mode]).to_byte_array()
	
	var current_set = uniform_set_a_to_b if ping_pong else uniform_set_b_to_a
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, current_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constant, push_constant.size())
	rd.compute_list_dispatch(compute_list, GRID_W/8, GRID_H/8, 1)
	rd.compute_list_end()
	
	ping_pong = not ping_pong
