param([ValidateSet('Sim','Build','Assets','Audio','Voice','Verify')][string]$Action='Sim')
$ErrorActionPreference='Stop'
$env:PYTHONIOENCODING='utf-8'
$projectRoot=Split-Path -Parent $PSScriptRoot
$pythonCandidates=@(
    (Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\python.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe')
)
$projectPython=$pythonCandidates | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
if(-not $projectPython){$found=Get-Command python -ErrorAction SilentlyContinue;if($found){$projectPython=$found.Source}}
if(-not $projectPython){throw 'Python 3 is required. Install Python and Pillow, then retry.'}
Set-Location -LiteralPath $projectRoot
switch($Action){
    'Sim' {
        & $projectPython (Join-Path $PSScriptRoot 'verify_media.py')
        if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
        & $projectPython (Join-Path $PSScriptRoot 'run_sim.py')
    }
    'Build' {& $projectPython (Join-Path $PSScriptRoot 'run_td.py') westlake_image}
    'Assets' {
        & $projectPython (Join-Path $PSScriptRoot 'prepare_assets.py')
        if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
        & $projectPython (Join-Path $PSScriptRoot 'pack_audio.py')
        if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
        & $projectPython (Join-Path $PSScriptRoot 'verify_audio_image.py')
    }
    'Verify' {& $projectPython (Join-Path $PSScriptRoot 'verify_media.py')}
    'Audio' {
        & $projectPython (Join-Path $PSScriptRoot 'pack_audio.py')
        if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
        & $projectPython (Join-Path $PSScriptRoot 'verify_audio_image.py')
    }
    'Voice' {
        & $projectPython (Join-Path $PSScriptRoot 'prepare_voice_captions.py')
        if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
        & $projectPython (Join-Path $PSScriptRoot 'pack_voice.py')
        if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
        & $projectPython (Join-Path $PSScriptRoot 'verify_voice_image.py')
    }
}
if($LASTEXITCODE -ne 0){throw "Step failed, exit code $LASTEXITCODE. Read the log before using outputs."}
Write-Host 'Finished. Hardware validation is still required.'
