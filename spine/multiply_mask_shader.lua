local shader_code = [[
    vec4 effect(vec4 color, Image texture, vec2 texCoords, vec2 screenCoords) {
        vec4 t = Texel(texture, texCoords);
        float a = t.a;
        vec3 base = a > 0.0 ? t.rgb / a : vec3(1.0);
        vec3 factor = mix(vec3(1.0), base, a);
        return vec4(factor, a) * color;
    }
]]

local ok, shader = pcall(love.graphics.newShader, shader_code)
if ok then
    return shader
else
    return nil
end

