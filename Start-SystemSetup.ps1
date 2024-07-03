#Requires -Version 7
#
# PowerShell Core for bulk of environment setup.
#
# This should always be idempotent. It runs after the system bootstrap so we are in an expected
# enviroment with all the right installers in place. Configuration is diriven by simple settings 
# configuration file.

[CmdletBinding()]
param (
    [Parameter()]
    [Switch]
    $SkipAdminUpdates,

    [String]
    $DomainOverride = ''
)

$expectedPowerShellModules = @(
    'poshlog',
    'Microsoft.PowerShell.ConsoleGuiTools',
    'SimpleSettings'
)

foreach ($moduleName in $expectedPowerShellModules) {
    Import-Module $moduleName
}

# ---------------------------------------- [Setup logging] -----------------------------------------
New-Logger |
Set-MinimumLevel -Value Verbose |
Add-SinkConsole -OutputTemplate '[{Timestamp:yyyyMMdd-HHmmss}][{Level:u3}] {Message:lj}{NewLine}{Exception}' |
Start-Logger

if (-not (Get-Command -Name Write-Notification -ErrorAction SilentlyContinue)) {
    function Write-Notification($Message) {
        Write-InfoLog $Message
    }
}
function wi($message) {
    Write-InfoLog $message
}

function ww($message) {
    Write-WarningLog $message
}

function Write-HeadingBlock($Message) {
    Write-InfoLog -Message "--- `e[32m[`e[0m$Message`e[32m]`e[0m ---"
}

Write-HeadingBlock -Message 'Running System Setup'

$settings = Get-SimpleSettingConfigurationFile
if ((Test-Path -Path $settings)) {
    wi "Using settings file: $settings"
    $currentSettings = Get-SimpleSetting 
    if ($null -eq $currentSettings -or $currentSettings -eq @{} -or ($currentSettings | ConvertTo-Json -Depth 10) -eq '{}') {
        ww "Unable to load settings file: $settings"
        ww "The file is invalid or empty, please set `$env:SIMPLESETTINGS_CONFIG_FILE to a valid configuration file."
        ww "See the readme.md files for information on setting this."
        return
    }
}
else {
    ww "Unable to find settings file: $settings"
    return
}

#
# ---------------------------------- [Create Scripts Junction Point] ---------------------------------
#
Write-HeadingBlock -Message 'Create Scripts Junction Point'

if($null -eq $env:SYSTEM_SCRIPTS_ROOT -or $env:SYSTEM_SCRIPTS_ROOT -eq '') {
    ww "Unable get system scripts root."
    ww "The file is invalid or empty, please set `$env:SYSTEM_SCRIPTS_ROOT to the root of your scripts folder"
    ww "See the readme.md files for information on setting this."

    return
}

if(-not (Test-Path "$env:USERPROFILE\Scripts")) {
    wi "Creating the '$env:USERPROFILE\Scripts' junction"
    New-Item -ItemType Junction -Path "$env:USERPROFILE\Scripts" -Target "$env:SYSTEM_SCRIPTS_ROOT" -ErrorAction SilentlyContinue | Out-Null
}

$scriptProfilePath = get-item -Path "$env:USERPROFILE\Scripts" 

if ($scriptProfilePath.LinkType -ne 'Junction' -and $scriptProfilePath.ResolvedTarget -ne "$env:SYSTEM_SCRIPTS_ROOT") {
    wi "Removing the '$env:USERPROFILE\Scripts' path"
    Remove-Item -Path "$env:USERPROFILE\Scripts" -Force -Recurse -ErrorAction SilentlyContinue 
    
    wi "recreating the '$env:USERPROFILE\Scripts' junction"
    New-Item -ItemType Junction -Path "$env:USERPROFILE\Scripts" -Target "$env:SYSTEM_SCRIPTS_ROOT" -ErrorAction SilentlyContinue | Out-Null
    
    if (-not (Test-Path -Path "$env:USERPROFILE\Scripts\readme.md")) {
        wi 'Issue with mapped scripts path, aborting' 1
        return
    }
}
else {
    wi "'$env:USERPROFILE\Scripts' is a Junction to '$env:SYSTEM_SCRIPTS_ROOT'"
}

# --------------------------------------- [Make Scripts Offline] ---------------------------------------
Write-HeadingBlock -Message 'Make Scripts Offline in OneDrive'

