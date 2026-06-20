shader_type canvas_item;

// ============================================================================
//  comic_post_fx.gdshader — screen-space comic / Spider-Verse post pass
// ----------------------------------------------------------------------------
//  Drives the whole frame toward 04_Art_Direction's "moving graffiti mural —
//  loud, saturated, comic book" look. Four independent, individually-tunable
//  effects composited in one canvas_item pass:
//
//    1. Posterize + saturation  -> cel colour banding, kills muddy midtones
//    2. Halftone / ben-day dots  -> screen-space dot pattern, concentrated in
//                                   shadow so the bright track stays clean
//    3. Ink edge outline (Sobel) -> dark graphic linework on contrast edges
//    4. Chromatic aberration     -> mild RGB split, scaled toward screen edge
//
//  Every knob is a uniform with a matching @export in ComicPostFX.gd, so the
//  dev tunes live in the inspector. Each effect has an *_intensity uniform
//  where 0.0 == fully off; defaults are deliberately SUBTLE because the art
//  doc treats track readability as sacred (VFX must never make the track
//  harder to read).
//
//  WHY canvas_item luminance Sobel (and not depth/normal edges):
//  -------------------------------------------------------------
//  A plain canvas_item shader can sample hint_screen_texture but has NO access
//  to hint_depth_texture / scene normals (those exist only in spatial shaders).
//  Clean geometry-edge outlines would need a CompositorEffect (compute) or a
//  spatial quad — both heavier and harder to drop in / tune live. For a
//  prototype on a DARK background (#0D0D14) with emissive track edge lines, a
//  luminance-gradient Sobel already lands its ink almost entirely on the
//  readable track edges and the vehicle silhouette, which is exactly where we
//  want it. So: one self-contained canvas_item pass. Tradeoff = outlines key
//  off brightness contrast, not true depth, so very low-contrast seams won't
//  be inked. Acceptable (often desirable) for this art target. If the dev later
//  wants true depth edges, swap this single ColorRect for a CompositorEffect —
//  nothing else in the scene needs to change.
// ============================================================================

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

// --- master ---------------------------------------------------------------
// Global wet/dry. 0.0 returns the untouched frame (full bypass); 1.0 = full
// effect. Lets the dev A/B the entire pass against raw render with one slider.
uniform float master_mix : hint_range(0.0, 1.0) = 1.0;

// --- 1. posterize + saturation -------------------------------------------
uniform float posterize_intensity : hint_range(0.0, 1.0) = 0.6;   // blend toward banded colour
uniform float posterize_levels : hint_range(2.0, 16.0) = 6.0;     // colour steps per channel (low = chunkier cel look)
uniform float saturation_boost : hint_range(0.0, 2.0) = 0.35;     // extra saturation on top (0 = none)

// --- 2. halftone / ben-day dots ------------------------------------------
uniform float halftone_intensity : hint_range(0.0, 1.0) = 0.18;   // overall dot strength (kept low for readability)
uniform float halftone_scale : hint_range(20.0, 400.0) = 140.0;   // dots across the screen (higher = finer dots)
uniform float halftone_angle : hint_range(0.0, 1.5708) = 0.4;     // screen rotation of the dot grid (radians)
uniform vec3  halftone_color : source_color = vec3(0.05, 0.05, 0.08); // ink colour of the dots (near-black tint)
uniform float halftone_shadow_bias : hint_range(0.0, 1.0) = 0.7;  // 1.0 = dots only in shadows; 0.0 = dots everywhere

// --- 3. ink edge outline (Sobel on luminance) ----------------------------
uniform float outline_intensity : hint_range(0.0, 1.0) = 0.5;     // how strongly ink darkens edges
uniform float outline_thickness : hint_range(0.5, 4.0) = 1.2;     // Sobel sample spread, in pixels
uniform float outline_threshold : hint_range(0.0, 1.0) = 0.18;    // edge response below this is ignored (denoise)
uniform vec3  outline_color : source_color = vec3(0.02, 0.02, 0.04); // ink colour (near-black with a cool tint)

// --- 4. chromatic aberration ---------------------------------------------
uniform float aberration_intensity : hint_range(0.0, 1.0) = 0.25; // master strength of the RGB split
uniform float aberration_amount : hint_range(0.0, 8.0) = 1.6;     // max channel offset at the screen edge, in pixels
uniform float aberration_edge_falloff : hint_range(0.5, 4.0) = 2.0; // >1 keeps the centre clean, splits only the edges

