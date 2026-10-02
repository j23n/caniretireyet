"""Builds App/Resources/Assets.xcassets/AppIcon.appiconset from build/*.png
(made by render.mjs). Needs Pillow. The iOS icon is written without an alpha
channel, as the App Store requires; dark and tinted keep their transparency."""
import json
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Assets.xcassets", "AppIcon.appiconset")
os.makedirs(OUT, exist_ok=True)

def built(name):
    return Image.open(os.path.join(HERE, "build", f"{name}.png"))

built("AppIcon").convert("RGB").save(os.path.join(OUT, "AppIcon-iOS.png"))
built("AppIcon-Dark").convert("RGBA").save(os.path.join(OUT, "AppIcon-iOS-Dark.png"))
built("AppIcon-Tinted").convert("RGBA").save(os.path.join(OUT, "AppIcon-iOS-Tinted.png"))
images = [
    {"filename": "AppIcon-iOS.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
    {"appearances": [{"appearance": "luminosity", "value": "dark"}], "filename": "AppIcon-iOS-Dark.png",
     "idiom": "universal", "platform": "ios", "size": "1024x1024"},
    {"appearances": [{"appearance": "luminosity", "value": "tinted"}], "filename": "AppIcon-iOS-Tinted.png",
     "idiom": "universal", "platform": "ios", "size": "1024x1024"},
]
mac = built("AppIcon-Mac").convert("RGBA")
for points in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        name = f"AppIcon-Mac-{points}@{scale}x.png"
        mac.resize((points * scale,) * 2, Image.LANCZOS).save(os.path.join(OUT, name))
        images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{points}x{points}"})
with open(os.path.join(OUT, "Contents.json"), "w") as file:
    json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, file, indent=2)