if ($null -eq (Get-Command -Name attrib -ErrorAction SilentlyContinue)) {
    $env:Path += ';C:\Windows\System32'
}

wi "Setting Offline for Onedrive Personal"
$attribResult = attrib -U +P "$env:OneDriveConsumer\scripts\*" /S /D
$attribResult = attrib -U +P "$env:OneDriveConsumer\Documents\PowerShell\*" /S /D
$attribResult = attrib -U +P "$env:OneDriveConsumer\Documents\WindowsPowerShell\*" /S /D

if ($env:OneDriveCommercial) {
    wi "Setting Offline for Onedrive for Work or School"
    $attribResult = attrib -U +P "$env:OneDriveCommercial\scripts\*" /S /D
    $attribResult = attrib -U +P "$env:OneDriveCommercial\Documents\PowerShell\*" /S /D
    $attribResult = attrib -U +P "$env:OneDriveCommercial\Documents\WindowsPowerShell\*" /S /D
}

# ---------------------------------------- [Environment Setup] ---------------------------------------
Write-HeadingBlock -Message 'Checking enviroment for machine and domain'

wi "Computer Name: $env:COMPUTERNAME"
if ($env:USERDOMAIN) {
    $userDomain = $env:USERDOMAIN
}
else {
    $userDomain = $env:USERDOMAIN_ROAMINGPROFILE
}

