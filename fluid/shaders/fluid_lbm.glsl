#[compute]

#version 450

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(binding = 0, r32f) uniform image3D in_lattice;
layout(binding = 1, r32f) uniform image3D out_lattice;
layout(binding = 2, r8ui) uniform uimage2D obstacles;

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

const int inverse[9] = int[](
	0, 3, 4, 1, 2, 7, 8, 5, 6
);

// D2Q9 lattice weights
const float weights[9] = float[](
	4.0/9.0,
	1.0/9.0,  1.0/9.0,  1.0/9.0,  1.0/9.0,
	1.0/36.0, 1.0/36.0, 1.0/36.0, 1.0/36.0
);

ivec2 image_size = imageSize(in_lattice).xy;

float[9] streaming_step(ivec2 global_pos) {

	float mass[9]; // mass of fluid that is currently flowing at speed 1 in direction i
	for (int i = 0; i < 9; i++) {
		// Stream from opposite direction (where the mass is coming from)
		ivec2 source_pos = global_pos - flow_vectors[i];
		
		// Handle boundaries by loading zeros
		if (source_pos.x < 0 || source_pos.x >= image_size.x || 
			source_pos.y < 0 || source_pos.y >= image_size.y) {
			mass[i] = 0.0;
			continue;
		}

		// Obstacles are zeros
		// uint obstacle = imageLoad(obstacles, source_pos).r;
		// if ((obstacle & 1) > 0) {
		// 	mass[i] = 0.0;
		// 	continue;
		// }

		mass[i] = imageLoad(in_lattice, ivec3(source_pos, i)).r;
	}

	return mass;
}

void no_wall_pressure(out vec2 velocity, out float density, in float[9] mass) {
	density = 0.0;
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
	velocity = density > 0.0 ? momentum / density : vec2(0.0);
}

void zou_he_west_wall_velocity(vec2 wall_velocity, out vec2 velocity, out float density, inout float[9] mass) {
	const float cst1 = 2.0 / 3.0;
	const float cst2 = 1.0 / 6.0;
	const float cst3 = 1.0 / 2.0;

	velocity = wall_velocity;

	// West wall: known are CTR, N, S, W, NW, SW
	// Unknown: E, NE, SE
	density = (mass[CTR] + mass[N] + mass[S] + 
			   2.0 * mass[W] + 2.0 * mass[NW] + 
			   2.0 * mass[SW]) / (1.0 - velocity.x);

	mass[E] = mass[W] + cst1 * density * velocity.x;

	mass[NE] = mass[NW] - cst3 * (mass[N] - mass[S]) + 
			  cst2 * density * velocity.x + 
			  cst3 * density * velocity.y;

	mass[SE] = mass[SW] + cst3 * (mass[N] - mass[S]) + 
			  cst2 * density * velocity.x - 
			  cst3 * density * velocity.y;
}

void zou_he_east_wall_pressure(float wall_density, vec2 wall_velocity, out vec2 velocity, out float density, inout float[9] mass) {
	const float cst1 = 2.0 / 3.0;
	const float cst2 = 1.0 / 6.0;
	const float cst3 = 1.0 / 2.0;

	density = wall_density;
	velocity.y = wall_velocity.y;

	// East wall: known are CTR, N, S, E, NE, SE
	// Unknown: W, NW, SW
	velocity.x = (mass[CTR] + mass[N] + mass[S] + 
				  2.0 * mass[E] + 2.0 * mass[NE] + 
				  2.0 * mass[SE]) / density - 1.0;

	mass[W] = mass[E] - cst1 * density * velocity.x;

	mass[NW] = mass[NE] + cst3 * (mass[N] - mass[S]) - 
			  cst2 * density * velocity.x - 
			  cst3 * density * velocity.y;

	mass[SW] = mass[SE] - cst3 * (mass[N] - mass[S]) - 
			  cst2 * density * velocity.x + 
			  cst3 * density * velocity.y;
}

