import kitty_custom_shader_types;

static const bool MOTION_BLUR = true;
static const int MOTION_BLUR_SAMPLES = 16;
static const bool ANTIALIASING = false;
static const bool CONNECTED = false;

static float
outside_edge(float2 p, float2 a, float2 b, float orientation) {
    float2 e = b - a;
    float dist = orientation * (e.x * (p.y - a.y) - e.y * (p.x - a.x)) / length(e);
    if (!ANTIALIASING) return dist < 0.0 ? 1.0 : 0.0;
    return 1.0 - saturate(0.5 + dist);
}

static float
triangle_coverage(float2 p, float2 a, float2 b, float2 c) {
    float area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
    if (abs(area) < 1e-6) return 0.0;
    float orientation = area > 0.0 ? 1.0 : -1.0;
    return saturate(1.0 - outside_edge(p, a, b, orientation) - outside_edge(p, b, c, orientation) - outside_edge(p, c, a, orientation));
}

static float
trail_coverage(float2 p, float4 xs, float4 ys) {
    float2 c0 = float2(xs.x, ys.x);
    float2 c1 = float2(xs.y, ys.y);
    float2 c2 = float2(xs.z, ys.z);
    float2 c3 = float2(xs.w, ys.w);
    return min(triangle_coverage(p, c0, c1, c2) + triangle_coverage(p, c0, c2, c3), 1.0);
}

static float
rect_coverage(float2 p, float2 lo, float2 hi) {
    if (!ANTIALIASING) return (p.x >= lo.x && p.x <= hi.x && p.y >= lo.y && p.y <= hi.y) ? 1.0 : 0.0;
    float2 overlap = saturate(min(p + 0.5, hi) - max(p - 0.5, lo));
    return overlap.x * overlap.y;
}

static float
min4(float4 v) {
    return min(min(v.x, v.y), min(v.z, v.w));
}

static float
max4(float4 v) {
    return max(max(v.x, v.y), max(v.z, v.w));
}

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float opacity = d.cursor_trail_color.a;
    if (opacity <= 0.0 || d.cursor_trail_state <= 0.0) return color;

    float2 pixel_dims = max(float2(d.viewport_size_pixels) * t.viewport.zw, float2(1.0));
    float2 p = t.pos * pixel_dims;
    float2 cursor_lo = float2(d.cursor_trail_edge.x, d.cursor_trail_edge.w) * pixel_dims;
    float2 cursor_hi = float2(d.cursor_trail_edge.y, d.cursor_trail_edge.z) * pixel_dims;

    float4 end_x = d.cursor_trail_corners_x * pixel_dims.x;
    float4 end_y = d.cursor_trail_corners_y * pixel_dims.y;
    if (MOTION_BLUR && CONNECTED) {
        end_x = float4(cursor_hi.x, cursor_hi.x, cursor_lo.x, cursor_lo.x);
        end_y = float4(cursor_hi.y, cursor_lo.y, cursor_lo.y, cursor_hi.y);
    }
    float4 start_x = MOTION_BLUR ? d.cursor_trail_prev_corners_x * pixel_dims.x : end_x;
    float4 start_y = MOTION_BLUR ? d.cursor_trail_prev_corners_y * pixel_dims.y : end_y;

    float2 swept_lo = float2(min(min4(start_x), min4(end_x)), min(min4(start_y), min4(end_y))) - 1.0;
    float2 swept_hi = float2(max(max4(start_x), max4(end_x)), max(max4(start_y), max4(end_y))) + 1.0;
    if (p.x < swept_lo.x || p.x > swept_hi.x || p.y < swept_lo.y || p.y > swept_hi.y) return color;

    const int samples = MOTION_BLUR ? clamp(MOTION_BLUR_SAMPLES, 1, 64) : 1;
    float coverage = 0.0;
    for (int i = 0; i < samples; i++) {
        float time = MOTION_BLUR ? (float(i) + 0.5) / float(samples) : 1.0;
        coverage += trail_coverage(p, lerp(start_x, end_x, time), lerp(start_y, end_y, time));
    }
    coverage /= float(samples);

    coverage *= 1.0 - rect_coverage(p, cursor_lo, cursor_hi);
    if (coverage <= 0.0) return color;

    return float4(lerp(color.rgb, d.cursor_trail_color.rgb, saturate(opacity * coverage)), color.a);
}
