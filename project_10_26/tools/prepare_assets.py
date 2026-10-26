"""Build 24 standard BMPs (4 station + 20 promo), caption ROMs and a
deterministic FAT32 disk-image FILE. Never opens a physical disk.
The .img must later be written to the dedicated TF card.
"""
from pathlib import Path
from PIL import Image,ImageOps,ImageDraw,ImageFont
import json,struct,zlib,hashlib
root=Path(__file__).resolve().parent.parent
assets=root/'01_Assets';hdl=root/'03_Project/WestLake_AV/src/user_source/hdl_source/westlake'
hdl.mkdir(parents=True,exist_ok=True)

# ---- station metadata ----
names=['少年宫（断桥）','涌金门','雷峰塔','岳庙（跨虹桥）']
descriptions=['烟雨断桥连白堤，一湖山色入画来。','金牛卧波，柳影拂岸，湖光尽收眼底。','雷峰塔影映湖山，登临远眺西湖风光。','岳王庙前寻旧迹，读一段西湖人文。']
ids=['01_duanqiao','02_yongjinmen','03_leifeng','04_yuemiao']
NUM_STATIONS=4
PROMOS_PER_INTERVAL=5
TOTAL=NUM_STATIONS+NUM_STATIONS*PROMOS_PER_INTERVAL  # 24

font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
title_font=ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc',24)
ascii_font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',13)

words=[];caption_records=[];promo_records=[];bmps=[];fnames=[]
previews=assets/'Preview';previews.mkdir(exist_ok=True)

def pad_bmp(src,out_name):
    original=ImageOps.exif_transpose(Image.open(src)).convert('RGB')
    im=ImageOps.pad(original,(640,480),method=Image.Resampling.LANCZOS,color=(14,32,40))
    p=assets/'TF_BMP'/out_name;im.save(p)
    b=p.read_bytes();assert len(b)==921654
    assert struct.unpack_from('<iiHHI',b,18)==(640,480,1,24,0)
    return p,b,im

def fname83(s):
    return (s[:8].ljust(8,' ')+'BMP').encode('ascii')

