"""Independent read-only FAT32/catalog verifier, also generates simulation vectors."""
from pathlib import Path
import struct,json,zlib,hashlib
from PIL import Image
root=Path(__file__).resolve().parent.parent
assets=root/'01_Assets'; sim=root/'04_Sim';sim.mkdir(exist_ok=True)
img=(assets/'WestLake_TF_128MiB.img').read_bytes()
u16=lambda b,o:struct.unpack_from('<H',b,o)[0]
u32=lambda b,o:struct.unpack_from('<I',b,o)[0]
assert len(img)==128*1024**2 and img[510:512]==b'\x55\xaa'
part=u32(img,454); size=u32(img,458);boot=img[part*512:(part+1)*512]
assert part+size==len(img)//512
assert u16(boot,11)==512 and boot[13]==1 and boot[16]==2 and boot[510:512]==b'\x55\xaa'
reserved=u16(boot,14);fatsize=u32(boot,36);rootcluster=u32(boot,44)
fatstart=(part+reserved)*512;fat=img[fatstart:fatstart+fatsize*512]
assert fat==img[fatstart+fatsize*512:fatstart+2*fatsize*512]
data_lba=part+reserved+2*fatsize
clusterdata=lambda c:img[(data_lba+c-2)*512:(data_lba+c-1)*512]
def chain(c):
 seen=set();data=bytearray();clusters=[]
 while c<0xffffff8:
  assert c>=2 and c not in seen;seen.add(c);clusters.append(c)
  data.extend(clusterdata(c));c=u32(fat,c*4)&0xfffffff
 return bytes(data),clusters
directory,_=chain(rootcluster);cat=img[(part+8)*512:(part+9)*512]
assert cat[:10]==b'WLAV0002\x18\x18' and struct.unpack_from('<HH',cat,10)==(640,480)
assert cat[14:16]==bytes((4,5))
manifest=json.loads((assets/'station_manifest.json').read_text('utf-8'));results=[]
cap=[int(x,16) for x in (root/'03_Project/WestLake_AV/src/user_source/hdl_source/westlake/captions.hex').read_text().split()]
font=[int(x,16) for x in (root/'03_Project/WestLake_AV/src/user_source/hdl_source/westlake/ascii_font.hex').read_text().split()]
records=manifest['stations']+manifest['promos']
for n in range(24):
 ent=directory[n*32:n*32+32];first=(u16(ent,20)<<16)|u16(ent,26);length=u32(ent,28)
 data,clusters=chain(first);data=data[:length]
 lba,clen,cid,crc=struct.unpack_from('<IIII',cat,16+n*16)
 assert cid==n and clen==length and lba==data_lba+first-2
 assert clusters==list(range(first,first+len(clusters)))
 assert zlib.crc32(data)&0xffffffff==crc
 expected=(root/records[n]['bmp']).read_bytes();assert data==expected
 assert u32(data,2)==len(data)==921654 and u32(data,10)==54
 assert struct.unpack_from('<iiHHI',data,18)==(640,480,1,24,0)
 results.append({'image':n,'directory_name':ent[:11].decode(),'LBA':lba,'bytes':length,'clusters':len(clusters),'sha256':hashlib.sha256(data).hexdigest()})
 if n>=4:continue
 im=Image.open(root/records[n]['bmp']).convert('RGB')
 # Independent, pixel-by-pixel reference for actual RTL overlay output.
 ref=[];pixels=list(im.getdata());status=f'STOP TEST P=03s U=00:00 S={n+1}/4'
 for y in range(480):
  for x in range(640):
   rgb=pixels[y*640+x];value=(rgb[0]<<16)|(rgb[1]<<8)|rgb[2]
   caption=False
   if y<32 or y>=416:
    cy=y if y<32 else y-384
    caption=bool(cap[n*1920+cy*20+x//32]&(1<<(31-x%32)))
   statuspixel=False
   if 40<=y<56 and 16<=x<256:
    col=(x-16)//8;c=ord(status[col]) if col<len(status) else 32
    statuspixel=bool(font[c*16+y-40]&(1<<(7-x%8)))
   stop=400<=y<=414 and any(76+160*j<=x<=84+160*j for j in range(4))
   chosen=stop and 76+160*n<=x<=84+160*n
   rail=407<=y<=408 and 80<=x<=560
   if statuspixel:value=0x50e0e0
   elif caption:value=0xffffff
   elif chosen:value=0xffcc30
   elif stop or rail:value=0xbebebe
   elif y<64 or y>=416:value=((rgb[0]//4)<<16)|((rgb[1]//4)<<8)|(rgb[2]//4)
   ref.append(value)
 (sim/f'input_{n}.hex').write_text(''.join(f'{r:02x}{g:02x}{b:02x}\n' for r,g,b in pixels),'ascii')
 (sim/f'expected_{n}.hex').write_text(''.join(f'{v:06x}\n' for v in ref),'ascii')
report={'result':'PASS','checks':['MBR bounds','FAT32 BPB','both FAT copies equal','all cluster chains contiguous and acyclic','all BMP files identical to source','catalog ID and CRC32','BMP geometry/depth/compression'], 'images':results}
(sim/'media_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),'utf-8')
print('PASS: 24 FAT32 files, catalog, CRC32 and BMP headers verified independently.')