if ($env:COMPUTERNAME -eq $env:USERDOMAIN) {
    # Not network joined, may have a work/school account. Only look at first one.
    if ((Test-Path 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WorkplaceJoin\JoinInfo') -and (Get-Item 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WorkplaceJoin\JoinInfo').SubKeyCount -eq 1) {
        $userEmail = ((Get-ChildItem 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WorkplaceJoin\JoinInfo')[0] | Get-ItemProperty -Name UserEmail).UserEmail
        $userDomain = Get-SimpleSetting -Section 'SystemSetup' -Name "$userEmail-MappedDomain" -DefaultValue $env:COMPUTERNAME
    }
}

if ($DomainOverride -ne '') {
    $userDomain = $DomainOverride
}

wi "Computer Domain: $userDomain"

# ------------------------------------------ [Update SCOOP] ------------------------------------------
Write-HeadingBlock -Message 'Update SCOOP'
scoop update *> $null
$scoopConfiguration = (scoop export | ConvertFrom-Json)

# -------------------------------------- [Update SCOOP buckets] --------------------------------------
Write-HeadingBlock -Message 'Update SCOOP buckets'

$Script:installedBuckets = $(scoop bucket list).Name -join ','
$scoopBuckets = Get-SimpleSetting -Section 'SystemSetup' -Name 'DefaultScoopBuckets' -DefaultValue @()

$scoopBuckets | ForEach-Object {
    wi "Checking for scoop bucket '$($_[0])'"
    if (!$Script:installedBuckets.Contains($_[0])) {
        if ($_[1] -ne '') {
            wi "Adding scoop bucket '$($_[0])' -> '$($_[1])'"
            scoop bucket add $_[0] $_[1]
        }
        else {
            wi "Adding scoop bucket '$($_[0])''"
            scoop bucket add $_[0]
        }
    }
    else {
        wi "Skpping scoop bucket '$($_[0])' as it is already added."

    }
}

# ---------------------------------- [ Install SCOOP applications ] ----------------------------------
Write-HeadingBlock -Message 'Install SCOOP applications'

function Get-ScoopApp($Name) {
    return $scoopConfiguration.apps | Where-Object { $_.Name -eq $Name }
}

function Install-ScoopApp($Name, [switch]$Sudo) {
    wi "Checking for installation of '$Name'"
    $currentFG = $Host.UI.RawUI.ForegroundColor
    $currentBG = $Host.UI.RawUI.BackgroundColor
    $appInstalled = $null -ne (Get-ScoopApp $Name)
    if (!$appInstalled) {
        scoop install $Name
    }
    $Host.UI.RawUI.ForegroundColor = $currentFG
    $Host.UI.RawUI.BackgroundColor = $currentBG
}

$Script:defaultScoopApps = Get-SimpleSetting -Section 'SystemSetup' -Name 'DefaultScoopApps' -DefaultValue @()
$Script:machineScoopApps = Get-SimpleSetting -Section 'SystemSetup' -Name "$($env:COMPUTERNAME)ScoopApps" -DefaultValue @()
$Script:domainScoopApps = Get-SimpleSetting -Section 'SystemSetup' -Name "$($userDomain)ScoopApps" -DefaultValue @()

Install-ScoopApp -Name 'aria2'
scoop config aria2-enabled false *> $null
scoop config use_lessmsi true *> $null

foreach ($app in $Script:defaultScoopApps) {
    Install-ScoopApp -Name $app
}

foreach ($app in $Script:machineScoopApps) {
    Install-ScoopApp -Name $app
}

foreach ($app in $Script:domainScoopApps) {
    Install-ScoopApp -Name $app
}
# ---------------------------------- [ Update SCOOP applications ] ----------------------------------
Write-HeadingBlock -Message 'Update SCOOP applications'

$appStatus = scoop status
$appStatus | % {
    wi "Updating $($_.Name) to $($_.'Latest Version') from $($_.'Installed Version')"
    scoop update $_.Name
}

# -------------------- [ Cleanup SCOOP ]
Write-HeadingBlock -Message 'Cleanup SCOOP'

try {
    scoop cleanup * *> $null
}
catch {
    wi 'Error trying to cleanup, most likely a locked file...'
}

# -------------------- [Update powershell core mapping in tools] --------------------
Write-HeadingBlock -Message 'Updating powershell core mapping in c:\tools'
# Make this configurable at some point.

Remove-Item -Path "c:\tools\pwsh" -Force -Recurse -ErrorAction SilentlyContinue | Out-Null
New-Item -ItemType Junction -Path "c:\tools\pwsh" -Target (get-item "$env:USERPROFILE\scoop\apps\pwsh\current").target -ErrorAction SilentlyContinue | Out-Null

# -------------------- [Update Windows Terminal Configuration] --------------------
Write-HeadingBlock 'Updating Windows Terminal Settings'

$windowsTerminalSettingsPath = Get-SimpleSetting -Section 'SystemSetup' -Name "windowsTerminalSettingsPath" -DefaultValue ''
if ($windowsTerminalSettingsPath -eq '') {
    wi 'No Windows Terminal settings path configured'
}
else {
    if ($windowsTerminalSettingsPath.Contains("`$env:")) {
        $windowsTerminalSettingsPath = Invoke-Expression -Command "`"$windowsTerminalSettingsPath`""
    }

    # Even if the path is in the configuration, windows-teminal installed via scoop may not exist. So this will
    # skip if you are not using windows terminal via scoop.
    if ((Test-Path "$env:USERPROFILE\scoop\persist\windows-terminal")) {
        if (-not (Get-Item "$env:USERPROFILE\scoop\persist\Windows-Terminal\settings").LinkType -eq 'SymbolicLink') {
            wi 'Creating symbolic link for Windows Terminal Settings'
            Remove-Item -Path "$env:USERPROFILE\scoop\persist\Windows-Terminal\settings" -Force -Recurse
            $wtLink = New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\scoop\persist\Windows-Terminal\settings" -Target $windowsTerminalSettingsPath
            if ($null -eq $wtLink) {
                ww "Unable to create Windows Terminal symlink"
            }
        }
        else {
            wi 'Windows Terminal settings are already linked'
        }
    }
}


# -------------------- [Update GIT configuration] --------------------
Write-HeadingBlock 'Update GIT configuration'

# if missing or not set then it will just skip the updates.
$gitConfiguration = Get-SimpleSetting -Section 'SystemSetup' -Name "gitConfiguration" -DefaultValue @{}

foreach ($config in $gitConfiguration.PSObject.Properties) {
    wi "Setting git configuration '$($config.Name)' to '$($config.Value)'"
    git config --global $($config.Name) $($config.Value)
}

# -------------------- [Run Powershell Help update in the background] --------------------
Write-HeadingBlock -Message 'Run Powershell Help update in the background'
$updateHelpJob = Start-Job -ScriptBlock { Update-Help -Scope CurrentUser }

# -------------------- [Run any domain or machine specific actions] --------------------
Write-HeadingBlock 'Checking for machine/domain specific scripts...'
$domainScript = "Start-SystemSetup-$($userDomain).ps1"
$machineScript = "Start-SystemSetup-$($env:COMPUTERNAME).ps1"

wi "Checking for $PSScriptRoot/$domainScript"
if (Test-Path $PSScriptRoot/$domainScript) {
    Write-HeadingBlock "Running $domainScript"
    & $PSScriptRoot/$domainScript
}

wi "Checking for $PSScriptRoot/$machineScript"
if (Test-Path $PSScriptRoot/$machineScript) {
    Write-HeadingBlock "Running $machineScript"
    & $PSScriptRoot/$machineScript
}

# -------------------- [Run setup that need UAC if not skipped] --------------------
if ($SkipAdminUpdates) {
    return
}

gsudo cache on

# -------------------- [Update the registry] --------------------
Write-HeadingBlock 'Update the registry'
gsudo New-PSDrive -PSProvider registry -Root HKEY_CLASSES_ROOT -Name HKCR -ErrorAction SilentlyContinue | Out-Null

function Set-RegistryItem {
    param (
        $RegistryKeyPath,
        $RegistryItemName,
        $RegistryItemType,
        $RegistryItemValue,
        $RegistryItemDescription
    )
    if (-not(Test-Path -Path "$RegistryKeyPath")) {
        gsudo New-Item -Path "$RegistryKeyPath" -ItemType Directory -Force | Out-Null
    }
    if (-not(Get-ItemProperty -Path "$RegistryKeyPath" -Name $RegistryItemName -ErrorAction SilentlyContinue )) {
        gsudo New-ItemProperty -Path "$RegistryKeyPath" -Name $RegistryItemName -PropertyType $RegistryItemType -Value $RegistryItemValue #| Out-Null
    }

    if ((Get-ItemProperty -Path "$RegistryKeyPath" -Name $RegistryItemName -ErrorAction SilentlyContinue)) {
        gsudo Set-ItemProperty -Path "$RegistryKeyPath" -Name $RegistryItemName -Value $RegistryItemValue | Out-Null
    }

    if (-not(Get-ItemProperty -Path "$RegistryKeyPath" -Name $RegistryItemName -ErrorAction SilentlyContinue )) {
        wi "$RegistryItemDescription : Unable to set $RegistryItemName to ($RegistryItemType)$RegistryItemValue "
    }
    else {
        $newSettings = Get-ItemProperty -Path "$RegistryKeyPath" -Name $RegistryItemName
        wi "$RegistryItemDescription : Set $RegistryItemName to ($RegistryItemType)$RegistryItemValue"
        wi "$RegistryItemDescription : $RegistryItemName Actually ($RegistryItemType)$($newSettings."$RegistryItemName")"
    }
}

$registryChanges = Get-SimpleSetting -Section 'SystemSetup' -Name "registryChanges" -DefaultValue @()

foreach ($registryChange in $registryChanges) {
    Set-RegistryItem -RegistryKeyPath $registryChange.RegistryKeyPath -RegistryItemName $registryChange.RegistryItemName -RegistryItemType $registryChange.RegistryItemType -RegistryItemValue $registryChange.RegistryItemValue -RegistryItemDescription $registryChange.RegistryItemDescription
}


# -------------------- [Update scoop apps with reg files] --------------------
Write-HeadingBlock 'Update scoop apps with reg files'

function Import-RegistryFile {
    param (
        $RegistryFile,
        $Description
    )
    if ((Test-Path $RegistryFile)) {
        wi "Importing $Description"
        gsudo reg import $RegistryFile *> $null
    }
}

$scoopRegistryFiles = Get-SimpleSetting -Section 'SystemSetup' -Name "scoopRegistryFiles" -DefaultValue @()

foreach ($registryFile in $scoopRegistryFiles) {
    Import-RegistryFile -RegistryFile "$($env:USERPROFILE)\scoop\apps\$($registryFile.RegistryFile)" -Description $registryFile.Description
}

# -------------------- [Install Windows Features] --------------------
Write-HeadingBlock 'Install Windows Features'

$windowsFeatures = Get-SimpleSetting -Section 'SystemSetup' -Name "windowsFeatures" -DefaultValue @()   

foreach ($feature in $windowsFeatures) {
    wi "Checking for Windows Feature '$feature'"
    $featureInstalled = (gsudo { Get-WindowsOptionalFeature -FeatureName $args[0] -Online } -args $feature).State
    if (!$featureInstalled) {
        wi "Installing Windows Feature '$feature'"
        gsudo Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart
    }
    else {
        wi "Windows Feature '$feature' is already installed."
    }
}



