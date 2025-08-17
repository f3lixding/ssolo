//
// Menu shader for UI elements
//
@vs vs
in vec2 pos;
in vec4 color0;
in vec2 uv0;

out vec4 color;
out vec2 uv;

void main() {
    gl_Position = vec4(pos, 0.0, 1.0);
    color = color0;
    uv = vec2(uv0.x, uv0.y);
}
@end

@fs fs
in vec4 color;
in vec2 uv;
out vec4 frag_color;

void main() {
    frag_color = color;
}
@end

@program menu vs fs