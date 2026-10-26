"""Run self-checking RTL simulations. Does not simulate encrypted HDMI or hardware."""
from pathlib import Path
import subprocess,sys,time,json
from PIL import Image
root=Path(__file__).resolve().parent.parent;sim=root/'04_Sim'
h=root/'03_Project/WestLake_AV/src/user_source/hdl_source'
bin=root/'tools/iverilog/bin';report=[]
oldfile=sim/'simulation_results.json'
old={r['name']:r for r in json.loads(oldfile.read_text())} if oldfile.exists() else {}
names=sys.argv[1:] or ['media','audio','osd','control','framebuffer','key','status']
for name in names:
 files=[str(sim/f'tb_{name}.sv')]+[str(p) for p in (h/'westlake').glob('*.v')]
 if name=='framebuffer':files+=[str(h/'SD/frame_fifo_write.v'),str(h/'SD/frame_fifo_read.v')]
 started=time.time();log=[]
 for cmd in [[str(bin/'iverilog.exe'),'-g2012','-Wall','-s',f'tb_{name}','-o',str(sim/f'{name}.vvp')]+files,[str(bin/'vvp.exe'),str(sim/f'{name}.vvp')]]:
  p=subprocess.run(cmd,cwd=sim,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=300)
  log.append(p.stdout)
  if p.returncode:break
 (sim/f'{name}.log').write_text('\n'.join(log),'utf-8')
 result={'name':name,'pass':p.returncode==0,'seconds':round(time.time()-started,2)};report.append(result);old[name]=result
 oldfile.write_text(json.dumps(list(old.values()),indent=2),'utf-8');print(result,flush=True)
 if p.returncode:print(p.stdout);sys.exit(p.returncode)
 if name=='osd':
  for i in range(4):Image.frombytes('RGB',(640,480),(sim/f'osd_rtl_{i}.rgb').read_bytes()).save(sim/f'osd_rtl_{i}.png')
print('PASS: selected simulations complete. Full results: 04_Sim/simulation_results.json')
