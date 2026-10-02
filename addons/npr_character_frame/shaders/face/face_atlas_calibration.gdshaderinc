// Authored normalized Face texture coordinates, after fragment Y flip.
// No sample layout fallback; ordinary base rendering does not require this profile.
group_uniforms u_npr_face_atlas;
uniform bool u_npr_face_atlas_enabled = false;
uniform vec2 u_npr_face_atlas_accent_uv_min = vec2(0.0);
uniform vec2 u_npr_face_atlas_accent_uv_max = vec2(0.0);
uniform vec2 u_npr_face_atlas_accent_plate_uv = vec2(0.0);
uniform float u_npr_face_atlas_skin_sample_v = 0.0;
uniform vec2 u_npr_face_atlas_replacement_eye_a_max_uv = vec2(0.0);
uniform float u_npr_face_atlas_replacement_eye_b_min_u = 0.0;
uniform vec2 u_npr_face_atlas_replacement_eye_b_v_range = vec2(0.0);
uniform vec2 u_npr_face_atlas_round_eye_center_uv = vec2(0.0);
uniform vec2 u_npr_face_atlas_round_eye_aspect = vec2(0.0);
uniform vec2 u_npr_face_atlas_round_eye_pupil_radii = vec2(0.0);
uniform vec2 u_npr_face_atlas_round_eye_disc_radii = vec2(0.0);
group_uniforms;

bool npr_face_atlas_replacement_eye(vec2 uv) {
	// Preserve open half-spaces, including UV0/negative/repeat coordinates.
	return (uv.x < u_npr_face_atlas_replacement_eye_a_max_uv.x
			&& uv.y < u_npr_face_atlas_replacement_eye_a_max_uv.y)
		|| (uv.x > u_npr_face_atlas_replacement_eye_b_min_u
			&& uv.y > u_npr_face_atlas_replacement_eye_b_v_range.x
			&& uv.y < u_npr_face_atlas_replacement_eye_b_v_range.y);
}
