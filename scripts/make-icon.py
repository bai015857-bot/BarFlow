"""Generate BarFlow's original icon; no third-party assets."""
from pathlib import Path
from PIL import Image, ImageDraw
import subprocess

root = Path(__file__).resolve().parents[1]
iconset = root / ".build/BarFlow.iconset"
iconset.mkdir(parents=True, exist_ok=True)
scale = 4
im = Image.new("RGBA", (1024*scale, 1024*scale))
d = ImageDraw.Draw(im)
def box(xy, **kw):
    d.rounded_rectangle(tuple(int(x*scale) for x in xy), radius=80*scale, **kw)
box((50,50,974,974), fill=(24,40,56,255))
box((230,240,794,365), fill=(73,222,172,255))
box((230,445,560,570), fill=(238,245,249,255))
box((230,650,665,775), fill=(238,245,249,255))
d.line([(760*scale,440*scale),(760*scale,760*scale)],fill=(73,222,172,255),width=42*scale)
d.line([(705*scale,705*scale),(760*scale,760*scale),(815*scale,705*scale)],fill=(73,222,172,255),width=42*scale,joint="curve")
for size in [16,32,128,256,512]:
    for factor in [1,2]:
        filename=f"icon_{size}x{size}"+("@2x" if factor==2 else "")+".png"
        im.resize((size*factor,size*factor),Image.Resampling.LANCZOS).save(iconset/filename)
subprocess.run(["iconutil","-c","icns",str(iconset),"-o",str(root/"Resources/AppIcon.icns")],check=True)
im.resize((512,512),Image.Resampling.LANCZOS).save(root/"Resources/AppIcon.png")
print(root/"Resources/AppIcon.icns")
