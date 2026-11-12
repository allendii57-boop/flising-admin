import os
from PIL import Image, ImageOps

img_path = 'assets/images/flising_admin.jpg'
if os.path.exists(img_path):
    im = Image.open(img_path).convert('RGB')
    # Add 15% dark padding to match the framed squircle layout perfectly
    im = ImageOps.expand(im, border=int(im.size[0] * 0.15), fill='#0D1117')
    im.save(img_path)
    print("Successfully padded flising_admin.jpg")
else:
    print("Logo not found at", img_path)
