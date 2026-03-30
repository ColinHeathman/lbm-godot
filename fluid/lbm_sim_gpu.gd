extends Node

@export var display: Sprite2D
@export var display_normals: Sprite2D
@export var obstacles: Image
@export var noise: FastNoiseLite
@export var gradient: GradientTexture1D

var iteration = 0

var _rd: RenderingDevice
var _fluid_shader: RID
var _fluid_pipeline: RID
var _fluid_input_uniform: RDUniform
var _fluid_output_uniform: RDUniform
var _fluid_obstacle_uniform: RDUniform
var _fluid_uniform_set: RID

var _visualization_shader: RID
var _visualization_pipeline: RID
var _visualization_input_uniform: RDUniform
var _visualization_gradient_uniform: RDUniform
var _visualization_color_uniform: RDUniform
var _visualization_normal_uniform: RDUniform
var _visualization_uniform_set: RID

var _default_texture_view : RDTextureView
var _lattice_texture_format : RDTextureFormat
var _obstacle_texture_format : RDTextureFormat
var _color_texture_format : RDTextureFormat
var _gradient_texture_format : RDTextureFormat

var _lattice_textures: Array[RID]
var _obstacle_texture: RID
var _color_texture: RID
var _gradient_texture: RID
var _normal_texture: RID

const WIDTH = 256
const HEIGHT = 256
const EMPTY = Color(0.0, 0.0, 0.0, 1.0)

const WORKGROUP_X = WIDTH
const WORKGROUP_Y = HEIGHT
const INVOCATIONS_X = 1
const INVOCATIONS_Y = 1

const flow_vectors: Array[Vector2i] = [
	Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1),
	Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

func _init_shaders() -> void:
	# Create a local rendering device.
	_rd = RenderingServer.create_local_rendering_device()
	assert(_rd != null)

	# Load GLSL shaders
	_default_texture_view = RDTextureView.new()

	_lattice_texture_format = RDTextureFormat.new()
	_lattice_texture_format.width = WIDTH
	_lattice_texture_format.height = HEIGHT
	_lattice_texture_format.depth = 9
	_lattice_texture_format.mipmaps = 1
	_lattice_texture_format.texture_type = RenderingDevice.TEXTURE_TYPE_3D
	_lattice_texture_format.format = _rd.DATA_FORMAT_R32_SFLOAT
	_lattice_texture_format.usage_bits |= _rd.TEXTURE_USAGE_STORAGE_BIT
	_lattice_texture_format.usage_bits |= _rd.TEXTURE_USAGE_CAN_UPDATE_BIT
	_lattice_texture_format.usage_bits |= _rd.TEXTURE_USAGE_CAN_COPY_FROM_BIT

	_obstacle_texture_format = RDTextureFormat.new()
	_obstacle_texture_format.width = WIDTH
	_obstacle_texture_format.height = HEIGHT
	_obstacle_texture_format.depth = 9
	_obstacle_texture_format.mipmaps = 1
	_obstacle_texture_format.texture_type = RenderingDevice.TEXTURE_TYPE_3D
	_obstacle_texture_format.format = _rd.DATA_FORMAT_R8_UINT
	_obstacle_texture_format.usage_bits |= _rd.TEXTURE_USAGE_STORAGE_BIT
	_obstacle_texture_format.usage_bits |= _rd.TEXTURE_USAGE_CAN_UPDATE_BIT
	_obstacle_texture_format.usage_bits |= _rd.TEXTURE_USAGE_CAN_COPY_FROM_BIT

	_color_texture_format = RDTextureFormat.new()
	_color_texture_format.width = WIDTH
	_color_texture_format.height = HEIGHT
	_color_texture_format.depth = 1
	_color_texture_format.mipmaps = 1
	_color_texture_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	_color_texture_format.format = _rd.DATA_FORMAT_R32G32B32A32_SFLOAT
	_color_texture_format.usage_bits |= _rd.TEXTURE_USAGE_STORAGE_BIT
	_color_texture_format.usage_bits |= _rd.TEXTURE_USAGE_CAN_UPDATE_BIT
	_color_texture_format.usage_bits |= _rd.TEXTURE_USAGE_CAN_COPY_FROM_BIT

	_gradient_texture_format = RDTextureFormat.new()
	_gradient_texture_format.width = 256
	_gradient_texture_format.height = 1
	_gradient_texture_format.depth = 1
	_gradient_texture_format.mipmaps = 1
	_gradient_texture_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	_gradient_texture_format.format = _rd.DATA_FORMAT_R32G32B32A32_SFLOAT
	_gradient_texture_format.usage_bits |= _rd.TEXTURE_USAGE_STORAGE_BIT
	_gradient_texture_format.usage_bits |= _rd.TEXTURE_USAGE_CAN_UPDATE_BIT
	_gradient_texture_format.usage_bits |= _rd.TEXTURE_USAGE_CAN_COPY_FROM_BIT

	# Create compute pipelines
	var fluid_shader_file := load("res://compute/shaders/fluid_lbm.glsl")
	var fluid_shader_spirv: RDShaderSPIRV = fluid_shader_file.get_spirv()
	_fluid_shader = _rd.shader_create_from_spirv(fluid_shader_spirv)
	_fluid_pipeline = _rd.compute_pipeline_create(_fluid_shader)
	assert(_rd.compute_pipeline_is_valid(_fluid_pipeline))

	# Create uniforms for fluid shader
	_fluid_input_uniform = RDUniform.new()
	_fluid_input_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	_fluid_input_uniform.binding = 0
	_fluid_output_uniform = RDUniform.new()
	_fluid_output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	_fluid_output_uniform.binding = 1
	_fluid_obstacle_uniform = RDUniform.new()
	_fluid_obstacle_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	_fluid_obstacle_uniform.binding = 2

	var visualization_shader_file := load("res://compute/shaders/visualization.glsl")
	var visualization_shader_spirv: RDShaderSPIRV = visualization_shader_file.get_spirv()
	_visualization_shader = _rd.shader_create_from_spirv(visualization_shader_spirv)
	_visualization_pipeline = _rd.compute_pipeline_create(_visualization_shader)
	assert(_rd.compute_pipeline_is_valid(_visualization_pipeline))

	# Create uniforms for visualization shader
	_visualization_input_uniform = RDUniform.new()
	_visualization_input_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	_visualization_input_uniform.binding = 0
	_visualization_gradient_uniform = RDUniform.new()
	_visualization_gradient_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	_visualization_gradient_uniform.binding = 1
	_visualization_color_uniform = RDUniform.new()
	_visualization_color_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	_visualization_color_uniform.binding = 2
	_visualization_normal_uniform = RDUniform.new()
	_visualization_normal_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	_visualization_normal_uniform.binding = 3

