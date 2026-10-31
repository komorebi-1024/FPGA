"""Pack shared title, station labels and three speech-linked subtitle pages.

8160 words fit the existing 8192x32 caption ROM; no new bitmap RAM is needed.
This creates a separate voice_captions.hex and leaves the old caption ROM alone.
"""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json
ROOT=Path(__file__).resolve().parent.parent
VOICE=ROOT/'01_Assets/Voice'
HDL=ROOT/'03_Project/WestLake_AV/src/user_source/hdl_source/westlake'

def main():
    data=json.loads((VOICE/'narration.json').read_text('utf-8'))
    stations=data['stations'];assert len(stations)==4
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
    bold=ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc',20)
    words=[];strips=[]
    def append_strip(text,selected_font=font):
        strip=Image.new('1',(640,24));draw=ImageDraw.Draw(strip)
        assert draw.textbbox((16,-2),text,font=selected_font)[2]<=636,text
        draw.text((16,-2),text,font=selected_font,fill=1)
        strips.append(strip)
        for y in range(24):
            for x in range(0,640,32):
                value=0
                for bit in range(32):value=(value<<1)|int(bool(strip.getpixel((x+bit,y))))
                words.append(value)
    append_strip('随行视听  西湖环湖游',bold)
    for i,s in enumerate(stations):
        assert s['id']==i and len(s['segments'])==3
        append_strip(f'本站：{s["name"]}   下一站：{stations[(i+1)%4]["name"]}')
    for s in stations:
        for segment in s['segments']:append_strip(segment['text'])
    assert len(words)==8160
    words.extend([0]*32)
    (HDL/'voice_captions.hex').write_text(''.join(f'{v:08x}\n' for v in words),'ascii')
    preview=VOICE/'Preview';preview.mkdir(exist_ok=True)
    manifest=json.loads((ROOT/'01_Assets/station_manifest.json').read_text('utf-8'))
    for i,s in enumerate(stations):
        for phase,seg in enumerate(s['segments']):
            im=Image.open(ROOT/manifest['stations'][i]['bmp']).convert('RGB')
            for top,height in [(0,64),(416,64)]:
                region=im.crop((0,top,640,top+height));region=region.point(lambda x:x//4);im.paste(region,(0,top))
            im.paste((255,255,255),(0,0,640,24),strips[0])
            im.paste((255,255,255),(0,416,640,440),strips[1+i])
            im.paste((255,255,255),(0,448,640,472),strips[5+i*3+phase])
            im.save(preview/f'station{i+1:02d}_phrase{phase+1:02d}_software_preview.png')
    print('Prepared 8160 caption words in existing 8192-word capacity; voice previews generated.')

if __name__=='__main__':main()
