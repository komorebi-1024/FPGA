"""Run the installed TD Tcl frontend without opening a separate window."""
from pathlib import Path
import subprocess,sys,time,os,hashlib,json,re,shutil
root=Path(__file__).resolve().parent.parent
name=sys.argv[1] if len(sys.argv)>1 else 'baseline'
exe=Path(os.environ.get('WESTLAKE_TD',r'D:\Program Files\TD_6_2_1\bin\td_commands_prompt.exe'))
if not exe.is_file():raise SystemExit('TD not found. Set WESTLAKE_TD to the full td_commands_prompt.exe path.')
project_name='00_Baseline' if name=='baseline' else 'WestLake_AV'
project=root/'03_Project'/project_name/'src/td_project'
out=root/'05_Build'/name
out.mkdir(parents=True,exist_ok=True)
source_hashes={str(p.relative_to(project.parent)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (project.parent/'user_source').rglob('*') if p.is_file() and p.suffix.lower() in ('.v','.sdc','.adc','.hex','.tcl')}
(out/'source_hashes.json').write_text(json.dumps(source_hashes,indent=2),'utf-8')
(out/'build_status.txt').write_text('RUNNING; do not use an earlier bitstream\n','utf-8')
# TD's command adapter does not reliably accept nested Tcl command substitutions
# in file arguments. Generate literal, slash-normalized paths instead.
script=root/'tools'/f'build_{name}_generated.tcl'
lines=[f'cd {project.as_posix()}', 'import_device eagle_s20.db -package EG4S20BG256',
'open_project -single_run HDMI1.4b_Transmitter_v1.0.al','elaborate -top top',
'read_adc ../user_source/constraints_source/pin.adc','optimize_rtl',
'read_sdc ../user_source/constraints_source/timing.sdc',
'read_sdc -ip rfifo_32_32_512 ../user_source/hdl_source/IP/afifo_32_16_256.tcl',
'read_sdc -ip wfifo_32_32_512 ../user_source/hdl_source/IP/afifo_16_32_256.tcl',
'optimize_gate',f'report_area -file {out.as_posix()}/gate.area','legalize_phy_inst',
'read_sdc ../user_source/constraints_source/timing.sdc',
'read_sdc -ip rfifo_32_32_512 ../user_source/hdl_source/IP/afifo_32_16_256.tcl',
'read_sdc -ip wfifo_32_32_512 ../user_source/hdl_source/IP/afifo_16_32_256.tcl',
'place','route',f'report_area -io_info -file {out.as_posix()}/final.area',
'update_timing -mode final',f'report_timing_summary -file {out.as_posix()}/timing.rpt',
f'report_clock_summary -file {out.as_posix()}/clocks.rpt',
f'report_timing_exception -file {out.as_posix()}/exceptions.rpt',
f'export_db {out.as_posix()}/routed.db',f'bitgen -bit {out.as_posix()}/{name}.bit','close_project']
script.write_text('set wl_result [catch {\n'+'\n'.join(lines)+'\n} wl_message]\nif {$wl_result} {puts "BUILD_FAILED: $wl_message"; puts $::errorInfo; exit 1}\nputs BUILD_FLOW_COMPLETE\nexit 0\n',encoding='utf-8')
log=root/'05_Build'/f'{name}_console.log'
with log.open('wb') as f:
    p=subprocess.Popen([str(exe),script.as_posix()],cwd=root/'05_Build',stdout=f,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
    print(f'TD started pid={p.pid}; log={log}',flush=True)
    code=p.wait()
print(f'TD frontend exit={code}',flush=True)
logtext=log.read_text('utf-8',errors='replace')
ok=code==0 and 'BUILD_FLOW_COMPLETE' in logtext and (out/f'{name}.bit').exists() and 'HDL-5105' not in logtext
timing=(out/'timing.rpt').read_text('utf-8',errors='replace') if (out/'timing.rpt').exists() else ''
setup=re.search(r'SWNS:\s*([-\d.]+)ns',timing);hold=re.search(r'HWNS:\s*([-\d.]+)ns',timing)
timing_ok=bool(setup and hold and float(setup[1])>=0 and float(hold[1])>=0)
status='FLOW_COMPLETE; CONSTRAINED_TIMING_PASS; hardware pending\n' if ok and timing_ok else ('FLOW_COMPLETE; TIMING_FAIL; not release ready\n' if ok else 'FAILED; see console log\n')
(out/'build_status.txt').write_text(status,encoding='utf-8')
bid=project/'HDMI1.4b_Transmitter_v1.0_inst.bid'
if ok and bid.exists():shutil.copy2(bid,out/'memory_initialization.bid')
print(status.strip(),flush=True)
if not ok or (name!='baseline' and not timing_ok): code=1
sys.exit(code)
