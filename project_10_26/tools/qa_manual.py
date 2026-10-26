from pathlib import Path
from PIL import Image,ImageDraw
import pdfplumber,json
root=Path(__file__).resolve().parent.parent;qa=root/'00_Docs/_qa_manual'
pdf=pdfplumber.open(next(qa.glob('*.pdf')))
pages=[qa/f'page-{n}.png' for n in range(1,len(pdf.pages)+1)]
for i in range(0,len(pages),2):
 a=Image.open(pages[i]);b=Image.open(pages[i+1]) if i+1<len(pages) else Image.new('RGB',a.size,'white')
 sheet=Image.new('RGB',(a.width+b.width+12,max(a.height,b.height)),(170,170,170));sheet.paste(a,(0,0));sheet.paste(b,(a.width+12,0));sheet.save(qa/f'review_{i//2+1:02d}.png')
summary=[]
for n,page in enumerate(pdf.pages,1):
 lines=page.extract_text().splitlines();blocks=page.chars
 off=[(b['text'],b['x0'],b['top']) for b in blocks if b['x0']<20 or b['x1']>page.width-20 or b['top']<12 or b['bottom']>page.height-10]
 summary.append({'page':n,'lines':len(lines),'first':lines[:3],'last':lines[-3:],'out_of_page_blocks':off})
(qa/'layout_check.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),'utf-8')
print(json.dumps(summary,ensure_ascii=False))
