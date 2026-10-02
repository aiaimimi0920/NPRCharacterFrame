// Same 65-column rest aperture and curved shell as the authored sliding lids.
uniform vec4 eye_profile[65]; // upper Y, lower Y, upper Z, lower Z; eye-local.
uniform vec2 eye_bounds;
uniform float lid_closure = 0.0;
uniform float layer_depth = 0.0012;
uniform float closure_meeting = 0.72;
uniform float shell_offset = 0.00035;
uniform float shell_bulge_max = 0.008;
uniform float shell_bulge_ratio = 0.2;

vec4 npr_eye_profile(float x) {
	float u = clamp((x-eye_bounds.x)/(eye_bounds.y-eye_bounds.x),0.0,1.0)*64.0;
	int i = min(int(u),63);
	return mix(eye_profile[i],eye_profile[i+1],u-float(i));
}

bool npr_eye_aperture(vec2 p) {
	vec4 s = npr_eye_profile(p.x);
	float meeting = mix(s.x,s.y,closure_meeting);
	return lid_closure < 0.999999 && p.x >= eye_bounds.x && p.x <= eye_bounds.y
		&& p.y <= mix(s.x,meeting,lid_closure)
		&& p.y >= mix(s.y,meeting,lid_closure);
}

float npr_eye_depth(vec2 p) {
	vec4 s = npr_eye_profile(p.x);
	float gap = max(s.x-s.y,0.0000001);
	float t = clamp((s.x-p.y)/gap,0.0,1.0);
	return mix(s.z,s.w,t)+shell_offset+4.0*min(shell_bulge_max,gap*shell_bulge_ratio)*t*(1.0-t)-layer_depth;
}