func _init_textures() -> void:
	_lattice_textures.resize(2)
	_lattice_textures[0] = _rd.texture_create(_lattice_texture_format, _default_texture_view)
	assert(_rd.texture_is_valid(_lattice_textures[0]))
	_lattice_textures[1] = _rd.texture_create(_lattice_texture_format, _default_texture_view)
	assert(_rd.texture_is_valid(_lattice_textures[1]))
	
	# Obstacle texture
	_obstacle_texture = _rd.texture_create(_obstacle_texture_format, _default_texture_view)
	assert(_rd.texture_is_valid(_obstacle_texture))
	# Create visualization textures
	_gradient_texture = _rd.texture_create(_gradient_texture_format, _default_texture_view)
	assert(_rd.texture_is_valid(_gradient_texture))
	_color_texture = _rd.texture_create(_color_texture_format, _default_texture_view)
	assert(_rd.texture_is_valid(_color_texture))
	_normal_texture = _rd.texture_create(_color_texture_format, _default_texture_view)
	assert(_rd.texture_is_valid(_normal_texture))
	
	# Initialize with noise data
	var noise_image: Image = noise.get_image(WIDTH, HEIGHT)
	var input_data := PackedFloat32Array()
	
	# Initialize all 9 layers of the 3D texture
	for z in range(9):
		for y in range(HEIGHT):
			for x in range(WIDTH):
				var color := EMPTY
				color.r = 0.5
				#color.r += (noise_image.get_pixel(x, y).r - 0.5)
				input_data.append(color.r)
	
	# Upload initial data to input texture
	var data_bytes = input_data.to_byte_array()
	_rd.texture_update(_lattice_textures[0], 0, data_bytes)

	# Upload initial obstacle texture
	obstacles.convert(Image.FORMAT_R8)
	_rd.texture_update(_obstacle_texture, 0, obstacles.get_data())

	var gradient_image = gradient.get_image()
	gradient_image.convert(Image.FORMAT_RGBAF)
	_rd.texture_update(_gradient_texture, 0, gradient_image.get_data())


