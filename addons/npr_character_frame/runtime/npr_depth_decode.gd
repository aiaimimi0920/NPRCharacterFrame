extends RefCounted
## GPU-only packed RG+coverage -> reconstructed normalized R32F depth.

# Cache keys include shader, sampler, source and target RIDs. The engine owns
# invalidation when any dependency is freed; cached sets must not be freed here.
var cache_uniforms := true
var _shader := RID()
var _pipeline := RID()
var _sampler := RID()


func copy(source: RID, target: RID, layer: int, size: Vector2i) -> Error:
	var rd := RenderingServer.get_rendering_device()
	if not _pipeline.is_valid():
		var code := RDShaderSource.new()
		code.source_compute = """
#version 450
layout(local_size_x=8, local_size_y=8, local_size_z=1) in;
layout(set=0, binding=0) uniform sampler2D packed_depth;
layout(r32f, set=0, binding=1) uniform writeonly image2DArray decoded_depth;
layout(push_constant, std430) uniform Params { ivec4 region; } params;
void main() {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(p, params.region.xy))) { return; }
    vec3 data = texelFetch(packed_depth, p, 0).rgb;
    float d = data.b > 0.5 ? dot(data.rg, vec2(1.0, 1.0 / 256.0)) : -1.0;
    imageStore(decoded_depth, ivec3(p, params.region.z), vec4(d, 0.0, 0.0, 0.0));
}
"""
		_shader = rd.shader_create_from_spirv(rd.shader_compile_spirv_from_source(code))
		if not _shader.is_valid():
			return ERR_CANT_CREATE
		_pipeline = rd.compute_pipeline_create(_shader)
		_sampler = rd.sampler_create(RDSamplerState.new())
		if not _pipeline.is_valid() or not _sampler.is_valid():
			release()
			return ERR_CANT_CREATE
	var input := RDUniform.new()
	input.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	input.binding = 0
	input.add_id(_sampler)
	input.add_id(source)
	var output := RDUniform.new()
	output.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output.binding = 1
	output.add_id(target)
	var uniforms: Array[RDUniform] = [input, output]
	var uniform_set := (
		UniformSetCacheRD.get_cache(_shader, 0, uniforms)
		if cache_uniforms
		else rd.uniform_set_create(uniforms, _shader, 0)
	)
	if not uniform_set.is_valid():
		return ERR_CANT_CREATE
	var commands := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(commands, _pipeline)
	rd.compute_list_bind_uniform_set(commands, uniform_set, 0)
	var parameters := PackedInt32Array([size.x, size.y, layer, 0]).to_byte_array()
	rd.compute_list_set_push_constant(commands, parameters, parameters.size())
	rd.compute_list_dispatch(commands, ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
	rd.compute_list_end()
	if not cache_uniforms:
		rd.free_rid(uniform_set)
	return OK


func release() -> void:
	var rd := RenderingServer.get_rendering_device()
	for handle in [_sampler, _pipeline, _shader]:
		if handle.is_valid():
			rd.free_rid(handle)
	_sampler = RID()
	_pipeline = RID()
	_shader = RID()
