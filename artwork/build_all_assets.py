#!/usr/bin/env python3
import os
import subprocess
import shutil

ARTWORK_DIR = "/Users/zSimoz/Projects/snowdrop/artwork"
MACOS_RES_DIR = "/Users/zSimoz/Projects/snowdrop/macos/Resources"
ANDROID_RES_DIR = "/Users/zSimoz/Projects/snowdrop/android/app/src/main/res"

os.makedirs(ARTWORK_DIR, exist_ok=True)
os.makedirs(MACOS_RES_DIR, exist_ok=True)

# ---------------------------------------------------------------------------
# 1. macOS Menu Bar Icon (Monochrome Template SVG)
# ---------------------------------------------------------------------------
menubar_svg = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <defs>
    <mask id="petal-mask">
      <rect width="512" height="512" fill="white"/>
      <path d="M 256,52 C 286,125 288,218 256,290 C 224,218 226,125 256,52 Z"
            fill="black" stroke="black" stroke-width="16" stroke-linejoin="round"/>
    </mask>
  </defs>

  <g transform="translate(0, 16)">
    <!-- Seamless Fluting Outer Shell + Stem -->
    <path d="M 245,365
             C 245,320 242,285 225,255
             C 205,220 138,180 142,120
             C 145,94 175,102 192,122
             C 218,154 238,230 252,278
             C 253,282 259,282 260,278
             C 274,230 294,154 320,122
             C 337,102 367,94 370,120
             C 374,180 307,220 287,255
             C 270,285 267,320 267,365
             A 11,11 0 0,1 245,365
             Z"
          fill="#000000"
          mask="url(#petal-mask)"/>

    <!-- Dominant Center Petal -->
    <path d="M 256,52
             C 286,125 288,218 256,290 C 224,218 226,125 256,52 Z"
          fill="#000000"/>
  </g>
</svg>"""

with open(f"{ARTWORK_DIR}/snowdrop_menubar_template.svg", "w") as f:
    f.write(menubar_svg)

print("1. Render master menu bar PNGs...")
subprocess.run(["qlmanage", "-t", "-s", "256", "-o", "/tmp", f"{ARTWORK_DIR}/snowdrop_menubar_template.svg"], check=True)
subprocess.run(["sips", "-z", "18", "18", "/tmp/snowdrop_menubar_template.svg.png", "--out", f"{MACOS_RES_DIR}/MenuBarIcon.png"], check=True)
subprocess.run(["sips", "-z", "36", "36", "/tmp/snowdrop_menubar_template.svg.png", "--out", f"{MACOS_RES_DIR}/MenuBarIcon@2x.png"], check=True)
print("   -> MenuBarIcon.png & MenuBarIcon@2x.png created in macos/Resources")

# ---------------------------------------------------------------------------
# 2. macOS AppIcon.icns
# ---------------------------------------------------------------------------
print("2. Generating macOS AppIcon.icns...")
iconset_dir = "/tmp/AppIcon.iconset"
shutil.rmtree(iconset_dir, ignore_errors=True)
os.makedirs(iconset_dir, exist_ok=True)

# Master 1024x1024 PNG from seamless app icon
subprocess.run(["qlmanage", "-t", "-s", "1024", "-o", "/tmp", f"{ARTWORK_DIR}/snowdrop_logo_seamless.svg"], check=True)
master_1024 = "/tmp/snowdrop_logo_seamless.svg.png"

sizes = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for filename, size in sizes:
    subprocess.run(["sips", "-z", str(size), str(size), master_1024, "--out", f"{iconset_dir}/{filename}"], check=True, stdout=subprocess.DEVNULL)

subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", f"{MACOS_RES_DIR}/AppIcon.icns"], check=True)
print("   -> AppIcon.icns created in macos/Resources")

# ---------------------------------------------------------------------------
# 3. Android Adaptive & Legacy Icons
# ---------------------------------------------------------------------------
print("3. Generating Android Resources...")

# Circular master icon for Android round icon
circle_svg = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <circle cx="256" cy="256" r="256" fill="#0F172A"/>
  
  <g id="snowdrop-mark" transform="translate(0, 24)">
    <path d="M 245,365
             C 245,320 242,285 225,255
             C 205,220 138,180 142,120
             C 145,94 175,102 192,122
             C 218,154 238,230 252,278
             C 253,282 259,282 260,278
             C 274,230 294,154 320,122
             C 337,102 367,94 370,120
             C 374,180 307,220 287,255
             C 270,285 267,320 267,365
             A 11,11 0 0,1 245,365
             Z"
          fill="#38BDF8"/>
    <path d="M 248,278
             C 226,252 178,195 184,136
             C 186,116 206,120 218,136
             C 238,164 248,225 253,268
             Z"
          fill="#BAE6FD"/>
    <path d="M 264,278
             C 286,252 334,195 328,136
             C 326,116 306,120 294,136
             C 274,164 264,225 259,268
             Z"
          fill="#BAE6FD"/>
    <path d="M 256,52
             C 286,125 288,218 256,290
             C 224,218 226,125 256,52
             Z"
          fill="#FFFFFF"/>
  </g>
</svg>"""

