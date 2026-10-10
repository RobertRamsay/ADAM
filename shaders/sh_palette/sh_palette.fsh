//
// ADAM - draws a palette-index surface through the Amiga palette.
// The colour index is stored in the red OR blue channel (the other is 0),
// so the result is the same whichever byte order the surface uses.
// With the copper sky on, colour 0 shows the sky gradient instead, rounded
// to 12-bit colour exactly as the Amiga's copper list writes it.
//
varying vec2 v_vTexcoord;
varying vec4 v_vColour;

uniform vec3 u_pal[128];
uniform float u_sky_on;
uniform vec3 u_sky_top;
uniform vec3 u_sky_mid;
uniform vec3 u_sky_bot;
uniform float u_sky_midy;

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
        float line = floor(v_vTexcoord.y * 256.0);
        vec3 s;
        if (line <= u_sky_midy)
        {
            s = mix(u_sky_top, u_sky_mid, line / max(u_sky_midy, 1.0));
        }
        else
        {
            s = mix(u_sky_mid, u_sky_bot, (line - u_sky_midy) / max(255.0 - u_sky_midy, 1.0));
        }
        c = floor(s * 15.0 + 0.5) / 15.0;
    }
    gl_FragColor = vec4(c, t.a * v_vColour.a);
}
