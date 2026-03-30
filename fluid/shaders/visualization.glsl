#[compute]

#version 450

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(binding = 0, r32f) uniform image3D in_lattice;
layout(binding = 1, rgba32f) uniform image2D in_gradient;
layout(binding = 2, rgba32f) uniform image2D out_color;
layout(binding = 3, rgba32f) uniform image2D out_normal;

const int CTR = 0; // [CTR]
const int E   = 1; // [E]
const int N   = 2; // [N]
const int W   = 3; // [W]
const int S   = 4; // [S]
const int NE  = 5; // [NE]
const int NW  = 6; // [NW]
const int SW  = 7; // [SW]
const int SE  = 8; // [SE]

// D2Q9 flow vectors
// e6, e2, e5,
// e3, e0, e1,
// e7, e4, e8,
const ivec2 flow_vectors[9] = ivec2[](
	ivec2( 0,  0),
	ivec2( 1,  0), ivec2( 0, -1), ivec2(-1,  0), ivec2( 0,  1),
	ivec2( 1, -1), ivec2(-1, -1), ivec2(-1,  1), ivec2( 1,  1)
);

vec4 get_density_color(float[9] mass) {

	float density = 0.0;
	// macroscopic density (total mass)
	for (int i = 0; i < 9; i++) {
		density += mass[i];
	}

	// Clamp input
	return imageLoad(in_gradient, ivec2(clamp(density * 255, 0.0, 255.0), 0));
}

vec4 get_flow_color(float[9] mass) {

	float density = 0.0;
	// macroscopic density (total mass)
	for (int i = 0; i < 9; i++) {
		density += mass[i];
	}

	// macroscopic momentum (mass-weighted velocity)
	vec2 momentum = vec2(0.0);
	for (int i = 0; i < 9; i++) {
		momentum += mass[i] * flow_vectors[i];
	}

	// average velocity
	vec2 velocity = density > 0.0 ? momentum / density : vec2(0.0);
	float speed = sqrt(dot(velocity, velocity));
	speed = speed * 2.0; // Adjustment

	// Clamp input
	return vec4(
		imageLoad(
			in_gradient,
			ivec2(clamp(speed * 255, 0.0, 255.0), 0)
		).rgb,
		clamp(density, 0.0, 1.0)
	);
}

void main() {
	ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
	
	float mass[9]; // mass of fluid that is currently flowing at speed 1 in direction i
	for (int i = 0; i < 9; i++) {
		mass[i] = imageLoad(in_lattice, ivec3(coord, i)).r;
	}

	// Store average as color texture (alpha = 1 for display)
	// vec4 density_color = get_density_color(mass);
	// imageStore(out_color, coord, density_color);
	vec4 flow_color = get_flow_color(mass);
	imageStore(out_color, coord, flow_color);
	
	// Calculate flow direction for normal map
	vec2 flow_direction = vec2(0.0);
	for (int i = 0; i < 9; i++) {
		// Weight each flow vector by its mass intensity
		flow_direction += flow_vectors[i] * mass[i];
	}
	
	// Normalize flow direction and convert to normal map format
	if (length(flow_direction) > 0.0) {
		flow_direction = normalize(flow_direction);
	}
	
	// Convert from [-1,1] range to [0,1] range for normal map storage
	// X and Y are flow direction, Z is always pointing "up" (out of plane)
	vec3 normal = vec3(
		flow_direction.x * 0.5 + 0.5,  // X component
		flow_direction.y * 0.5 + 0.5,  // Y component  
		1.0                            // Z component (always up)
	);
	
	imageStore(out_normal, coord, vec4(normal, 1.0));
}