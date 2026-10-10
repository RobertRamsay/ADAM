//
// ADAM - draws a palette-index surface through the Amiga palette.
// The colour index is stored in the red OR blue channel (the other is 0),
// so the result is the same whichever byte order the surface uses.
//
varying vec2 v_vTexcoord;
varying vec4 v_vColour;

uniform vec3 u_pal[128];

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
    gl_FragColor = vec4(c, v_vColour.a);
}
