#version 450

layout(location = 0) in vec2 local_position;
layout(location = 1) in vec2 primitive_size;
layout(location = 2) in vec4 color;
layout(location = 3) in vec4 secondary;
layout(location = 4) in vec4 radii;
layout(location = 5) in vec4 border;
layout(location = 6) in vec4 widths;
layout(location = 7) in vec4 gradient;
layout(location = 8) in vec4 center_kind;
layout(location = 9) in float dash;
layout(location = 10) in float spread;

layout(set = 0, binding = 0) uniform sampler2D atlas;
layout(location = 0) out vec4 fragment_color;

float approx_erf(float value) {
  float square = value * value;
  return sign(value) * sqrt(1.0 - exp(-square * (1.27323954474 + 0.147 * square) / (1.0 + 0.147 * square)));
}

void main() {
  vec4 fill = color;
  if (center_kind.w == 0.0) {
    if (gradient.x > 0.0) {
      vec2 normalized = local_position / primitive_size;
      float raw = gradient.x == 1.0 || gradient.x == 4.0
        ? dot(normalized - 0.5, vec2(cos(radians(gradient.w)), sin(radians(gradient.w)))) + 0.5
        : gradient.x == 2.0 || gradient.x == 5.0 ? length(normalized - center_kind.xy) / center_kind.z
        : fract((atan(normalized.y - center_kind.y, normalized.x - center_kind.x) - radians(gradient.w)) / 6.28318530718 + 1.0);
      float amount = clamp((raw - gradient.y) / max(gradient.z - gradient.y, 0.000001), 0.0, 1.0);
      vec2 ramp_uv = vec2((floor(amount * 255.0 + 0.5) + 0.5) / 256.0, (secondary.x + 0.5) / 256.0);
      fill = gradient.x >= 4.0 ? texture(atlas, ramp_uv) * vec4(1.0,1.0,1.0,color.a)
        : mix(color, secondary, amount);
    }
    float radius = local_position.y < primitive_size.y / 2.0
      ? (local_position.x < primitive_size.x / 2.0 ? radii.x : radii.y)
      : (local_position.x < primitive_size.x / 2.0 ? radii.w : radii.z);
    radius = clamp(radius, 0.0, min(primitive_size.x, primitive_size.y) / 2.0);
    vec2 q = abs(local_position - primitive_size / 2.0) - primitive_size / 2.0 + radius;
    float distance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    float coverage = clamp(0.5 - distance, 0.0, 1.0);
    vec4 edge_distance = vec4(local_position.y, primitive_size.x - local_position.x,
                              primitive_size.y - local_position.y, local_position.x);
    float edge = min(min(edge_distance.x, edge_distance.y), min(edge_distance.z, edge_distance.w));
    float border_width = edge == edge_distance.x ? widths.x
      : edge == edge_distance.y ? widths.y : edge == edge_distance.z ? widths.z : widths.w;
    float coordinate = edge == edge_distance.x || edge == edge_distance.z ? local_position.x : local_position.y;
    if (border_width > 0.0 && distance >= -border_width &&
        !(dash == 1.0 && mod(coordinate, 6.0) >= 3.0)) fill = border;
    fill.a *= coverage;
  } else if (center_kind.w == 4.0) {
    float margin = dash == 1.0 ? 0.0 : spread + center_kind.z * 3.0 + 1.0;
    vec2 original_size = primitive_size - 2.0 * margin;
    vec2 p = local_position - margin;
    float radius = p.y < original_size.y/2.0 ? (p.x < original_size.x/2.0 ? radii.x : radii.y) : (p.x < original_size.x/2.0 ? radii.w : radii.z);
    radius = clamp(radius, 0.0, min(original_size.x,original_size.y)/2.0);
    vec2 q = abs(p - original_size/2.0) - original_size/2.0 + radius;
    float distance = length(max(q,0.0)) + min(max(q.x,q.y),0.0) - radius;
    float sigma = center_kind.z;
    float coverage = dash == 1.0
      ? clamp(0.5 - distance, 0.0, 1.0) * (sigma == 0.0 ? clamp(distance + spread + 0.5, 0.0, 1.0) : 0.5 + 0.5 * approx_erf((distance + spread) / (sigma * 1.41421356237)))
      : sigma == 0.0 ? clamp(0.5 - distance + spread, 0.0, 1.0) : 0.5 - 0.5 * approx_erf((distance - spread) / (sigma * 1.41421356237));
    fill.a *= coverage;
  } else if (center_kind.w == 1.0 || center_kind.w == 2.0) {
    vec2 uv = widths.xy + local_position / primitive_size * widths.zw;
    vec4 sample_color = texture(atlas, uv);
    if (center_kind.w == 1.0) fill.a *= sample_color.r;
    else fill *= sample_color;
  }
  fragment_color = vec4(fill.rgb * fill.a, fill.a);
}
