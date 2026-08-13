#version 460 core

// Paper stuck to a wall.
//
// The depth map is the only real input: everything the eye reads as "this is
// lying on a surface" is derived from its slope, in one pass.
//
//   1. the print bends where the plaster rises or dips  (UV displacement)
//   2. the wall's light falls across the print          (normal from gradient)
//   3. a little of the wall's own grain shows through   (luminance modulation)
//
// Sampling the wall and the depth in WINDOW space rather than in the quad's own
// space is what keeps the brick courses running from one poster into the wall
// and on into the next. uOrigin is where this quad sits on screen; without it
// every poster would restart the same brick in its own corner.

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;    // the quad being painted, in pixels
uniform vec2 uOrigin;  // its top-left, in window pixels
uniform vec2 uWall;    // the window, i.e. the wall's on-screen extent

uniform float uDisplacement;    // how far the print slides down a slope
uniform float uTextureStrength; // how much wall grain shows through the paper
uniform float uBumpStrength;    // how steep the derived normal is
uniform float uLightAngle;      // radians, 0 = from the right
uniform float uLightDepth;      // z of the light vector; low = raking, harsh
uniform float uAmbient;         // brightness of a fully unlit patch
uniform float uGain;            // brightness of a fully lit one
uniform float uSampleSpread;    // gradient sample distance, in wall pixels
uniform float uPaperStrength;   // paper noise and grunge over the print
uniform float uWash;            // print wash: desaturate and lift the blacks

uniform sampler2D uPoster;
uniform sampler2D uWallTex;
uniform sampler2D uDepth;
uniform sampler2D uPaper;

out vec4 fragColor;

void main() {
    vec2 frag = FlutterFragCoord().xy;
    vec2 quadUV = frag / uSize;

    // Where this fragment lands on the wall, not on the poster.
    vec2 wallUV = (frag + uOrigin) / uWall;
    vec2 step = uSampleSpread / uWall;

    float dl = texture(uDepth, wallUV - vec2(step.x, 0.0)).r;
    float dr = texture(uDepth, wallUV + vec2(step.x, 0.0)).r;
    float du = texture(uDepth, wallUV - vec2(0.0, step.y)).r;
    float dd = texture(uDepth, wallUV + vec2(0.0, step.y)).r;

    vec2 gradient = vec2(dr - dl, dd - du);

    // 1. The print follows the surface it is stuck to.
    vec2 posterUV = clamp(quadUV + gradient * uDisplacement, 0.0, 1.0);
    vec4 poster = texture(uPoster, posterUV);

    // 2. The wall's relief lights the paper lying on it. Cheap normal: the
    //    slope in x and y, with z standing in for how steep we claim it is.
    vec3 normal = normalize(vec3(
        -gradient.x * uBumpStrength,
        -gradient.y * uBumpStrength,
        1.0
    ));
    vec3 light = normalize(vec3(
        cos(uLightAngle),
        sin(uLightAngle),
        uLightDepth
    ));
    float diffuse = clamp(dot(normal, light), 0.0, 1.0);
    float lighting = mix(uAmbient, uGain, diffuse);

    // 3. A trace of the wall's own grain, through the paper. Kept small on
    //    purpose: push this up and the poster stops looking like paper and
    //    starts looking transparent.
    vec3 wall = texture(uWallTex, wallUV).rgb;
    float wallLum = dot(wall, vec3(0.299, 0.587, 0.114));
    float grain = mix(1.0, wallLum * 1.5, uTextureStrength);

    poster.rgb *= lighting * grain;

    // 4. The print wash. Approximates the ColorFilter the soft-light path uses:
    //    pull the colour back and lift the blacks off true black, so the image
    //    sits in the paper rather than glowing through it.
    float lum = dot(poster.rgb, vec3(0.299, 0.587, 0.114));
    poster.rgb = mix(poster.rgb, vec3(lum), 0.14 * uWash);
    poster.rgb += vec3(0.023, 0.020, 0.016) * uWash;

    // 5. The paper itself — its noise, grunge and edge wear, over everything.
    //    Sampled in the quad's own space, not the wall's: the sheet belongs to
    //    this poster and moves with it, unlike the brick behind it.
    vec4 paper = texture(uPaper, quadUV);
    float paperA = paper.a * uPaperStrength;
    poster.rgb = poster.rgb * (1.0 - paperA) + paper.rgb * uPaperStrength;

    fragColor = poster;
}
