Write-Output 'Creating system-bootstrap folder.'
New-Item -Path 'C:\Temp\system-bootstrap' -ItemType Directory -Force

Write-Output 'Downloading system-bootstrap files.'

$files = @(
    'Start-SystemBootstrap.ps1',
    'basesystem.dsc.yaml',
    'Start-SystemSetup.ps1'
)

foreach ($file in $files) {
    $scriptDownload = Invoke-WebRequest "https://raw.githubusercontent.com/sytone/system-bootstrap/main/$file"
    Write-Output "Downloading $file to C:\Temp\system-bootstrap\$file"
    $scriptDownload.Content | Out-File -FilePath "C:\Temp\system-bootstrap\$file" -Force
}

Write-Output 'Running Start-SystemBootstrap.ps1'
& 'C:\Temp\system-bootstrap\Start-SystemBootstrap.ps1'
