#Requires -PSEdition Desktop
# This is run in powershell. It sets up all the 
# installers and gets git and pwsh running and then
# the other installers can run.

# This should always be 100% idempotent.
function wi($message) {
    Write-Host "[$(Get-Date -Format 'yyyyMMdd-hhmmss')][INF] $message"
}

function ww($message) {
    Write-Warning $message
}

function Write-HeadingBlock($Message) {
    Write-Host "[$(Get-Date -Format 'yyyyMMdd-hhmmss')][INF] "
    Write-Host "[$(Get-Date -Format 'yyyyMMdd-hhmmss')][INF] --- [$Message] ---"
}

function Get-ScoopApp($Name) {
    return $scoopConfiguration.apps | Where-Object { $_.Name -eq $Name }
}

function Update-ScoopApp($Name) {
    if (($scoopStatus | Where-Object { $_.Name -eq $Name })) { 
        wi "Updating $Name to: '$(($scoopStatus | Where-Object {$_.Name -eq $Name}).'Latest Version')'"
        scoop update $Name
    }
}

$trueValues = @{
    'Y'    = $true
    'YES'  = $true
    'TRUE' = $true
    1      = $true
}

#
# ---------------------------------- [Log Environment Configuration] ---------------------------------
#
Write-HeadingBlock -Message 'Environment Configuration Used'

wi "        SYSTEM_SCRIPTS_ROOT: '$env:SYSTEM_SCRIPTS_ROOT'"
wi "      SYSTEM_AUTO_RUN_SETUP: '$env:SYSTEM_AUTO_RUN_SETUP'"
wi "     SYSTEM_SKIP_WINGET_DSC: '$env:SYSTEM_SKIP_WINGET_DSC'"
wi " SIMPLESETTINGS_CONFIG_FILE: '$env:SIMPLESETTINGS_CONFIG_FILE'"
wi "                USERPROFILE: '$env:USERPROFILE'"
wi ""

wi "Starting minimal boostrap to get the system to a point where full installation scripts can run."

$currentExecutionPolicy = Get-ExecutionPolicy

if ($currentExecutionPolicy -ne 'Unrestricted') {
    ww "Please set execution policy to 'Unrestricted' in a admin instance of PowerShell, it is currently set to '$currentExecutionPolicy'."
    ww "Set-ExecutionPolicy -ExecutionPolicy Unrestricted"
}

# Install Scoop
# ---------------------------------------- [Check for SCOOP] -----------------------------------------
Write-HeadingBlock -Message 'Check for SCOOP'

$scoopOk = Get-Command -Name scoop -ErrorAction SilentlyContinue
if ($null -eq $scoopOk) {
    ww 'Installing Scoop'
    Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://get.scoop.sh')
} else {
    wi 'Scoop installed.'
    scoop update *> $null
}

$scoopConfiguration = (scoop export | ConvertFrom-Json)
$scoopStatus = (scoop status --local)

# ------------------------------------------ [Check for GIT] -----------------------------------------
# Minial footprint on start, just make sure git is around and any other scoop dependcies it has.
Write-HeadingBlock -Message 'Check for GIT'
if ($null -eq (Get-ScoopApp -Name 'git')) {
    ww 'Cannot find git in scoop, installing.'
    scoop install git
} else {
    wi 'Git is installed.'
    Update-ScoopApp -Name 'git'
}

# Setup the manager for global and system.
git config --global credential.helper manager
# git config --system credential.helper "!`"$((scoop info git -v).Installed.Replace("\","/"))/mingw64/bin/git-credential-manager.exe`""

# ------------------------------------------ [Add SCOOP Buckets] ------------------------------------------
Write-HeadingBlock -Message 'Add SCOOP Buckets'

