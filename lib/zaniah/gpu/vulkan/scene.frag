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

layout(set = 0, binding = 0) uniform sampler2D atlas;
layout(location = 0) out vec4 fragment_color;

void main() {
  vec4 fill = color;
  if (center_kind.w == 0.0) {
    if (gradient.x > 0.0) {
      vec2 normalized = local_position / primitive_size;
      float raw = gradient.x == 1.0
        ? dot(normalized - 0.5, vec2(cos(radians(gradient.w)), sin(radians(gradient.w)))) + 0.5
        : length(normalized - center_kind.xy) / center_kind.z;
      fill = mix(color, secondary,
        clamp((raw - gradient.y) / max(gradient.z - gradient.y, 0.000001), 0.0, 1.0));
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
  } else if (center_kind.w == 1.0 || center_kind.w == 2.0) {
    vec2 uv = widths.xy + local_position / primitive_size * widths.zw;
    vec4 sample_color = texture(atlas, uv);
    if (center_kind.w == 1.0) fill.a *= sample_color.r;
    else fill *= sample_color;
  }
  fragment_color = vec4(fill.rgb * fill.a, fill.a);
}