with open(f"{ARTWORK_DIR}/snowdrop_logo_round.svg", "w") as f:
    f.write(circle_svg)

subprocess.run(["qlmanage", "-t", "-s", "1024", "-o", "/tmp", f"{ARTWORK_DIR}/snowdrop_logo_round.svg"], check=True)
master_round_1024 = "/tmp/snowdrop_logo_round.svg.png"

# Colors: define ic_launcher_background
colors_xml_path = f"{ANDROID_RES_DIR}/values/colors.xml"
colors_content = """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#0F172A</color>
</resources>
"""
with open(colors_xml_path, "w") as f:
    f.write(colors_content)

# Android Vector Foreground (108dp x 108dp viewport, centered flower scaled ~0.14)
# 512 * 0.13 = 66.5dp, centered: (108 - 66.5) / 2 = 20.75dp
foreground_vector = """<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <group
        android:scaleX="0.13"
        android:scaleY="0.13"
        android:translateX="20.7"
        android:translateY="20.7">
        <group android:translateY="24">
            <!-- Stem and outer petals (unified) -->
            <path
                android:fillColor="#38BDF8"
                android:pathData="M 245,365 C 245,320 242,285 225,255 C 205,220 138,180 142,120 C 145,94 175,102 192,122 C 218,154 238,230 252,278 C 253,282 259,282 260,278 C 274,230 294,154 320,122 C 337,102 367,94 370,120 C 374,180 307,220 287,255 C 270,285 267,320 267,365 A 11,11 0 0,1 245,365 Z" />
            <!-- Left inner depth petal -->
            <path
                android:fillColor="#BAE6FD"
                android:pathData="M 248,278 C 226,252 178,195 184,136 C 186,116 206,120 218,136 C 238,164 248,225 253,268 Z" />
            <!-- Right inner depth petal -->
            <path
                android:fillColor="#BAE6FD"
                android:pathData="M 264,278 C 286,252 334,195 328,136 C 326,116 306,120 294,136 C 274,164 264,225 259,268 Z" />
            <!-- Center white petal -->
            <path
                android:fillColor="#FFFFFF"
                android:pathData="M 256,52 C 286,125 288,218 256,290 C 224,218 226,125 256,52 Z" />
        </group>
    </group>
</vector>
"""
os.makedirs(f"{ANDROID_RES_DIR}/drawable", exist_ok=True)
with open(f"{ANDROID_RES_DIR}/drawable/ic_launcher_foreground.xml", "w") as f:
    f.write(foreground_vector)

# Notification icon (pure white vector silhouette for status bar)
notification_vector = """<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <group
        android:scaleX="0.04"
        android:scaleY="0.04"
        android:translateX="1.76"
        android:translateY="2.0">
        <path
            android:fillColor="#FFFFFFFF"
            android:pathData="M 245,365 C 245,320 242,285 225,255 C 205,220 138,180 142,120 C 145,94 175,102 192,122 C 218,154 238,230 252,278 C 253,282 259,282 260,278 C 274,230 294,154 320,122 C 337,102 367,94 370,120 C 374,180 307,220 287,255 C 270,285 267,320 267,365 A 11,11 0 0,1 245,365 Z" />
        <path
            android:fillColor="#FFFFFFFF"
            android:pathData="M 256,52 C 286,125 288,218 256,290 C 224,218 226,125 256,52 Z" />
    </group>
</vector>
"""
with open(f"{ANDROID_RES_DIR}/drawable/ic_snowdrop_notification.xml", "w") as f:
    f.write(notification_vector)

# Adaptive XML in mipmap-anydpi-v26
anydpi_dir = f"{ANDROID_RES_DIR}/mipmap-anydpi-v26"
os.makedirs(anydpi_dir, exist_ok=True)

adaptive_xml = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
"""
with open(f"{anydpi_dir}/ic_launcher.xml", "w") as f:
    f.write(adaptive_xml)
with open(f"{anydpi_dir}/ic_launcher_round.xml", "w") as f:
    f.write(adaptive_xml)

# Legacy raster icons across densities
android_densities = [
    ("mipmap-mdpi", 48),
    ("mipmap-hdpi", 72),
    ("mipmap-xhdpi", 96),
    ("mipmap-xxhdpi", 144),
    ("mipmap-xxxhdpi", 192),
]

for folder, size in android_densities:
    out_dir = f"{ANDROID_RES_DIR}/{folder}"
    os.makedirs(out_dir, exist_ok=True)
    subprocess.run(["sips", "-z", str(size), str(size), master_1024, "--out", f"{out_dir}/ic_launcher.png"], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["sips", "-z", str(size), str(size), master_round_1024, "--out", f"{out_dir}/ic_launcher_round.png"], check=True, stdout=subprocess.DEVNULL)

print("   -> All Android mipmaps and adaptive drawables created.")
print("Asset generation complete!")
