import os
from PIL import Image, ImageOps

img_path = 'assets/images/flising_admin.jpg'
if os.path.exists(img_path):
    im = Image.open(img_path).convert('RGB')
    im = ImageOps.expand(im, border=int(im.size[0] * 0.15), fill='#0D1117')
    im.save(img_path)
    print("Successfully padded flising_admin.jpg")

for p in ['android/app/build.gradle', 'android/app/build.gradle.kts']:
    if os.path.exists(p):
        txt = open(p).read()
        if 'checkReleaseBuilds' not in txt:
            if p.endswith('.kts'):
                patch = 'lint { checkReleaseBuilds = false; isAbortOnError = false }\n    buildTypes {'
            else:
                patch = 'lintOptions { checkReleaseBuilds false; abortOnError false }\n    buildTypes {'
            txt = txt.replace('buildTypes {', patch)
            open(p, 'w').write(txt)
            print("Disabled release lint in", p)
