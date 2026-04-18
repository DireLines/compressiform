from PIL import Image, ImageDraw, ImageFilter
import numpy as np
from scipy.ndimage import gaussian_filter
import colorsys
import argparse

# --- Sliders (defaults) ---
BASE_HUE   = 36   # degrees 0–360
BASE_SAT   = 0.41 # 0.0–1.0
BASE_VAL   = 0.73 # 0.0–1.0
GRAIN_AMP   = 10  # brightness units, roughly ± this value
GRAIN_SCALE = 3   # gaussian sigma in pixels (symmetric H/V)

parser = argparse.ArgumentParser()
parser.add_argument("--hue",         type=float, default=BASE_HUE)
parser.add_argument("--sat",         type=float, default=BASE_SAT)
parser.add_argument("--val",         type=float, default=BASE_VAL)
parser.add_argument("--grain-amp",   type=float, default=GRAIN_AMP)
parser.add_argument("--grain-scale", type=float, default=GRAIN_SCALE)
parser.add_argument("--scale",  type=float, default=1.0)
parser.add_argument("--output", type=str,   default="/Users/ryan/Desktop/gamejam/tablet.png")
args = parser.parse_args()

BASE_HUE, BASE_SAT, BASE_VAL, GRAIN_AMP, GRAIN_SCALE = args.hue, args.sat, args.val, args.grain_amp, args.grain_scale
W, H = round(2048 * args.scale), round(1536 * args.scale)

img = Image.new("RGBA", (W, H), (0, 0, 0, 0))

# --- Shape definition (no foreshortening: straight vertical sides) ---
S          = args.scale
margin_x   = round(80  * S)
margin_y   = round(30  * S)
arch_height = round(180 * S)
left_x     = margin_x
right_x    = W - margin_x
bottom_y   = H - margin_y
top_y      = margin_y + arch_height
arch_mid_y = margin_y
arch_cx    = W // 2
arch_w     = right_x - left_x

# Straight rectangular body polygon (no trapezoid)
tablet_poly = [
    (left_x,  top_y),
    (right_x, top_y),
    (right_x, bottom_y),
    (left_x,  bottom_y),
]

# --- Stone base color with per-pixel noise ---
rng = np.random.default_rng(42)

base_r, base_g, base_b = (round(c * 255) for c in colorsys.hsv_to_rgb(BASE_HUE / 360, BASE_SAT, BASE_VAL))

# Fine-grain high-frequency noise
noise = rng.integers(-18, 18, (H, W, 3), dtype=np.int16)

# Organic grain: anisotropic Gaussian-blurred noise — very wide in X, moderate in Y
# This creates slow-drifting, slightly wavy horizontal variation like natural stone
grain_raw = rng.standard_normal((H, W)).astype(np.float32)
grain = gaussian_filter(grain_raw, sigma=GRAIN_SCALE)
grain /= grain.std()                                   # normalize to unit std
grain = (grain * GRAIN_AMP).astype(np.int16)

stone_arr = np.clip(
    np.array([base_r, base_g, base_b], dtype=np.int16)
    + noise
    + grain[:, :, np.newaxis],
    0, 255
).astype(np.uint8)

stone_img = Image.fromarray(
    np.dstack([stone_arr, np.full((H, W), 255, dtype=np.uint8)]),
    "RGBA"
)

# --- Mask: rectangular body + arch top ---
mask = Image.new("L", (W, H), 0)
mask_draw = ImageDraw.Draw(mask)
mask_draw.polygon(tablet_poly, fill=255)

# Arch top: ellipse centered on top edge
mask_draw.ellipse(
    [arch_cx - arch_w // 2, arch_mid_y,
     arch_cx + arch_w // 2, top_y + (top_y - arch_mid_y)],
    fill=255
)

# Apply mask to stone texture
tablet = Image.new("RGBA", (W, H), (0, 0, 0, 0))
tablet.paste(stone_img, mask=mask)

# --- Edge darkening ---
shadow_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
shadow_draw  = ImageDraw.Draw(shadow_layer)

edge_color = (40, 28, 16, 110)
thickness  = 24

for i in range(thickness):
    t = i / thickness
    alpha = int(edge_color[3] * (1 - t))
    c = (*edge_color[:3], alpha)
    shrink = i * 1.1
    shadow_draw.polygon([
        (left_x  + shrink, top_y    + shrink),
        (right_x - shrink, top_y    + shrink),
        (right_x - shrink, bottom_y - shrink),
        (left_x  + shrink, bottom_y - shrink),
    ], outline=c)

shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=6))
tablet = Image.alpha_composite(tablet, shadow_layer)

# --- Highlight (top-left rim catch light) ---
hi_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
hi_draw  = ImageDraw.Draw(hi_layer)
hi_draw.line(
    [(left_x + 4, top_y + 8), (left_x + 4, bottom_y - 12)],
    fill=(232, 213, 163, 60), width=12
)
hi_draw.line(
    [(left_x + 4, top_y + 8), (arch_cx, arch_mid_y + 8)],
    fill=(232, 213, 163, 50), width=8
)
hi_layer = hi_layer.filter(ImageFilter.GaussianBlur(radius=8))
tablet = Image.alpha_composite(tablet, hi_layer)

# --- Final mask (clean alpha boundary) ---
final_mask = Image.new("L", (W, H), 0)
final_mask_draw = ImageDraw.Draw(final_mask)
final_mask_draw.polygon(tablet_poly, fill=255)
final_mask_draw.ellipse(
    [arch_cx - arch_w // 2, arch_mid_y,
     arch_cx + arch_w // 2, top_y + (top_y - arch_mid_y)],
    fill=255
)

out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
out.paste(tablet, mask=final_mask)

out.save(args.output)
print(f"Saved {args.output}")
