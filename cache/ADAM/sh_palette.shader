//
// ADAM - passthrough vertex shader for the palette-indexed backdrop
//
attribute vec3 in_Position;
attribute vec4 in_Colour;
attribute vec2 in_TextureCoord;

varying vec2 v_vTexcoord;
varying vec4 v_vColour;

void main()
{
    vec4 object_space_pos = vec4(in_Position.x, in_Position.y, in_Position.z, 1.0);
    gl_Position = gm_Matrices[MATRIX_WORLD_VIEW_PROJECTION] * object_space_pos;
    v_vColour = in_Colour;
    v_vTexcoord = in_TextureCoord;
}

//######################_==_YOYO_SHADER_MARKER_==_######################@~
//
// ADAM - draws a palette-index surface through the Amiga palette.
// The colour index is stored in the red OR blue channel (the other is 0),
// so the result is the same whichever byte order the surface uses.
// With the copper sky on, colour 0 shows the sky instead: u_sky_tex is a
// 256 x 1 strip holding the exact colour the copper writes on each line
// (sky_table - 12-bit or 24-bit, with the line blending).
//
varying vec2 v_vTexcoord;
varying vec4 v_vColour;

uniform vec3 u_pal[128];
uniform float u_sky_on;
uniform sampler2D u_sky_tex;
// screen line = texture y * u_sky_map.x + u_sky_map.y (backdrop: 256, 0;
// a tile map: its height and minus the camera; a single tile: 0 and a line)
uniform vec2 u_sky_map;

void main()
{
    vec4 t = texture2D(gm_BaseTexture, v_vTexcoord);
    float idx = floor((t.r + t.b) * 255.0 + 0.5);
    vec3 c = u_pal[0];
    for (int k = 1; k < 128; k++)
    {
        if (float(k) == idx)
        {
            c = u_pal[k];
        }
    }
    if (idx < 0.5 && u_sky_on > 0.5)
    {
        float line = clamp(floor(v_vTexcoord.y * u_sky_map.x + u_sky_map.y), 0.0, 255.0);
        c = texture2D(u_sky_tex, vec2((line + 0.5) / 256.0, 0.5)).rgb;
    }
    gl_FragColor = vec4(c, t.a * v_vColour.a);
}

