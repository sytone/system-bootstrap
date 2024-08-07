#Requires -PSEdition Desktop
# Bootstrap should be run on windows powershell which is the desktop version.

Write-Output ' __                _                      '
Write-Output '(_    __|_ _ ._ _ |_) _  __|_ __|_.__.._  '
Write-Output '__)\/_> |_(/_| | ||_)(_)(_)|__> |_|(_||_) '
Write-Output '   /                                  |   '
Write-Output ''
Write-Output 'Creating system-bootstrap folder.'

$bootstrapFolder = "$env:temp\system-bootstrap"
New-Item -Path $bootstrapFolder -ItemType Directory -Force | Out-Null

if(-not (Test-Path $bootstrapFolder)) {
    Write-Output "Failed to create system-bootstrap folder '$bootstrapFolder'."
    return
}

Write-Output "Folder created at: '$bootstrapFolder'"

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

Write-Output "Running $bootstrapFolder\Start-SystemBootstrap.ps1"

& "$bootstrapFolder\Start-SystemBootstrap.ps1"
