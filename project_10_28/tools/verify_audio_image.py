"""Independently verify the generated music image against all source WAV/BMPs."""
from pathlib import Path
import hashlib,json,struct,wave,zlib

ROOT=Path(__file__).resolve().parent.parent
ASSETS=ROOT/'01_Assets'
u16=lambda b,o:struct.unpack_from('<H',b,o)[0]
u32=lambda b,o:struct.unpack_from('<I',b,o)[0]

def main():
    image_path=ASSETS/'WestLake_TF_Audio_128MiB.img'
    image=image_path.read_bytes()
    assert len(image)==128*1024**2 and image[510:512]==b'\x55\xaa'
    part=u32(image,454);boot=image[part*512:(part+1)*512]
    assert part==2048 and u32(image,458)+part==len(image)//512
    reserved=u16(boot,14);fat_size=u32(boot,36)
    assert u16(boot,11)==512 and boot[13]==1 and boot[16]==2
    fat=image[(part+reserved)*512:(part+reserved+fat_size)*512]
    assert fat==image[(part+reserved+fat_size)*512:(part+reserved+2*fat_size)*512]
    data_lba=part+reserved+2*fat_size
    def read_chain(first):
        cluster=first;chunks=[];chain=[];seen=set()
        while cluster<0xffffff8:
            assert 2<=cluster<(len(fat)//4) and cluster not in seen
            chain.append(cluster);seen.add(cluster)
            offset=(data_lba+cluster-2)*512
            chunks.append(image[offset:offset+512])
            cluster=u32(fat,cluster*4)&0xfffffff
        return b''.join(chunks),chain
    directory,_=read_chain(u32(boot,44))
    entries={}
    for offset in range(0,len(directory),32):
        entry=directory[offset:offset+32]
        if entry[0]==0:break
        if entry[0]!=0xe5 and entry[11]!=0x0f:
            entries[entry[:11].decode('ascii')]=entry
    cat=image[2057*512:2058*512]
    assert cat[:12]==b'WLPCM001'+bytes((len(list((ASSETS/'Audio').glob('music??.wav'))),2,16,0))
    assert u32(cat,12)==48000 and cat[8]<=4
    report=[]
    for index in range(cat[8]):
        lba,frames,crc,reserved_word=struct.unpack_from('<IIII',cat,16+16*index)
        assert reserved_word==0 and lba>2057 and frames>0
        entry=entries[f'MUSIC{index+1:02d} PCM']
        first=(u16(entry,20)<<16)|u16(entry,26)
        size=u32(entry,28);payload,chain=read_chain(first)
        assert size==frames*4 and lba==data_lba+first-2
        assert chain==list(range(first,first+(size+511)//512))
        assert zlib.crc32(payload[:size])&0xffffffff==crc and not any(payload[size:])
        with wave.open(str(ASSETS/'Audio'/f'music{index+1:02d}.wav'),'rb') as wav:
            assert (wav.getnchannels(),wav.getsampwidth(),wav.getframerate(),wav.getcomptype())==(2,2,48000,'NONE')
            assert wav.getnframes()==frames and wav.readframes(frames)==payload[:size]
        report.append({'track':index+1,'frames':frames,'seconds':round(frames/48000,3),
                       'lba':lba,'crc32':f'{crc:08x}'})
    # Music allocation must preserve every original picture and its fixed catalog.
    original=(ASSETS/'WestLake_TF_128MiB.img').read_bytes()
    assert image[2056*512:2057*512]==original[2056*512:2057*512]
    for i in range(24):
        lba,size,_,_=struct.unpack_from('<IIII',image,2056*512+16+i*16)
        assert image[lba*512:lba*512+size]==original[lba*512:lba*512+size]
    result={'result':'PASS','tracks':report,'preserved_bmps':24,
            'image_sha256':hashlib.sha256(image).hexdigest()}
    (ROOT/'04_Sim/audio_asset_verification.json').write_text(json.dumps(result,indent=2),'utf-8')
    print(json.dumps(result,indent=2))

if __name__=='__main__':main()
