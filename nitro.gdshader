shader_type canvas_item;

uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float line_count : hint_range(10.0, 300.0, 1.0) = 140.0;
uniform float line_density : hint_range(0.0, 1.0) = 0.6;
uniform float line_sharpness : hint_range(0.001, 0.5) = 0.03;      // Low = crisp razor edges
uniform float mask_size : hint_range(0.0, 1.0) = 0.15;             // Base center circle size
uniform float mask_edge : hint_range(0.0, 1.0) = 0.35;             // Fade transition to edges
uniform float length_randomness : hint_range(0.0, 1.0) = 0.55;     // How much line lengths vary!
uniform float width_randomness : hint_range(0.0, 1.0) = 0.70;      // Mix of thin threads vs thick needles!
uniform float animation_speed : hint_range(1.0, 30.0) = 22.0;      // How fast lines randomize
uniform float master_opacity : hint_range(0.0, 1.0) = 1.0;         // For smooth GDScript tweening

float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
    vec2 centered_uv = UV - vec2(0.5);
    float angle = atan(centered_uv.y, centered_uv.x);
    float distance_from_center = length(centered_uv);
    
    // Convert angle to continuous radial slices
    float polar_angle = angle * line_count / 6.28318530718;
    float angle_index = floor(polar_angle);
    float angle_fract = fract(polar_angle); // Position (0.0 to 1.0) inside each slice
    
    // Generate independent random values for width and length over time
    float width_noise = random(vec2(angle_index, floor(TIME * animation_speed)));
    float length_noise = random(vec2(angle_index + 142.53, floor(TIME * animation_speed)));
    
    // 1. RANDOMIZE LENGTH: Offset the center mask per line so needles start at different depths
    float dynamic_mask_start = max(0.01, mask_size - (length_noise * length_randomness * 0.15));
    float center_mask = smoothstep(dynamic_mask_start, dynamic_mask_start + mask_edge, distance_from_center);
    
    // 2. RANDOMIZE THINNESS: Mix base density with random variance
    float dynamic_density = mix(line_density * 0.2, line_density * 1.5, width_noise * width_randomness);
    float thickness = dynamic_density * center_mask;
    
    // Sculpt sharp needle edges within the slice
    float half_width = thickness * 0.5;
    float line_shape = smoothstep(0.5 - half_width - line_sharpness, 0.5 - half_width, angle_fract) 
                     - smoothstep(0.5 + half_width, 0.5 + half_width + line_sharpness, angle_fract);
    
    // Apply final color and master opacity
    float final_alpha = line_shape * center_mask * line_color.a * master_opacity;
    COLOR = vec4(line_color.rgb, clamp(final_alpha, 0.0, 1.0));
}