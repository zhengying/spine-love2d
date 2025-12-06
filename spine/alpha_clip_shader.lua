local shader_code = [[
    vec4 effect(vec4 color, Image texture, vec2 texCoords, vec2 screenCoords) {
        vec4 t = Texel(texture, texCoords);
        // Drop near-transparent fragments to avoid darkening in multiply
        if (t.a <= 0.0039) discard; // ~1/255
        return t * color;
    }
]]

local ok, shader = pcall(love.graphics.newShader, shader_code)
if ok then
    return shader
else
    return nil
end
