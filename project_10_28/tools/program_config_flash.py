"""Back up and program the HX4S20C configuration Flash, with readback verify.

Default mode only probes the chip. --program writes a fresh, timing-passing
audio build to the configuration W25Q16 (EF4015), not the user-data W25Q64.
Never opens or writes a physical SD disk.
"""
from pathlib import Path
import argparse,hashlib,json,re,subprocess
from download_audio import ROOT,BUILD,validate_build,tcl_path

EXE=Path('D:/Program Files/TD_6_2_1/bin/bw_commands_prompt.exe')
OUT=ROOT/'05_Build'

def run(commands,label,timeout=180):
    script=OUT/f'{label}.tcl'
    script.write_text('set failed [catch {\n'+'\n'.join(commands)+
                      '\n} msg]\nif {$failed} {puts "WL_FLASH_FAILED: $msg"; exit 1}\n'
                      'puts WL_FLASH_DONE\nexit 0\n','utf-8')
    log=OUT/f'{label}.log'
    with log.open('wb') as stream:
        result=subprocess.run([str(EXE),script.as_posix()],cwd=OUT,
                              stdout=stream,stderr=subprocess.STDOUT,timeout=timeout,
                              creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    text=log.read_text('utf-8',errors='replace').replace('\r','')
    print(text,flush=True)
    if result.returncode or 'WL_FLASH_DONE' not in text or re.search(
        r'\b(?:ERROR|FATAL|failed|failure|fail)\b',text,re.I):
        raise ValueError('Flash operation did not pass: '+str(log))
    return text

def confirm_flash(text):
    expected={'Manufacturer ID':'ef','Interface type':'40','Density and Feature':'15'}
    for field,value in expected.items():
        match=re.search(re.escape(field)+r'\s*:\s*([0-9a-f]+)',text,re.I)
        if not match or match[1].lower()!=value:
            raise ValueError('Refusing Flash write: expected Winbond W25Q16 EF4015')
    if 'EG4S20BG256' not in text:raise ValueError('Wrong FPGA device')

def main():
    global BUILD
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--program',action='store_true')
    parser.add_argument('--build',choices=['westlake_audio','westlake_voice','westlake_image'],default='westlake_audio')
    args=parser.parse_args()
    BUILD=ROOT/'05_Build'/args.build
    if args.program:bit=validate_build(BUILD)
    probe=run(['list_cable','set ids [read_device_id -cable 0]',
               'puts "ONLINE_FPGA=$ids"','get_flash_manufacturer -cable 0 -spd 4'],
              'config_flash_identity',30)
    confirm_flash(probe)
    if not args.program:return
    backup=OUT/'config_flash_before_rubric.bin'
    manifest=OUT/'config_flash_before_rubric.json'
    if not backup.exists():
        run([f'read_flash -start_addr 0 -length 2097152 -output {tcl_path(backup)} -cable 0'],
            'config_flash_backup')
    if backup.stat().st_size!=2097152:raise ValueError('Incomplete 2 MiB Flash backup')
    digest=hashlib.sha256(backup.read_bytes()).hexdigest()
    if manifest.exists():
        if json.loads(manifest.read_text('utf-8'))['sha256']!=digest:
            raise ValueError('Flash backup hash mismatch; original backup must be retained')
    else:
        # Also accepts the prior read-only backup made before this script existed.
        backup_log=(OUT/'config_flash_backup.log').read_text('utf-8',errors='replace')
        if 'FLASH_BACKUP_DONE' not in backup_log and 'WL_FLASH_DONE' not in backup_log:
            raise ValueError('Missing successful original backup log')
        manifest.write_text(json.dumps({'device':'EF4015','bytes':2097152,
             'sha256':digest,'created':'2026-10-28','source':'configuration Flash before rubric optimization'},indent=2),'utf-8')
    bit=validate_build(BUILD)  # Do not program a build changed during the backup.
    run([f'download -bit {tcl_path(bit)} -mode program_spi -v -spd 4 -cable 0'],
        'config_flash_program',300)
    # A separate comparison confirms the contents after the programming operation.
    run([f'download -bit {tcl_path(bit)} -mode verify_spi -spd 4 -cable 0'],
        'config_flash_verify',180)
    report={'result':'FLASH_PROGRAM_AND_VERIFY_PASS','bitstream':str(bit),
            'bitstream_sha256':hashlib.sha256(bit.read_bytes()).hexdigest(),
            'original_backup':str(backup),'original_backup_sha256':digest,
            'device':'EF4015','cold_start':'PENDING_PHYSICAL_POWER_CYCLE'}
    (BUILD/'flash_status.json').write_text(json.dumps(report,indent=2),'utf-8')
    print('Flash programmed and verified. Power-cycle testing is still required.',flush=True)

if __name__=='__main__':
    try:main()
    except (OSError,ValueError,subprocess.TimeoutExpired) as error:
        raise SystemExit('ERROR: '+str(error))