func _ready() -> void:
	_init_shaders()
	_init_textures()
	_create_uniform_sets()

func _create_uniform_sets() -> void:
	_fluid_input_uniform.add_id(_lattice_textures[0])
	_fluid_output_uniform.add_id(_lattice_textures[1])
	_fluid_obstacle_uniform.add_id(_obstacle_texture)
	_fluid_uniform_set = _rd.uniform_set_create(
		[_fluid_input_uniform, _fluid_output_uniform, _fluid_obstacle_uniform],
		_fluid_shader,
		0
	)

	# Create visualization uniform set (uses fluid output texture)
	_visualization_input_uniform.add_id(_lattice_textures[1])
	_visualization_gradient_uniform.add_id(_gradient_texture)
	_visualization_color_uniform.add_id(_color_texture)
	_visualization_normal_uniform.add_id(_normal_texture)
	_visualization_uniform_set = _rd.uniform_set_create(
		[_visualization_input_uniform, _visualization_gradient_uniform, _visualization_color_uniform, _visualization_normal_uniform],
		_visualization_shader,
		0
	)

func _swap() -> void:
	# Swap the two lattice textures
	var swap: RID = _lattice_textures[0]
	_lattice_textures[0] = _lattice_textures[1]
	_lattice_textures[1] = swap
	
	# Update uniform sets with new texture assignments
	_fluid_input_uniform.clear_ids()
	_fluid_output_uniform.clear_ids()
	_fluid_input_uniform.add_id(_lattice_textures[0])
	_fluid_output_uniform.add_id(_lattice_textures[1])
	_fluid_uniform_set = _rd.uniform_set_create(
		[_fluid_input_uniform, _fluid_output_uniform, _fluid_obstacle_uniform],
		_fluid_shader,
		0
	)
	
	# Update visualization uniform set to read from the fluid output texture
	_visualization_input_uniform.clear_ids()
	_visualization_input_uniform.add_id(_lattice_textures[1])
	_visualization_uniform_set = _rd.uniform_set_create(
		[_visualization_input_uniform, _visualization_gradient_uniform, _visualization_color_uniform, _visualization_normal_uniform],
		_visualization_shader,
		0
	)

func _process(_delta: float) -> void:
	for x in range(10):
		var compute_list := _rd.compute_list_begin()
		
		# Execute fluid+streaming step: lattice_textures[0] -> lattice_textures[1]
		_rd.compute_list_bind_compute_pipeline(compute_list, _fluid_pipeline)
		_rd.compute_list_bind_uniform_set(compute_list, _fluid_uniform_set, 0)
		_rd.compute_list_dispatch(compute_list, WIDTH, HEIGHT, 1)
		
		# Add barrier to ensure fluid+streaming completes before visualization
		_rd.compute_list_add_barrier(compute_list)
		
		# Execute visualization step: lattice_textures[1] -> color and normal textures
		_rd.compute_list_bind_compute_pipeline(compute_list, _visualization_pipeline)
		_rd.compute_list_bind_uniform_set(compute_list, _visualization_uniform_set, 0)
		_rd.compute_list_dispatch(compute_list, WIDTH, HEIGHT, 1)
		
		_rd.compute_list_end()

		# Submit to GPU and wait for sync
		_rd.submit()
		_rd.sync()

		# Swap textures for next frame
		_swap()
		
		#DDD.set_text("iteration", iteration)
		iteration += 1
	
	# Display the visualization result
	_display_lattice()
	

func _display_lattice() -> void:
	# Read back the color visualization texture (already averaged across all 9 layers)
	var color_bytes := _rd.texture_get_data(_color_texture, 0)
	
	# Create image directly from the color texture data
	var image = Image.create_from_data(
		WIDTH,
		HEIGHT,
		false,
		Image.FORMAT_RGBAF,
		color_bytes
	)
	display.texture = ImageTexture.create_from_image(image)

	# Read back the color visualization texture (already averaged across all 9 layers)
	var normal_bytes := _rd.texture_get_data(_normal_texture, 0)
	
	# Create image directly from the color texture data
	var image_normal = Image.create_from_data(
		WIDTH,
		HEIGHT,
		false,
		Image.FORMAT_RGBAF,
		normal_bytes
	)
	display_normals.texture = ImageTexture.create_from_image(image_normal)
	
