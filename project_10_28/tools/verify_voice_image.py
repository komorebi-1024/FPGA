"""Read-only, independent check of the four narration files/cues and old media."""
from pathlib import Path
import hashlib,json,struct,wave,zlib
ROOT=Path(__file__).resolve().parent.parent
ASSETS=ROOT/'01_Assets'
u16=lambda b,o:struct.unpack_from('<H',b,o)[0]
u32=lambda b,o:struct.unpack_from('<I',b,o)[0]

def main():
    path=ASSETS/'WestLake_TF_Voice_128MiB.img';image=path.read_bytes()
    original=(ASSETS/'WestLake_TF_Audio_128MiB.img').read_bytes()
    assert len(image)==len(original)==128*1024**2
    part=u32(image,454);boot=image[part*512:(part+1)*512]
    assert part==2048 and image[510:512]==b'\x55\xaa' and u16(boot,11)==512 and boot[13]==1 and boot[16]==2
    reserved=u16(boot,14);fat_size=u32(boot,36);fat_lba=part+reserved
    fat=image[fat_lba*512:(fat_lba+fat_size)*512]
    assert fat==image[(fat_lba+fat_size)*512:(fat_lba+fat_size*2)*512]
    data_lba=fat_lba+fat_size*2
    def chain(c):
        seen=set();ids=[];chunks=[]
        while c<0xffffff8:
            assert 2<=c<len(fat)//4 and c not in seen
            seen.add(c);ids.append(c);offset=(data_lba+c-2)*512
            chunks.append(image[offset:offset+512]);c=u32(fat,c*4)&0xfffffff
        return b''.join(chunks),ids
    directory,_=chain(u32(boot,44));entries={}
    for offset in range(0,len(directory),32):
        entry=directory[offset:offset+32]
        if entry[0]==0:break
        if entry[0]!=0xe5 and entry[11]!=0x0f:entries[entry[:11].decode('ascii')]=entry
    cat=image[2058*512:2059*512]
    assert cat[:12]==b'WLVOC001'+bytes((4,2,16,3)) and u32(cat,12)==48000
    metadata=json.loads((ASSETS/'Voice/narration.json').read_text('utf-8'));results=[]
    for index,s in enumerate(metadata['stations']):
        record=cat[16+index*32:48+index*32]
        lba,frames,cue1,cue2,crc=struct.unpack_from('<IIIII',record)
        assert s['id']==index and 0<cue1<cue2<frames
        assert [cue1,cue2,frames]==[seg['end_frame'] for seg in s['segments']]
        assert list(record[20:23])==[len(seg['text']) for seg in s['segments']] and not any(record[23:])
        entry=entries[f'VOICE{index+1:02d} PCM'];first=(u16(entry,20)<<16)|u16(entry,26)
        assert u32(entry,28)==frames*4 and lba==data_lba+first-2
        payload,ids=chain(first);size=frames*4
        assert ids==list(range(first,first+(size+511)//512)) and not any(payload[size:])
        assert zlib.crc32(payload[:size])&0xffffffff==crc
        with wave.open(str(ASSETS/'Voice'/s['wav']),'rb') as wav:
            assert (wav.getnchannels(),wav.getsampwidth(),wav.getframerate(),wav.getcomptype())==(2,2,48000,'NONE')
            assert wav.getnframes()==frames and wav.readframes(frames)==payload[:size]
        results.append({'station':index+1,'frames':frames,'seconds':round(frames/48000,3),
                        'cue1':cue1,'cue2':cue2,'lba':lba,'crc32':f'{crc:08x}'})
    assert image[2056*512:2058*512]==original[2056*512:2058*512]
    # All 24 picture and every music payload must remain byte-identical.
    for i in range(24):
        lba,size=struct.unpack_from('<II',image,2056*512+16+i*16)
        assert image[lba*512:lba*512+size]==original[lba*512:lba*512+size]
    music_count=image[2057*512+8]
    for i in range(music_count):
        lba,frames=struct.unpack_from('<II',image,2057*512+16+i*16)
        assert image[lba*512:lba*512+frames*4]==original[lba*512:lba*512+frames*4]
    clusters=u32(boot,32)-reserved-2*fat_size
    free=sum(u32(fat,c*4)&0xfffffff==0 for c in range(2,clusters+2))
    for info_lba in [part+u16(boot,48),part+u16(boot,50)+u16(boot,48)]:
        assert u32(image,info_lba*512+488)==free
    result={'result':'PASS','stations':results,'preserved_pictures':24,'preserved_music':music_count,
            'image_sha256':hashlib.sha256(image).hexdigest()}
    (ROOT/'04_Sim/voice_asset_verification.json').write_text(json.dumps(result,indent=2),'utf-8')
    print(json.dumps(result,indent=2))

if __name__=='__main__':main()
