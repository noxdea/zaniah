#version 450

layout(location = 0) in vec4 instance_bounds;
layout(location = 1) in vec4 instance_color;
layout(location = 2) in vec4 instance_secondary;
layout(location = 3) in vec4 instance_radii;
layout(location = 4) in vec4 instance_border;
layout(location = 5) in vec4 instance_widths;
layout(location = 6) in vec4 instance_gradient;
layout(location = 7) in vec4 instance_center_kind;
layout(location = 8) in vec4 instance_matrix;
layout(location = 9) in vec4 instance_translation;

layout(push_constant) uniform Viewport { vec2 size; } viewport;

layout(location = 0) out vec2 local_position;
layout(location = 1) out vec2 primitive_size;
layout(location = 2) out vec4 color;
layout(location = 3) out vec4 secondary;
layout(location = 4) out vec4 radii;
layout(location = 5) out vec4 border;
layout(location = 6) out vec4 widths;
layout(location = 7) out vec4 gradient;
layout(location = 8) out vec4 center_kind;
layout(location = 9) out float dash;
layout(location = 10) out float spread;

void main() {
  vec2 corners[4] = vec2[4](vec2(0, 0), vec2(1, 0), vec2(0, 1), vec2(1, 1));
  vec2 corner = corners[gl_VertexIndex];
  vec2 size = instance_bounds.zw;
  vec2 position = instance_bounds.xy + corner * size;
  if (instance_center_kind.w == 3.0) {
    position = gl_VertexIndex == 0 ? instance_bounds.xy
      : gl_VertexIndex == 1 ? instance_bounds.zw : instance_radii.xy;
  }
  position = vec2(instance_matrix.x * position.x + instance_matrix.z * position.y + instance_translation.x,
                  instance_matrix.y * position.x + instance_matrix.w * position.y + instance_translation.y);
  gl_Position = vec4(position.x / viewport.size.x * 2.0 - 1.0,
                     position.y / viewport.size.y * 2.0 - 1.0, 0.0, 1.0);
  local_position = corner * size;
  primitive_size = size;
  color = instance_color;
  secondary = instance_secondary;
  radii = instance_radii;
  border = instance_border;
  widths = instance_widths;
  gradient = instance_gradient;
  center_kind = instance_center_kind;
  dash = instance_translation.w;
  spread = instance_translation.z;
}
