New-Item -Path 'C:\Temp\system-bootstrap' -ItemType Directory -Force

$files = @(
    'Start-SystemBootstrap.ps1',
    'basesystem.dsc.yaml',
    'Start-SystemSetup.ps1'
)

foreach ($file in $files) {
    $scriptDownload = Invoke-WebRequest https://raw.githubusercontent.com/sytone/system-bootstrap/main/$file
    $scriptDownload.Content | Out-File -FilePath "C:\Temp\system-bootstrap\$file"
}

& 'C:\Temp\system-bootstrap\Start-SystemBootstrap.ps1'