void zou_he_east_wall_velocity(vec2 wall_velocity, out vec2 velocity, out float density, inout float[9] mass) {
	const float cst1 = 2.0 / 3.0;
	const float cst2 = 1.0 / 6.0;
	const float cst3 = 1.0 / 2.0;

	velocity = wall_velocity;

	// East wall: known are CTR, N, S, E, NE, SE
	// Unknown: W, NW, SW
	density = (mass[CTR] + mass[N] + mass[S] + 
			   2.0 * mass[E] + 2.0 * mass[NE] + 
			   2.0 * mass[SE]) / (1.0 + velocity.x);

	mass[W] = mass[E] - cst1 * density * velocity.x;

	mass[NW] = mass[NE] + cst3 * (mass[N] - mass[S]) - 
			  cst2 * density * velocity.x - 
			  cst3 * density * velocity.y;

	mass[SW] = mass[SE] - cst3 * (mass[N] - mass[S]) - 
			  cst2 * density * velocity.x + 
			  cst3 * density * velocity.y;
}

void zou_he_north_wall_velocity(vec2 wall_velocity, out vec2 velocity, out float density, inout float[9] mass) {
	const float cst1 = 2.0 / 3.0;
	const float cst2 = 1.0 / 6.0;
	const float cst3 = 1.0 / 2.0;

	velocity = wall_velocity;

	// North wall (y=0, y-): known are CTR, E, W, N, NE, NW
	// Unknown: S, SW, SE
	density = (mass[CTR] + mass[E] + mass[W] + 
			   2.0 * mass[N] + 2.0 * mass[NE] + 
			   2.0 * mass[NW]) / (1.0 - velocity.y);

	mass[S] = mass[N] + cst1 * density * velocity.y;

	mass[SE] = mass[NE] - cst3 * (mass[E] - mass[W]) + 
			  cst3 * density * velocity.x + 
			  cst2 * density * velocity.y;

	mass[SW] = mass[NW] + cst3 * (mass[E] - mass[W]) - 
			  cst3 * density * velocity.x + 
			  cst2 * density * velocity.y;
}

void zou_he_south_wall_velocity(vec2 wall_velocity, out vec2 velocity, out float density, inout float[9] mass) {
	const float cst1 = 2.0 / 3.0;
	const float cst2 = 1.0 / 6.0;
	const float cst3 = 1.0 / 2.0;

	velocity = wall_velocity;

	// South wall (y=max, y+): known are CTR, E, W, S, SW, SE
	// Unknown: N, NE, NW
	density = (mass[CTR] + mass[E] + mass[W] + 
			   2.0 * mass[S] + 2.0 * mass[SW] + 
			   2.0 * mass[SE]) / (1.0 + velocity.y);

	mass[N] = mass[S] - cst1 * density * velocity.y;

	mass[NE] = mass[SE] - cst3 * (mass[E] - mass[W]) + 
			  cst3 * density * velocity.x - 
			  cst2 * density * velocity.y;

	mass[NW] = mass[SW] + cst3 * (mass[E] - mass[W]) - 
			  cst3 * density * velocity.x - 
			  cst2 * density * velocity.y;
}

void zou_he_northwest_corner_velocity(ivec2 global_pos, inout vec2 velocity, inout float density, inout float[9] mass) {

	float adjacent_mass[9] = streaming_step(global_pos + flow_vectors[SE]);
	no_wall_pressure(velocity, density, adjacent_mass);

	mass[E] = mass[W] + (2.0 / 3.0) * density * velocity.x;

	mass[S] = mass[N] + (2.0 / 3.0) * density * velocity.y;

	mass[SE] = mass[NW] + (1.0 / 6.0) * density * velocity.x + 
						(1.0 / 6.0) * density * velocity.y;

	mass[NE] = 0.0;
	mass[SW] = 0.0;

	mass[CTR] = density - mass[E] - mass[N] - mass[W] - mass[S] - 
						mass[NE] - mass[NW] - mass[SW] - mass[SE];
}

