//!HOOK MAIN
//!BIND HOOKED
//!DESC Retro TV Scanlines

vec4 hook() {
    vec4 color = HOOKED_tex(HOOKED_pos);

    float line = mod(floor(gl_FragCoord.y), 2.0);
    float brightness = mix(0.20, 1.0, line);

    color.rgb *= brightness;
    return color;
}
