param([Parameter(Mandatory=$true)][string]$InputDoc,[Parameter(Mandatory=$true)][string]$OutputPdf)
$ErrorActionPreference='Stop'
$wordApp=$null;$document=$null
try {
    $wordApp=New-Object -ComObject Word.Application
    $wordApp.Visible=$false
    $wordApp.DisplayAlerts=0
    $document=$wordApp.Documents.Open($InputDoc,$false,$true)
    $document.Repaginate()
    $document.ExportAsFixedFormat($OutputPdf,17)
    Write-Output "Word exported $OutputPdf"
} finally {
    if($document){$document.Close(0);[void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($document)}
    if($wordApp){$wordApp.Quit();[void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($wordApp)}
}