if ((Get-Command 'git' -ErrorAction SilentlyContinue)) {
    git config --global --add safe.directory "$ENV:USERPROFILE/scoop/buckets/extras".Replace('\', '/')
    git config --global --add safe.directory "$ENV:USERPROFILE/scoop/buckets/main".Replace('\', '/')
}

foreach($bucket in @('main','extra')) { 
    if (-not (scoop bucket list).Name -contains $bucket) {
        scoop bucket add $bucket
        wi "$bucket bucket added."
    } else {
        wi "$bucket bucket already added."
    }
}

# ------------------------------------------ [Update SCOOP] ------------------------------------------
Write-HeadingBlock -Message 'Update SCOOP'
scoop update *> $null
$scoopConfiguration = (scoop export | ConvertFrom-Json)
$scoopStatus = (scoop status --local)
wi "Scoop updated."

# ------------------------------------------ [Check for gsudo] -----------------------------------------
Write-HeadingBlock -Message 'Check for gsudo'
if ($null -eq (Get-ScoopApp -Name 'gsudo')) {
    ww 'Cannot find gsudo in scoop, installing.'
    scoop install gsudo
} else {
    wi "gsudo is installed."
    Update-ScoopApp -Name 'gsudo'
}

# ---------------------------------- [Check for PowerShell Core 7+] ----------------------------------
Write-HeadingBlock -Message 'Check for PowerShell Core 7+'
$runningInPowerShell = $host.Version.Major -le 5

if ($runningInPowerShell) {
    wi 'Running in PowerShell, ok to install / upgrade pwsh'
    while ((Get-Process -Name pwsh -ErrorAction SilentlyContinue).count -gt 0) {
        wi 'Waiting for all PowerSehll Core processes to stop...'
        Start-Sleep -Seconds 5
    }
    if ($null -eq (Get-ScoopApp -Name 'pwsh')) {
        ww 'Cannot find pwsh in scoop, installing.'
        scoop install pwsh
    } else {
        wi "pwsh is installed."
        Update-ScoopApp -Name 'pwsh' 
    }    
} else {
    ww "You are running this in PowerShell Core (pwsh) please run this in Windows Powershell so PowerShell Core can be installed."
    exit 1
} 


# ------------------------------------------ [Check for WinGet] -----------------------------------------
Write-HeadingBlock -Message 'Check for WinGet'

wi 'Checking for Nuget Package Provider'
if ($null -eq (Get-PackageProvider -Name Nuget)) {
    Install-PackageProvider -Name NuGet -Force -Scope CurrentUser -Confirm:$false
}

wi "Checking the PSGallery is Trusted"
if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
    Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
}

$pwsh7Cmd = Get-Command 'pwsh.exe' -ErrorAction SilentlyContinue
$pwsh7Exe = $pwsh7Cmd.Path

wi "Installing WinGet modules if missing and validating winget is OK."

# Everything is expected to run in powershell core, if you are using the deskop more then this will not be
# a good experience.
& $pwsh7Exe -ExecutionPolicy Bypass -NoProfile -NoLogo -NonInteractive -Command "if (`$null -eq (Get-Module -Name 'Microsoft.WinGet.Client' -All -ListAvailable)) { Install-Module Microsoft.WinGet.Client -Scope CurrentUser -Force }"
& $pwsh7Exe -ExecutionPolicy Bypass -NoProfile -NoLogo -NonInteractive -Command "if (`$null -eq (Get-Module -Name 'Microsoft.WinGet.Configuration' -All -ListAvailable)) { Install-Module Microsoft.WinGet.Configuration -Scope CurrentUser -Force }"
& $pwsh7Exe -ExecutionPolicy Bypass -NoProfile -NoLogo -NonInteractive -Command 'Repair-WinGetPackageManager -Latest -Force -Verbose'

# ------------------------------------------ [Base System DSC] -----------------------------------------
Write-HeadingBlock -Message 'Configure Base System DSC'

if ($null -eq $env:SYSTEM_SKIP_WINGET_DSC -or -not $trueValues.ContainsKey($($env:SYSTEM_SKIP_WINGET_DSC).ToUpper())) {
    wi "Running Base DSC"
    $baseSystemDscFile = Resolve-Path $PSScriptRoot/basesystem.dsc.yaml
    gsudo winget configure -f $baseSystemDscFile --accept-configuration-agreements
} else {
    wi "Skipped running Base DSC"
}

# ---------------------------------------- [Check for Required Modules] -----------------------------------------
# Minial set of modules to make life easier. All in PowerShell Core.
Write-HeadingBlock -Message 'Check for Required Modules'

$expectedPowerShellModules = @(
    'poshlog',
    'Microsoft.PowerShell.ConsoleGuiTools',
    'SimpleSettings'
)

foreach ($moduleName in $expectedPowerShellModules) {
    wi "Checking that $moduleName module is installed."
    $installCommand = "if (`$null -eq (Get-Module -Name '$moduleName' -All -ListAvailable)) { Install-Module $moduleName -Scope CurrentUser -Force } else { Write-Host 'Module $moduleName is installed.' }"
    wi "Running:"
    wi "$installCommand"
    & $pwsh7Exe -ExecutionPolicy Bypass -NoProfile -NoLogo -NonInteractive -Command "& { $installCommand }"
}

# ---------------------------------------- [Notifiy user to run next step] -----------------------------------------
Write-HeadingBlock -Message 'Notifiy user to run next step'
wi " "
wi "Ready for execution of Start-SystemSetup.ps1 to complete local configuration."
wi "Please run the following command to complete the setup or press Enter/Y at prompt."
wi " "
wi "& '$pwsh7Exe' -ExecutionPolicy Bypass -NoProfile -NoLogo -NonInteractive -Command '$PSScriptRoot\Start-SystemSetup.ps1'"
wi " "
wi " "
wi "Start-SystemBootstrap Completed"

if ($null -eq $env:SYSTEM_AUTO_RUN_SETUP -or -not $trueValues.ContainsKey($($env:SYSTEM_AUTO_RUN_SETUP).ToUpper())) {
    $runNextStep = Read-Host -Prompt "Would you like to execute the system setup? (Y/n)"
} else {
    if ($trueValues.ContainsKey($($env:SYSTEM_AUTO_RUN_SETUP).ToUpper())) {
        $runNextStep = 'Y'
    } else {
        $runNextStep = 'N'
    }
}

if ($runNextStep -eq "" -or $runNextStep -eq "Y" -or $runNextStep -eq "y") {
    & $pwsh7Exe -ExecutionPolicy Bypass -NoProfile -NoLogo -NonInteractive -Command "$PSScriptRoot\Start-SystemSetup.ps1"
}


