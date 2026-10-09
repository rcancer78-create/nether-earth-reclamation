shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 base_color : source_color = vec4(0.21,0.235,0.23,1.0);
varying vec3 world;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) { vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y); }
void vertex() { world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
 float n=noise(world.xz*0.12)*0.5+noise(world.xz*1.8)*0.3+noise(world.xz*15.0)*0.2;
 vec2 grid=abs(fract(world.xz/6.0-0.5)-0.5)/fwidth(world.xz/6.0);
 float line=1.0-min(min(grid.x,grid.y),1.0);
 ALBEDO=base_color.rgb*(0.64+n*0.65)+line*vec3(0.013,0.022,0.022);
 ROUGHNESS=0.86;
 METALLIC=0.08;
}