void zou_he_southwest_corner_velocity(ivec2 global_pos, inout vec2 velocity, inout float density, inout float[9] mass) {
	
	float adjacent_mass[9] = streaming_step(global_pos + flow_vectors[NE]);
	no_wall_pressure(velocity, density, adjacent_mass);

	mass[E] = mass[W] + (2.0 / 3.0) * density * velocity.x;

	mass[S] = mass[N] - (2.0 / 3.0) * density * velocity.y;

	mass[SE] = mass[SW] + (1.0 / 6.0) * density * velocity.x - 
						(1.0 / 6.0) * density * velocity.y;

	mass[NE] = 0.0;
	mass[NW] = 0.0;

	mass[CTR] = density - mass[E] - mass[N] - mass[W] - mass[S] - 
						mass[NE] - mass[NW] - mass[SW] - mass[SE];
}

void zou_he_southeast_corner_velocity(ivec2 global_pos, inout vec2 velocity, inout float density, inout float[9] mass) {
	
	float adjacent_mass[9] = streaming_step(global_pos + flow_vectors[NW]);
	no_wall_pressure(velocity, density, adjacent_mass);

	mass[W] = mass[E] - (2.0 / 3.0) * density * velocity.x;

	mass[S] = mass[N] - (2.0 / 3.0) * density * velocity.y;

	mass[SW] = mass[SE] - (1.0 / 6.0) * density * velocity.x - 
						(1.0 / 6.0) * density * velocity.y;

	mass[NW] = 0.0;
	mass[NE] = 0.0;

	mass[CTR] = density - mass[E] - mass[N] - mass[W] - mass[S] - 
						mass[NE] - mass[NW] - mass[SW] - mass[SE];
}

void zou_he_northeast_corner_velocity(ivec2 global_pos, inout vec2 velocity, inout float density, inout float[9] mass) {
	
	float adjacent_mass[9] = streaming_step(global_pos + flow_vectors[SW]);
	no_wall_pressure(velocity, density, adjacent_mass);

	mass[W] = mass[E] - (2.0 / 3.0) * density * velocity.x;

	mass[S] = mass[N] + (2.0 / 3.0) * density * velocity.y;

	mass[SW] = mass[SE] - (1.0 / 6.0) * density * velocity.x + 
						(1.0 / 6.0) * density * velocity.y;

	mass[NW] = 0.0;
	mass[SE] = 0.0;

	mass[CTR] = density - mass[E] - mass[N] - mass[W] - mass[S] - 
						mass[NE] - mass[NW] - mass[SW] - mass[SE];
}

