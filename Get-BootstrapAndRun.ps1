#Requires -PSEdition Desktop
# Bootstrap should be run on windows powershell which is the desktop version.

Write-Output 'Creating system-bootstrap folder.'
$bootstrapFolder = "$env:temp\system-bootstrap"
New-Item -Path $bootstrapFolder -ItemType Directory -Force | Out-Null
if(-not (Test-Path $bootstrapFolder)) {
    Write-Output "Failed to create system-bootstrap folder '$bootstrapFolder'."
    return
}

Write-Output 'Downloading system-bootstrap files.'
$files = @(
    'Start-SystemBootstrap.ps1',
    'basesystem.dsc.yaml',
    'Start-SystemSetup.ps1'
)
foreach ($file in $files) {
    $scriptDownload = Invoke-WebRequest "https://raw.githubusercontent.com/sytone/system-bootstrap/main/$file"
    Write-Output "Downloading $file to $bootstrapFolder\$file"
    $scriptDownload.Content | Out-File -FilePath "$bootstrapFolder\$file" -Force
}
Write-Output 'Running Start-SystemBootstrap.ps1'
& "$bootstrapFolder\Start-SystemBootstrap.ps1"
