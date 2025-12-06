-- Spine Tint Black Shader
-- Implements dual-color tinting: light color for bright pixels, dark color for dark pixels
-- This is used for the shine effect on the coin

local shader_code = [[
    uniform vec4 darkColor;
    
    vec4 effect(vec4 lightColor, Image texture, vec2 texture_coords, vec2 screen_coords) {
        vec4 texcolor = Texel(texture, texture_coords);
        float a = texcolor.a;
        vec3 base = a > 0.0 ? texcolor.rgb / a : vec3(0.0);
        vec3 mixed = mix(darkColor.rgb, lightColor.rgb, base);
        float outA = a * lightColor.a;
        return vec4(mixed * outA, outA);
    }
]]

return love.graphics.newShader(shader_code)
