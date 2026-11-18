shader_type spatial;
#include "res://addons/npr_character_frame/shaders/common/npr_surface_features.gdshaderinc"
render_mode diffuse_burley,specular_schlick_ggx;
uniform bool u_npr_posterior_enabled=false;
varying vec3 posterior_linear;
varying flat float posterior_domain;
varying vec3 posterior_world;
void vertex(){vec3 c=CUSTOM2.rgb;posterior_linear=mix(pow((c+vec3(0.055))/1.055,vec3(2.4)),c/12.92,lessThanEqual(c,vec3(0.04045)));posterior_domain=CUSTOM3.x;posterior_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){if(!u_npr_posterior_enabled || posterior_domain<0.5){discard;} if(!npr_visibility_keep(FRAGCOORD.xy)){discard;} if(npr_dissolve_signed_distance(UV,posterior_world,0.0)<0.0){discard;} ALBEDO=posterior_linear;ROUGHNESS=0.8;SPECULAR=0.0;}
