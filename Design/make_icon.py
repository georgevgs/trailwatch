"""Draws the Watch app icon: the Kaisariani loop in amber on the terrain green.

Run from the repo root: python3 Design/make_icon.py
"""
import math
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw

GPX = "TrailKit/Tests/TrailKitTests/Fixtures/kaisariani_megalos_kyklos.gpx"
OUT = "WatchApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
SIZE, SS = 1024, 4  # draw 4x larger, then downscale for smooth edges
TERRAIN, CONTOUR, ACCENT, CASING = "#18241E", "#24342B", "#E8B85A", "#0B110E"

ns = "{http://www.topografix.com/GPX/1/1}"
pts = [(float(p.get("lat")), float(p.get("lon"))) for p in ET.parse(GPX).getroot().iter(ns + "trkpt")]
k = math.cos(math.radians(pts[0][0]))
flat = [(lon * k, -lat) for lat, lon in pts]
xs, ys = [p[0] for p in flat], [p[1] for p in flat]
w, h = max(xs) - min(xs), max(ys) - min(ys)
box = SIZE * SS * 0.56  # the watch masks the icon to a circle; keep the route well inside it
scale = box / max(w, h)
ox = (SIZE * SS - w * scale) / 2 - min(xs) * scale
oy = (SIZE * SS - h * scale) / 2 - min(ys) * scale
line = [(ox + x * scale, oy + y * scale) for x, y in flat]

img = Image.new("RGB", (SIZE * SS, SIZE * SS), TERRAIN)
d = ImageDraw.Draw(img)
c = SIZE * SS / 2
for r in (0.18, 0.30, 0.42, 0.54):  # faint contour rings, as on the design's map
    rr = r * SIZE * SS
    d.ellipse((c - rr * 1.1, c - rr, c + rr * 1.1, c + rr), outline=CONTOUR, width=6 * SS)
d.line(line, fill=CASING, width=86 * SS, joint="curve")
d.line(line, fill=ACCENT, width=52 * SS, joint="curve")
x, y = line[0]  # white start dot
r = 44 * SS
d.ellipse((x - r, y - r, x + r, y + r), fill="#F4F5F7", outline=TERRAIN, width=14 * SS)
img.resize((SIZE, SIZE), Image.LANCZOS).save(OUT)
print("wrote", OUT)