# ---- stations (with captions + previews) ----
for i,stem in enumerate(ids):
    p,b,im=pad_bmp(assets/'Original'/f'{stem}.jpg',f'{i+1:02d}_{stem[3:]}.bmp')
    bmps.append((p,b));fnames.append(fname83(f'S{i:03d}'))
    mask=Image.new('1',(640,96),0);d=ImageDraw.Draw(mask)
    d.text((16,0),'随行视听  西湖环湖游',font=title_font,fill=1)
    line=f'本站：{names[i]}   下一站：{names[(i+1)%4]}'
    assert d.textbbox((0,0),line,font=font)[2]<610
    d.text((16,35),line,font=font,fill=1)
    d.text((16,64),descriptions[i],font=font,fill=1)
    mask.save(previews/f'{stem}_caption_mask.png')
    for y in range(96):
        for x in range(0,640,32):
            value=0
            for bit in range(32):value=(value<<1)|int(bool(mask.getpixel((x+bit,y))))
            words.append(value)
    demo=im.copy()
    for y in range(480):
        if y<64 or y>=416:
            for x in range(640):
                rgb=demo.getpixel((x,y));demo.putpixel((x,y),tuple(c//4 for c in rgb))
    fullmask=Image.new('1',(640,480));fullmask.paste(mask.crop((0,0,640,32)),(0,0));fullmask.paste(mask.crop((0,32,640,96)),(0,416))
    demo.paste((255,255,255),(0,0,640,480),fullmask)
    dd=ImageDraw.Draw(demo);dd.text((16,40),f'STOP TEST P=03s U=00:12 S={i+1}/4',font=ascii_font,fill=(80,224,224))
    dd.line((80,407,560,407),fill=(230,230,230),width=2)
    for j in range(4):dd.rectangle((76+160*j,400,84+160*j,414),fill=(255,204,48) if i==j else (190,190,190))
    demo.save(previews/f'{stem}_预期效果.png')
    caption_records.append({'id':i,'station':names[i],'next':names[(i+1)%4],'subtitle':descriptions[i],'bmp':str(p.relative_to(root)),'sha256':hashlib.sha256(b).hexdigest()})

# ---- promos (no captions) ----
for iv in range(NUM_STATIONS):
    for j in range(PROMOS_PER_INTERVAL):
        stem=f'promo_{iv}_{j}'
        p,b,_=pad_bmp(assets/'Original'/f'{stem}.jpg',f'{stem}.bmp')
        flat=iv*PROMOS_PER_INTERVAL+j
        bmps.append((p,b));fnames.append(fname83(f'P{flat:03d}'))
        promo_records.append({'interval':iv,'seq':j,'bmp':str(p.relative_to(root)),'sha256':hashlib.sha256(b).hexdigest()})

words.extend([0]*(8192-len(words)))
(hdl/'captions.hex').write_text(''.join(f'{v:08x}\n' for v in words),encoding='ascii')
fontbytes=[]
for c in range(128):
    glyph=Image.new('1',(8,16));dr=ImageDraw.Draw(glyph)
    if c>=32:dr.text((0,-1),chr(c),font=ascii_font,fill=1)
    for y in range(16):
        v=0
        for x in range(8):v=(v<<1)|int(bool(glyph.getpixel((x,y))))
        fontbytes.append(v)
(hdl/'ascii_font.hex').write_text(''.join(f'{v:02x}\n' for v in fontbytes),encoding='ascii')

# ---- FAT32 volume: 128 MiB disk, partition starts at LBA 2048, 512-byte clusters ----
total=262144;start=2048;reserved=32;volume=total-start;fat_sectors=1
while True:
    clusters=volume-reserved-2*fat_sectors
    required=((clusters+2)*4+511)//512
    if required<=fat_sectors:break
    fat_sectors=required
data_start=start+reserved+2*fat_sectors
fat=bytearray(fat_sectors*512)
root_sectors=(TOTAL*32+511)//512  # 24*32=768 -> 2 sectors for the root directory
for idx,value in [(0,0x0ffffff8),(1,0xffffffff)]:struct.pack_into('<I',fat,idx*4,value)
for c in range(2,2+root_sectors):
    nxt=c+1 if c<2+root_sectors-1 else 0x0fffffff
    struct.pack_into('<I',fat,c*4,nxt)
rootdir=bytearray(root_sectors*512);nextcluster=2+root_sectors

catalog=bytearray(512);catalog[:8]=b'WLAV0002';catalog[8]=TOTAL;catalog[9]=24
struct.pack_into('<HH',catalog,10,640,480);catalog[14]=NUM_STATIONS;catalog[15]=PROMOS_PER_INTERVAL
allocations=[]
for i,(p,b) in enumerate(bmps):
    count=(len(b)+511)//512;first=nextcluster;lba=data_start+first-2
    for cluster in range(first,first+count):
        struct.pack_into('<I',fat,cluster*4,cluster+1 if cluster<first+count-1 else 0x0fffffff)
    entry=bytearray(32);entry[:11]=fnames[i];entry[11]=0x20
    struct.pack_into('<H',entry,20,first>>16);struct.pack_into('<H',entry,26,first&65535);struct.pack_into('<I',entry,28,len(b))
    rootdir[i*32:(i+1)*32]=entry
    struct.pack_into('<IIII',catalog,16+i*16,lba,len(b),i,zlib.crc32(b)&0xffffffff)
    allocations.append((lba,b))
    if i<NUM_STATIONS:caption_records[i]['lba']=lba
    else:promo_records[i-NUM_STATIONS]['lba']=lba
    nextcluster+=count

mbr=bytearray(512);mbr[446:462]=struct.pack('<B3sB3sII',0,b'\xfe\xff\xff',0x0c,b'\xfe\xff\xff',start,volume);mbr[510:512]=b'\x55\xaa'
boot=bytearray(512);boot[:3]=b'\xeb\x58\x90';boot[3:11]=b'WLAV2026'
struct.pack_into('<HBHBHHBHHHII',boot,11,512,1,reserved,2,0,0,0xf8,0,63,255,start,volume)
struct.pack_into('<IHHIHH',boot,36,fat_sectors,0,0,2,1,6);boot[64]=0x80;boot[66]=0x29
struct.pack_into('<I',boot,67,0x20261024);boot[71:82]=b'WESTLAKE_AV';boot[82:90]=b'FAT32   ';boot[510:512]=b'\x55\xaa'
fsinfo=bytearray(512);struct.pack_into('<I',fsinfo,0,0x41615252);struct.pack_into('<I',fsinfo,484,0x61417272)
struct.pack_into('<II',fsinfo,488,clusters-(nextcluster-2),nextcluster);struct.pack_into('<I',fsinfo,508,0xaa550000)

img=assets/'WestLake_TF_128MiB.img'
with img.open('wb') as f:
    f.truncate(total*512)
    def put(lba,b):f.seek(lba*512);f.write(b)
    put(0,mbr);put(start,boot);put(start+1,fsinfo);put(start+6,boot);put(start+7,fsinfo);put(start+8,catalog)
    put(start+reserved,fat);put(start+reserved+fat_sectors,fat)
    for s in range(root_sectors):put(data_start+s,rootdir[s*512:(s+1)*512])
    for lba,b in allocations:put(lba,b)

manifest={'catalog_lba':2056,'data_start':data_start,'disk_sectors':total,
          'num_stations':NUM_STATIONS,'promos_per_interval':PROMOS_PER_INTERVAL,'total':TOTAL,
          'stations':caption_records,'promos':promo_records}
(assets/'station_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')

sources=json.loads((assets/'photo_sources.json').read_text('utf-8'))
credits=['# 西湖四站图片来源与字幕','', '照片用于展示站点周边地标，不代表实时停靠位置。图片为历史实景，线路顺序为本项目演示顺序。',
         '', '区间宣传图来自 01_Assets/Original/promo_*.jpg，仅作轮播展示，不叠加字幕。','']
for r,c in zip(sources,caption_records):
    credits += [f'## {c["station"]}',f'字幕：{c["subtitle"]}',f'作者：{r["author"]}',f'原图页面：{r["source_page"]}',f'许可：{r["license"]} {r["license_url"]}','处理：缩放并补边到 640×480；标准 BMP 不包含字幕，字幕由 FPGA ROM 实时叠加。衍生图片按原图相同许可提供。','']
(assets/'图片来源与字幕.md').write_text('\n'.join(credits),encoding='utf-8')

sheet=Image.new('RGB',(1280,960))
for i,stem in enumerate(ids):sheet.paste(Image.open(previews/f'{stem}_预期效果.png'),((i%2)*640,(i//2)*480))
sheet.save(previews/'四站预期效果_非实机截图.png')
print('Created',len(bmps),'BMPs, ROMs, previews and disk image:',img)
print('station LBAs:',[c['lba'] for c in caption_records])
print('promo LBAs:',[c['lba'] for c in promo_records])
