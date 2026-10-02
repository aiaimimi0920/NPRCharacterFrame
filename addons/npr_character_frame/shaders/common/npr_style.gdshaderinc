#ifndef NPR_STYLE_INCLUDED
#define NPR_STYLE_INCLUDED
// Local material values; never change a RenderingServer global to style one actor.
uniform bool u_npr_studio_enabled = false;
uniform float u_npr_ramp_mix : hint_range(0.0, 1.0) = 0.45;

float npr_ramp_mix(float captured) {
	return clamp(u_npr_studio_enabled ? u_npr_ramp_mix : captured, 0.0, 1.0);
}

bool npr_main_disabled(bool captured) {
	return !u_npr_studio_enabled && captured;
}
#endif
