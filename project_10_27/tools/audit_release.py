from pathlib import Path
import json,re,hashlib,xml.etree.ElementTree as ET
root=Path(__file__).resolve().parent.parent
build=root/'05_Build/westlake';project=root/'03_Project/WestLake_AV/src'
text=(root/'05_Build/westlake_console.log').read_text('utf-8',errors='replace')
assert 'BUILD_FLOW_COMPLETE' in text and 'HDL-5105' not in text
timing=(build/'timing.rpt').read_text('utf-8')
setup=float(re.search(r'SWNS:\s*([-\d.]+)ns',timing)[1]);hold=float(re.search(r'HWNS:\s*([-\d.]+)ns',timing)[1])
assert setup>=0 and hold>=0
bid=ET.parse(project/'td_project/HDMI1.4b_Transmitter_v1.0_inst.bid')
roms=[e for e in bid.findall('.//AL_PHY_BRAM/*') if (e.findtext('name') or '').startswith('overlay/')]
assert len(roms)>0 and all(e.findtext('is_initialize')=='y' for e in roms)
tests=json.loads((root/'04_Sim/simulation_results.json').read_text())
assert set(r['name'] for r in tests)>={'media','audio','osd','control','framebuffer','key','status'} and all(r['pass'] for r in tests)
assert json.loads((root/'04_Sim/media_verification.json').read_text('utf-8'))['result']=='PASS'
hashes=json.loads((build/'source_hashes.json').read_text())
for rel,digest in hashes.items():assert hashlib.sha256((project/rel).read_bytes()).hexdigest()==digest,rel
result={'software_release':'PASS','hardware_validation':'PENDING','setup_wns_ns':setup,'hold_wns_ns':hold,'sta_coverage_percent':float(re.search(r'STA coverage\s*:\s*([\d.]+)',timing)[1]),'initialized_overlay_bram_blocks':len(roms),'simulations':tests,'bit_sha256':hashlib.sha256((build/'westlake.bit').read_bytes()).hexdigest(),'remaining_warnings':['vendor SDRAM placement relocation','SDRAM clock local routing','vendor IP undriven or width warnings','external IO delays not fully constrained']}
(root/'06_Delivery/release_audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),'utf-8')
print(json.dumps(result,indent=2))
