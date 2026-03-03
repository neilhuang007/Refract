// HEAD

/*
    -- PATCH OVERWRITES --
*/
vec3 load_world_position();
void load_fragment_variables(out vec3 albedo, out vec3 world_pos, out vec3 world_normal, out vec3 world_normal_mapped);
vec3 sun_direction;
vec3 indirect_light_color;
vec3 get_sky_color(ivec2 gBufferLoc, vec3 worldPos, vec3 newNormal);