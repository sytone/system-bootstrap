# This is run in powershell. It sets up all the 
# installers and gets git and pwsh running and then
# the other installers can run.

# This should always be 100% idempotent.
function wi($message) {
    Write-Host $message
}

function ww($message) {
    Write-Warning $message
}

function Write-HeadingBlock($Message) {
    Write-Host "--- [$Message] ---"
}

function Get-ScoopApp($Name) {
    return $scoopConfiguration.apps | Where-Object { $_.Name -eq $Name }
}

function Install-ScoopApp($Name, [switch]$Sudo) {
    wi "Checking '$Name'"
    $currentFG = $Host.UI.RawUI.ForegroundColor
    $currentBG = $Host.UI.RawUI.BackgroundColor
    $appInstalled = $null -ne (Get-ScoopApp $Name)
    if (!$appInstalled) {
        scoop install $Name
    }
    elseif ($Name -in $updates.Keys) {
        scoop update $Name
    }
    $Host.UI.RawUI.ForegroundColor = $currentFG
    $Host.UI.RawUI.BackgroundColor = $currentBG
}

wi "Starting minimal boostrap to get the system to a point where full installation scripts can run."

$currentExecutionPolicy = Get-ExecutionPolicy

if($currentExecutionPolicy -ne 'Unrestricted') {
    ww "Please set execution policy to 'Unrestricted' in a admin instance of PowerShell"
    ww "Set-ExecutionPolicy -ExecutionPolicy Unrestricted"
}

# Install Scoop
# ---------------------------------------- [Check for SCOOP] -----------------------------------------
Write-HeadingBlock -Message 'Check for SCOOP'

$scoopOk = Get-Command -Name scoop -ErrorAction SilentlyContinue
if ($null -eq $scoopOk) {
    ww 'Installing Scoop'
    Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://get.scoop.sh')
}
else {
    wi 'Scoop installed.'
}


if (-not (scoop bucket list).Name -contains 'main') {
    scoop bucket add main
}
if (-not (scoop bucket list).Name -contains 'extras') {
    scoop bucket add extras
}

$scoopConfiguration = (scoop export | ConvertFrom-Json)

# ------------------------------------------ [Check for GIT] -----------------------------------------
Write-HeadingBlock -Message 'Check for GIT'
if ($null -eq (Get-ScoopApp -Name 'git')) {
    ww 'Cannot find git in scoop, installing.'
    scoop install git
} else {
    wi "Git is installed."
}

git config --global credential.helper manager

# ------------------------------------------ [Update SCOOP] ------------------------------------------
Write-HeadingBlock -Message 'Update SCOOP'
scoop update *> $null
scoop status *> $null
$scoopConfiguration = (scoop export | ConvertFrom-Json)

# ------------------------------------------ [Check for gsudo] -----------------------------------------
Write-HeadingBlock -Message 'Check for gsudo'
if ($null -eq (Get-ScoopApp -Name 'gsudo')) {
    ww 'Cannot find gsudo in scoop, installing.'
    scoop install gsudo
} else {
    wi "gsudo is installed."
}

# ---------------------------------- [Check for PowerShell Core 7+] ----------------------------------
Write-HeadingBlock -Message 'Check for PowerShell Core 7+'
$runningInPowerShell = $host.Version.Major -le 5
$runningInPowerShellCoreButOld = $host.Version.Major -eq 6
$runningInPowerShellCore = $host.Version.Major -ge 7

if ($runningInPowerShell) {
    wi 'Running in PowerShell, ok to install / upgrade pwsh'
    while ((Get-Process -Name pwsh -ErrorAction SilentlyContinue).count -gt 0) {
        wi 'Waiting for all PowerSehll Core processes to stop...'
        Start-Sleep -Seconds 5
    }
    scoop install pwsh
    scoop update pwsh
} else {
    ww "You are running this in PowerShell Core (pwsh) please run this in Windows Powershell so PowerShell Core can be installed."
} 


# ------------------------------------------ [Check for WinGet] -----------------------------------------
Write-HeadingBlock -Message 'Check for WinGet'

wi 'Checking for Nuget Package Provider'
if($null -eq (Get-PackageProvider -Name Nuget)) {
    Install-PackageProvider -Name NuGet -Scope CurrentUser -Force
}

wi "Checking the PSGallery is Trusted"
if((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
    Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
}

$pwsh7Cmd = Get-Command 'pwsh.exe' -ErrorAction SilentlyContinue
$pwsh7Exe = $pwsh7Cmd.Path

wi "Installing Winget modules if missing and validating winget is OK."

& $pwsh7Exe -ExecutionPolicy Bypass -NoProfile -NoLogo -NonInteractive -Command "if (`$null -eq (Get-Module -Name 'Microsoft.WinGet.Client' -All -ListAvailable)) { Install-Module Microsoft.WinGet.Client -Scope CurrentUser -Force }"
& $pwsh7Exe -ExecutionPolicy Bypass -NoProfile -NoLogo -NonInteractive -Command "if (`$null -eq (Get-Module -Name 'Microsoft.WinGet.Configuration' -All -ListAvailable)) { Install-Module Microsoft.WinGet.Configuration -Scope CurrentUser -Force }"
& $pwsh7Exe -ExecutionPolicy Bypass -NoProfile -NoLogo -NonInteractive -Command 'Repair-WinGetPackageManager -Latest -Force -Verbose'

# ------------------------------------------ [Base System DSC] -----------------------------------------
Write-HeadingBlock -Message 'Configure Base System DSC'

$baseSystemDscFile = Resolve-Path $PSScriptRoot/basesystem.dsc.yaml
gsudo winget configure -f $baseSystemDscFile --accept-configuration-agreements

# ---------------------------------------- [Check for Required Modules] -----------------------------------------
Write-HeadingBlock -Message 'Check for Required Modules'

$expectedPowerShellModules = @(
    'poshlog',
    'Microsoft.PowerShell.ConsoleGuiTools',
    'SimpleSettings'
)

foreach ($moduleName in $expectedPowerShellModules) {
    wi "Checking that $moduleName module is installed."
    & $pwsh7Exe -ExecutionPolicy Bypass -NoProfile -NoLogo -NonInteractive -Command "if (`$null -eq (Get-Module -Name '$moduleName' -All -ListAvailable)) { Install-Module $moduleName -Scope CurrentUser -Force }"
}

wi "Ready for execution of Start-SystemSetup.ps1 to complete local configuration."
wi "Please run the following command to complete the setup."
wi " "
wi "& $pwsh7Exe -ExecutionPolicy Bypass -NoProfile -NoLogo -NonInteractive -Command '$PSScriptRoot\Start-SystemSetup.ps1'"