float[9] get_equilibrium(ivec2 global_pos, float[9] mass) {
	float density;
	vec2 velocity;

	bool west_wall = global_pos.x == 0;
	bool east_wall = global_pos.x == image_size.x - 1;
	bool north_wall = global_pos.y == 0;
	bool south_wall = global_pos.y == image_size.y - 1;
	
	uint obstacle = imageLoad(obstacles, global_pos).r;
	bool west_obstacle = (obstacle & (1 << W)) > 0;
	bool east_obstacle = (obstacle & (1 << E)) > 0;
	bool north_obstacle = (obstacle & (1 << N)) > 0;
	bool south_obstacle = (obstacle & (1 << S)) > 0;

	// west_wall = west_wall || west_obstacle;
	// east_wall = east_wall || east_obstacle;
	north_wall = north_wall || north_obstacle;
	south_wall = south_wall || south_obstacle;

	// Apply boundary conditions
	if (west_wall && north_wall) {
		// Northwest corner
		zou_he_northwest_corner_velocity(global_pos, velocity, density, mass);
	} else if (west_wall && south_wall) {
		// Southwest corner
		zou_he_southwest_corner_velocity(global_pos, velocity, density, mass);
	} else if (east_wall && north_wall) {
		// Northeast corner
		zou_he_northeast_corner_velocity(global_pos, velocity, density, mass);
	} else if (east_wall && south_wall) {
		// Southeast corner
		zou_he_southeast_corner_velocity(global_pos, velocity, density, mass);
	
	} else if (west_wall) {
		// West wall
		vec2 wall_vel = vec2(0.2, 0.0); // Example inlet velocity
		zou_he_west_wall_velocity(wall_vel, velocity, density, mass);
	} else if (east_wall) {
		// East wall
		vec2 wall_vel = vec2(0.0, 0.0); // Example outlet velocity
		float wall_density = 3.25; // Example outlet pressure
		// zou_he_east_wall_velocity(wall_vel, velocity, density, mass);
		zou_he_east_wall_pressure(wall_density, wall_vel, velocity, density, mass);
	
	} else if (west_obstacle) {
		// West wall
		vec2 wall_vel = vec2(0.0, 0.0); // Example inlet velocity
		zou_he_west_wall_velocity(wall_vel, velocity, density, mass);
	} else if (east_obstacle) {
		// East wall
		vec2 wall_vel = vec2(0.0, 0.0); // Example outlet velocity
		zou_he_east_wall_velocity(wall_vel, velocity, density, mass);

	} else if (north_wall) {
		// North wall
		vec2 wall_vel = vec2(0.0, 0.0); // No-slip
		zou_he_north_wall_velocity(wall_vel, velocity, density, mass);
	} else if (south_wall) {
		// South wall
		vec2 wall_vel = vec2(0.0, 0.0); // No-slip
		zou_he_south_wall_velocity(wall_vel, velocity, density, mass);
	} else {
		// Interior - no boundary condition
		no_wall_pressure(velocity, density, mass);
	}

	// Speed of sound in D2Q9 lattice
	const float cs2 = 1.0 / 3.0; // cs = 1/sqrt(3)
	
	// Calculate the equilibrium densities
	float equilibrium[9];
	float ve = 1.5 * dot(velocity, velocity);

	for (int i = 0; i < 9; i++) {
		float rho = density;
		vec2 u = velocity;
		vec2 ei = flow_vectors[i];

		// Standard D2Q9 equilibrium distribution
		float t = 3.0 * dot(ei, u);

		equilibrium[i] = weights[i] * rho * (1.0 + t + 0.5 * t * t - ve);
	}

	return equilibrium;
}

float[9] collision_step(float[9] mass, float[9] equilibrium) {

	// Two-Relaxation-Time (TRT) collision parameters
	const float tau_lbm = 1.00;          // Main relaxation time
	const float lambda_trt = 0.25;       // TRT magic parameter (1/4 for stability)
	const float tau_p_lbm = tau_lbm;
	const float tau_m_lbm = lambda_trt / (tau_p_lbm - 0.5) + 0.5;
	const float om_p = 1.0 / tau_p_lbm;  // ??
	const float om_m = 1.0 / tau_m_lbm;  // ??

	float new_mass[9];
	// Special treatment for center node
	new_mass[CTR] = (1.0 - om_p) * mass[CTR] + om_p * equilibrium[CTR];

	// TRT collision for other directions
	for (int i = 1; i < 9; i++) {
		new_mass[i] = (1.0 - 0.5 * (om_p + om_m)) * mass[i]
					- 0.5 * (om_p - om_m) * mass[inverse[i]]
					+ 0.5 * (om_p + om_m) * equilibrium[i]
					+ 0.5 * (om_p - om_m) * equilibrium[inverse[i]];
	}

	return new_mass;
}

void main() {
	ivec2 global_pos = ivec2(gl_GlobalInvocationID.xy);
	float mass[9] = streaming_step(global_pos);
	float equilibrium[9] = get_equilibrium(global_pos, mass);
	float new_mass[9] = collision_step(mass, equilibrium);

	for (int i = 0; i < 9; i++) {
		imageStore(
			out_lattice,
			ivec3(gl_GlobalInvocationID.xy, i),
			vec4(new_mass[i], 1.0, 1.0, .0)
		);
	}
}