// Rec.709 luminance.
float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// RGB <-> HSV so we can push saturation without shifting hue.
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;          // size of one screen pixel in UV space
	vec2 uv = SCREEN_UV;

	// Truly untouched frame, kept for the master wet/dry so master_mix == 0.0
	// is an exact bypass (no aberration leak).
	vec3 raw_col = texture(screen_tex, uv).rgb;

	// ---- 4. Chromatic aberration (sampled first so every later effect sees
	//         the split frame). Offset grows toward the screen edges. --------
	vec3 base_col;
	float edge = 0.0;
	if (aberration_intensity > 0.0001) {
		vec2 from_center = uv - vec2(0.5);
		edge = pow(clamp(length(from_center) * 2.0, 0.0, 1.0), aberration_edge_falloff);
		vec2 dir = from_center;            // push channels radially outward
		float mag = aberration_amount * aberration_intensity * edge;
		vec2 ofs = dir * mag * px;
		float r = texture(screen_tex, uv + ofs).r;
		float g = texture(screen_tex, uv).g;
		float b = texture(screen_tex, uv - ofs).b;
		base_col = vec3(r, g, b);
	} else {
		base_col = raw_col;
	}

	vec3 col = base_col;

	// ---- 1. Posterize + saturation ----------------------------------------
	if (posterize_intensity > 0.0001 || saturation_boost > 0.0001) {
		vec3 hsv = rgb2hsv(col);
		hsv.y = clamp(hsv.y * (1.0 + saturation_boost), 0.0, 1.0);  // richer colour, no muddy midtones
		vec3 saturated = hsv2rgb(hsv);

		float levels = max(posterize_levels, 2.0);
		vec3 banded = floor(saturated * levels + 0.5) / levels;      // quantise to cel steps
		col = mix(saturated, banded, posterize_intensity);
	}

	// ---- 3. Ink edge outline (Sobel on luminance of the screen) -----------
	//  Uses the raw screen_tex (not the posterized col) so banding steps don't
	//  register as fake edges. Dark linework is multiplied in, so it darkens
	//  toward outline_color rather than painting flat over the art.
	if (outline_intensity > 0.0001) {
		vec2 o = px * outline_thickness;
		float tl = luma(texture(screen_tex, uv + vec2(-o.x,  o.y)).rgb);
		float tc = luma(texture(screen_tex, uv + vec2( 0.0,  o.y)).rgb);
		float tr = luma(texture(screen_tex, uv + vec2( o.x,  o.y)).rgb);
		float ml = luma(texture(screen_tex, uv + vec2(-o.x,  0.0)).rgb);
		float mr = luma(texture(screen_tex, uv + vec2( o.x,  0.0)).rgb);
		float bl = luma(texture(screen_tex, uv + vec2(-o.x, -o.y)).rgb);
		float bc = luma(texture(screen_tex, uv + vec2( 0.0, -o.y)).rgb);
		float br = luma(texture(screen_tex, uv + vec2( o.x, -o.y)).rgb);

		float gx = (tr + 2.0 * mr + br) - (tl + 2.0 * ml + bl);
		float gy = (bl + 2.0 * bc + br) - (tl + 2.0 * tc + tr);
		float sobel = sqrt(gx * gx + gy * gy);

		// Soft threshold -> 0..1 ink mask.
		float ink = smoothstep(outline_threshold, outline_threshold + 0.25, sobel);
		ink *= outline_intensity;
		col = mix(col, outline_color, ink);
	}

	// ---- 2. Halftone / ben-day dots ---------------------------------------
	//  Classic rotated-grid dot screen. Dot radius tracks darkness so shadows
	//  fill with ink while highlights stay open — keeps the bright track clear.
	if (halftone_intensity > 0.0001) {
		// Rotate sample space, correct for aspect so dots stay round.
		float aspect = px.y / max(px.x, 1.0e-6);   // = viewport_width / viewport_height
		vec2 suv = uv * vec2(aspect, 1.0) * halftone_scale;
		float ca = cos(halftone_angle);
		float sa = sin(halftone_angle);
		vec2 ruv = vec2(suv.x * ca - suv.y * sa, suv.x * sa + suv.y * ca);

		vec2 cell = fract(ruv) - 0.5;
		float dist = length(cell);

		// Darker pixels -> bigger dots. shadow_bias controls how much brightness
		// gates the dots (1.0 = highlights are dot-free).
		float bright = luma(col);
		float tone = mix(0.5, 1.0 - bright, halftone_shadow_bias);   // 0..1 dot fill amount
		float radius = sqrt(clamp(tone, 0.0, 1.0)) * 0.5;            // area ~ tone
		float aa = fwidth(dist) + 1.0e-4;
		float dot = 1.0 - smoothstep(radius - aa, radius + aa, dist); // 1 inside dot

		col = mix(col, halftone_color, dot * halftone_intensity);
	}

	// ---- master wet/dry ----------------------------------------------------
	col = mix(raw_col, col, master_mix);

	COLOR = vec4(col, 1.0);
}
