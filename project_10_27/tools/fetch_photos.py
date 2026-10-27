"""Restore missing selected photos using the current source manifest.
Existing photos are preserved. Source metadata is never replaced with old choices.
"""
from pathlib import Path
import concurrent.futures, hashlib, json, urllib.request
root=Path(__file__).resolve().parent.parent
assets=root/'01_Assets'
choices=json.loads((assets/'photo_sources.json').read_text('utf-8'))
def fetch(row):
    stem=row['id']; p=root/row['file']
    if not p.exists():
        req=urllib.request.Request(row['download_url'],headers={'User-Agent':'WestLakeFPGAStudentProject/1.1'})
        with urllib.request.urlopen(req,timeout=60) as resp:data=resp.read()
        if row.get('sha256') and hashlib.sha256(data).hexdigest()!=row['sha256']:
            raise ValueError('Downloaded original has changed: '+stem)
        p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
    print(stem,p.stat().st_size,flush=True)
    return row
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool: rows=list(pool.map(fetch,choices))
from PIL import Image,ImageOps,ImageDraw
sheet=Image.new('RGB',(1000,780),'white');draw=ImageDraw.Draw(sheet)
for i,row in enumerate(rows):
    p=root/row['file'];im=Image.open(p);im=ImageOps.exif_transpose(im).convert('RGB')
    preview=ImageOps.contain(im,(490,350));x=(i%2)*500;y=(i//2)*390
    sheet.paste(preview,(x+(490-preview.width)//2,y));draw.text((x+8,y+356),row['id'],fill='black')
sheet.save(assets/'四站原图预览.jpg')
