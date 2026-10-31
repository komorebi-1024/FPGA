"""Scan the local JTAG cable by default; --program explicitly loads SRAM.

This tool never programs configuration Flash. SRAM programming requires a fresh
audio bitstream whose build passed constrained timing and whose source hashes
still match the current formal project.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / '05_Build/westlake_audio'
PROJECT_SOURCE = ROOT / '03_Project/WestLake_AV/src'
BITSTREAM = BUILD / 'westlake_audio.bit'
SOURCE_EXTENSIONS = {'.v', '.sdc', '.adc', '.hex', '.tcl'}


def validate_build(build=None, project_source=PROJECT_SOURCE):
    build, project_source = Path(BUILD if build is None else build), Path(project_source)
    bit = build / (build.name+'.bit')
    status_file, hash_file = build / 'build_status.txt', build / 'source_hashes.json'
    if not all(path.is_file() for path in (bit, status_file, hash_file)):
        raise ValueError('Audio build is incomplete: bitstream/status/source hashes are required')
    status = status_file.read_text('utf-8').strip()
    if not status.startswith('FLOW_COMPLETE; CONSTRAINED_TIMING_PASS;'):
        raise ValueError(f'Audio build is not ready for download: {status}')
    if bit.stat().st_size == 0 or bit.stat().st_mtime_ns < hash_file.stat().st_mtime_ns:
        raise ValueError('Bitstream predates this build attempt; rebuild before downloading')
    if status_file.stat().st_mtime_ns < bit.stat().st_mtime_ns:
        raise ValueError('Build completion status predates the bitstream')
    saved = json.loads(hash_file.read_text('utf-8'))
    if not isinstance(saved, dict) or not all(isinstance(name, str) for name in saved):
        raise ValueError('Invalid build source hash manifest')
    saved = {name.replace('\\', '/'): digest for name, digest in saved.items()}
    current = {path.relative_to(project_source).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
               for path in (project_source / 'user_source').rglob('*')
               if path.is_file() and path.suffix.lower() in SOURCE_EXTENSIONS}
    if not current or current != saved:
        changed = sorted(name for name in current.keys() | saved.keys() if current.get(name) != saved.get(name))
        raise ValueError('Sources changed since audio build; rebuild before downloading: ' + ', '.join(changed[:5]))
    return bit


def tcl_path(path):
    # Quoted Tcl word, with no variable/command substitution from a path.
    text = Path(path).resolve().as_posix()
    for character in ('\\', '"', '$', '[', ']'):
        text = text.replace(character, '\\' + character)
    return '"' + text + '"'


def script_text(program, cable):
    operations = [
        'list_cable',
        f'set wl_ids [read_device_id -cable {cable}]',
        'puts "WL_DEVICE_IDS=$wl_ids"',
    ]
    if program:
        operations.append(f'download -bit {tcl_path(BITSTREAM)} -mode jtag -spd 6 -cable {cable}')
    label = 'PROGRAM' if program else 'SCAN'
    return ('set wl_failed [catch {\n' + '\n'.join(operations)
            + '\n} wl_message]\n'
            + 'if {$wl_failed} {\n puts "WL_OPERATION_FAILED: $wl_message"\n'
            + ' if {[info exists ::errorInfo]} {puts $::errorInfo}\n exit 1\n}\n'
            + f'puts WL_{label}_DONE\nexit 0\n')


def main():
    global BUILD,BITSTREAM
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--scan', action='store_true', help='Read cable/IDCODE only (default)')
    modes.add_argument('--program', action='store_true', help='Load the validated audio bitstream into SRAM')
    parser.add_argument('--cable', type=int, default=0, help='Local cable index; default 0')
    parser.add_argument('--build', choices=['westlake_audio','westlake_voice','westlake_image'], default='westlake_audio')
    args = parser.parse_args()
    BUILD=ROOT/'05_Build'/args.build
    BITSTREAM=BUILD/(args.build+'.bit')
    if args.cable < 0:
        parser.error('Cable index must be nonnegative')
    executable = Path(os.environ.get('WESTLAKE_BW', 'D:/Program Files/TD_6_2_1/bin/bw_commands_prompt.exe'))
    if not executable.is_file():
        parser.exit(1, 'BitWriter CLI not found. Set WESTLAKE_BW to bw_commands_prompt.exe.\n')
    try:
        if args.program:
            validate_build()
        build_root = ROOT / '05_Build'
        build_root.mkdir(exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=build_root, prefix='audio_jtag_', suffix='.tcl',
                                         mode='w', encoding='utf-8', delete=False) as stream:
            script = Path(stream.name)
            stream.write(script_text(args.program, args.cable))
        try:
            process = subprocess.run([str(executable), script.as_posix()], cwd=build_root,
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                     timeout=180 if args.program else 20,
                                     creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        finally:
            script.unlink(missing_ok=True)
    except (OSError, ValueError, json.JSONDecodeError, subprocess.TimeoutExpired) as error:
        parser.exit(1, f'ERROR: {error}\n')
    output = process.stdout.decode('utf-8', errors='replace').replace('\r', '')
    label={'westlake_audio':'audio','westlake_voice':'voice','westlake_image':'image'}[args.build]
    log = build_root / (f'download_{label}_program.log' if args.program else f'download_{label}_scan.log')
    log.write_text(output, 'utf-8')
    print(output, end='' if output.endswith('\n') else '\n')
    marker = 'WL_PROGRAM_DONE' if args.program else 'WL_SCAN_DONE'
    failure = re.search(r'\b(?:ERROR|FATAL)\b|\b(?:failed|failure|fail)\b|WL_OPERATION_FAILED', output, re.IGNORECASE)
    if process.returncode != 0 or marker not in output or failure:
        parser.exit(1, f'JTAG operation did not pass. Log: {log}\n')
    if args.program:
        print(f'SRAM download completed: {BITSTREAM}\nHDMI picture, sound and spectrum still require observation on the device.')
    else:
        print('IDCODE scan completed. Confirm the connected FPGA is EG4S20BG256 before --program.')
    print(f'Log: {log}')


if __name__ == '__main__':
    main()
