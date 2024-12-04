#Requires -Version 7
#
# PowerShell Core for bulk of environment setup.
#
# This should always be idempotent. It runs after the system bootstrap so we are in an expected
# enviroment with all the right installers in place. Configuration is driven by simple settings 
# configuration file.

[CmdletBinding()]
param (
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

function Write-FooterBlock() {
    Write-InfoLog -Message ""
}

$trueValues = @{
    'Y'    = $true
    'YES'  = $true
    'TRUE' = $true
    1      = $true
}

# Nothing but my profile setup is allowed...
# Customization is in local profile scripts.
$envLoadLine = "`n. `$env:USERPROFILE\Scripts\powershell\defaultprofile.ps1`n"
if ((Test-Path $profile) -eq $false) {
    New-Item $profile -Type File  -Force -ErrorAction 0 | Out-Null
}
$envLoadLine | Set-Content ($profile)

#
# ---------------------------------- [Log Environment Configuration] ---------------------------------
#
Write-HeadingBlock -Message 'Environment Configuration Used'

# If GIT is enabled we pull out the URL and set the root to the repo under the user profile.
if ($null -ne $env:SYSTEM_GIT_ENABLED -and $trueValues.ContainsKey($($env:SYSTEM_GIT_ENABLED).ToUpper())) {
    $env:SYSTEM_GIT_ENABLED = $true

    if ($env:SYSTEM_GIT_REPO -eq '') {
        ww 'GIT is enabled but no repo is set. Aborting.'
        ww "See the README.md files for information on setting this."
        return        
    }   
}

if ($null -eq $env:SYSTEM_SCRIPTS_ROOT -or $env:SYSTEM_SCRIPTS_ROOT -eq '') {
    ww "Unable get system scripts root."
    ww "Please set `$env:SYSTEM_SCRIPTS_ROOT to the root of your scripts folder"
    ww "See the README.md files for information on setting this."

    return
}

wi "       SYSTEM_SCRIPTS_ROOT: '$env:SYSTEM_SCRIPTS_ROOT'"
wi "        SYSTEM_GIT_ENABLED: '$env:SYSTEM_GIT_ENABLED'"
wi "SIMPLESETTINGS_CONFIG_FILE: '$env:SIMPLESETTINGS_CONFIG_FILE'"
wi "               USERPROFILE: '$env:USERPROFILE'"
wi "          OneDriveConsumer: '$env:OneDriveConsumer'"
wi "        OneDriveCommercial: '$env:OneDriveCommercial'"
wi "              COMPUTERNAME: '$env:COMPUTERNAME'"
wi "                USERDOMAIN: '$env:USERDOMAIN'"
wi " USERDOMAIN_ROAMINGPROFILE: '$env:USERDOMAIN_ROAMINGPROFILE'"
wi ""

Write-FooterBlock
#
# ---------------------------------- [GIT Pre Setup] ---------------------------------
#
Write-HeadingBlock -Message 'Running GIT Pre Setup'

if ($env:SYSTEM_GIT_ENABLED) {
    wi "GIT is enabled, setting up GIT"
    if (-not (Test-Path $env:SYSTEM_SCRIPTS_ROOT)) {
        wi "Cloning $($env:SYSTEM_GIT_REPO) into $($env:SYSTEM_SCRIPTS_ROOT)"
        git clone $env:SYSTEM_GIT_REPO $env:SYSTEM_SCRIPTS_ROOT
    } else {
        wi "Pulling latest from $($env:SYSTEM_GIT_REPO) into $($env:SYSTEM_SCRIPTS_ROOT)"
        Push-Location $env:SYSTEM_SCRIPTS_ROOT
        git pull
        Pop-Location
    }
} else {
    wi "GIT is not enabled, skipping GIT setup"
}

Write-FooterBlock
#
# ---------------------------------- [Start Main System Setup] ---------------------------------
#
Write-HeadingBlock -Message 'Running System Setup'

$settings = Get-SimpleSettingConfigurationFile
if ((Test-Path -Path $settings)) {
    wi "Using settings file: $settings"
    $currentSettings = Get-SimpleSetting 
    if ($null -eq $currentSettings -or $currentSettings -eq @{} -or ($currentSettings | ConvertTo-Json -Depth 10) -eq '{}') {
        ww "Unable to load settings file: $settings"
        ww "The file is invalid or empty, please set `$env:SIMPLESETTINGS_CONFIG_FILE to a valid configuration file."
        ww "See the README.md files for information on setting this."
        return
    }
} else {
    ww "Unable to find settings file: $settings"
    return
}

Write-FooterBlock
#
# ---------------------------------- [Create Scripts Junction Point] ---------------------------------
#
Write-HeadingBlock -Message 'Create Scripts Junction Point'

if (-not (Test-Path "$env:USERPROFILE\Scripts")) {
    wi "Creating the '$env:USERPROFILE\Scripts' junction"
    New-Item -ItemType Junction -Path "$env:USERPROFILE\Scripts" -Target "$env:SYSTEM_SCRIPTS_ROOT" -ErrorAction SilentlyContinue | Out-Null
}

$scriptProfilePath = get-item -Path "$env:USERPROFILE\Scripts" 

if ($scriptProfilePath.LinkType -eq 'Junction' -and $scriptProfilePath.ResolvedTarget -eq "$env:SYSTEM_SCRIPTS_ROOT") {
    wi "'$env:USERPROFILE\Scripts' is a Junction to '$env:SYSTEM_SCRIPTS_ROOT'"
} else {
    wi "Removing the '$env:USERPROFILE\Scripts' path"
    Remove-Item -Path "$env:USERPROFILE\Scripts" -Force -Recurse -ErrorAction SilentlyContinue 
    
    wi "Recreating the '$env:USERPROFILE\Scripts' junction"
    New-Item -ItemType Junction -Path "$env:USERPROFILE\Scripts" -Target "$env:SYSTEM_SCRIPTS_ROOT" -ErrorAction SilentlyContinue | Out-Null
    
    if (-not (Test-Path -Path "$env:USERPROFILE\Scripts\readme.md")) {
        wi 'Issue with mapped scripts path, aborting' 1
        return
    }
}

Write-FooterBlock
# --------------------------------------- [Make Scripts Offline] ---------------------------------------
Write-HeadingBlock -Message 'Make Scripts Offline in OneDrive'

if ($env:SYSTEM_GIT_ENABLED) {
    wi "GIT is enabled, skipping OneDrive offline setup"
} else {

    if ($null -eq (Get-Command -Name attrib -ErrorAction SilentlyContinue)) {
        $env:Path += ';C:\Windows\System32'
    }

    if ($env:OneDriveConsumer) {
        wi "Setting Offline for Onedrive Personal"
        $attribResult = attrib -U +P "$env:OneDriveConsumer\scripts\*" /S /D
        $attribResult = attrib -U +P "$env:OneDriveConsumer\Documents\PowerShell\*" /S /D
        $attribResult = attrib -U +P "$env:OneDriveConsumer\Documents\WindowsPowerShell\*" /S /D
    }

    if ($env:OneDriveCommercial) {
        wi "Setting Offline for Onedrive for Work or School"
        $attribResult = attrib -U +P "$env:OneDriveCommercial\scripts\*" /S /D
        $attribResult = attrib -U +P "$env:OneDriveCommercial\Documents\PowerShell\*" /S /D
        $attribResult = attrib -U +P "$env:OneDriveCommercial\Documents\WindowsPowerShell\*" /S /D
    }
}

Write-FooterBlock
# ---------------------------------------- [Environment Setup] ---------------------------------------
Write-HeadingBlock -Message 'Checking enviroment for machine and domain'

wi "Computer Name: $env:COMPUTERNAME"
if ($env:USERDOMAIN) {
    $userDomain = $env:USERDOMAIN
} else {
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

Write-FooterBlock
# ------------------------------------------ [Configure SCOOP] ------------------------------------------
Write-HeadingBlock -Message 'Configure SCOOP'
$scoopConfiguration = Get-SimpleSetting -Section 'SystemSetup' -Name 'ScoopConfiguration' -DefaultValue @{}

foreach ($config in $scoopConfiguration.PSObject.Properties) {
    if ($config.Value -eq 'TRUE' -or $config.Value -eq '1' -or $config.Value -eq $true) {
        $config.Value = $true
    } else {
        $config.Value = $false
    }

    if ((scoop config $($config.Name)) -eq $config.Value) {
        wi "Skipping scoop configuration '$($config.Name)' as it is already set to '$($config.Value)'"
        continue
    }

    wi "Setting scoop configuration '$($config.Name)' to '$($config.Value)'"
    scoop config $($config.Name) $config.Value
}

Write-FooterBlock
# ------------------------------------------ [Update SCOOP] ------------------------------------------
Write-HeadingBlock -Message 'Update SCOOP'
scoop update *> $null
$scoopConfiguration = (scoop export | ConvertFrom-Json)

Write-FooterBlock
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
        } else {
            wi "Adding scoop bucket '$($_[0])''"
            scoop bucket add $_[0]
        }
    } else {
        wi "Skpping scoop bucket '$($_[0])' as it is already added."

    }
}

Write-FooterBlock
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

foreach ($app in $Script:defaultScoopApps) {
    Install-ScoopApp -Name $app
}

foreach ($app in $Script:machineScoopApps) {
    Install-ScoopApp -Name $app
}

foreach ($app in $Script:domainScoopApps) {
    Install-ScoopApp -Name $app
}

Write-FooterBlock
# ---------------------------------- [ Update SCOOP applications ] ----------------------------------
Write-HeadingBlock -Message 'Update SCOOP applications'

$appStatus = scoop status --local
$appStatus | ForEach-Object {
    wi "Updating $($_.Name) to $($_.'Latest Version') from $($_.'Installed Version')"
    scoop update $_.Name
}

Write-FooterBlock
# -------------------- [ Cleanup SCOOP ]
Write-HeadingBlock -Message 'Cleanup SCOOP'

try {
    scoop cleanup * *> $null
} catch {
    wi 'Error trying to cleanup, most likely a locked file...'
}

Write-FooterBlock
# -------------------- [Install / Update winget based packages] --------------------
Write-HeadingBlock -Message 'Install WinGet packages'

$defaultWinGetApps = Get-SimpleSetting -Section 'SystemSetup' -Name 'DefaultWinGetApps' -DefaultValue @()
$machineWinGetApps = Get-SimpleSetting -Section 'SystemSetup' -Name "$($env:COMPUTERNAME)WinGetApps" -DefaultValue @()
$domainWinGetApps = Get-SimpleSetting -Section 'SystemSetup' -Name "$($userDomain)WinGetApps" -DefaultValue @()

foreach ($app in $defaultWinGetApps) {
    wi "Installing Default WinGet package: $app"
    winget install $app --accept-source-agreements --accept-package-agreements
}

foreach ($app in $machineWinGetApps) {
    wi "Installing Machine WinGet package: $app"
    winget install $app --accept-source-agreements --accept-package-agreements
}

foreach ($app in $domainWinGetApps) {
    wi "Installing Domain WinGet package: $app"
    winget install $app --accept-source-agreements --accept-package-agreements
}

Write-FooterBlock
# -------------------- [Update powershell core mapping in tools] --------------------
Write-HeadingBlock -Message 'Updating powershell core mapping'

$toolsPath = Get-SimpleSetting -Section 'SystemSetup' -Name 'ToolsPath' -DefaultValue 'c:\tools'
wi "Using tools path: $toolsPath"

if (-not(Test-Path $toolsPath)) {
    wi "Creating tools path: $toolsPath"
    New-Item -ItemType Directory -Path $toolsPath -Force | Out-Null
}

Remove-Item -Path "$toolsPath\pwsh" -Force -Recurse -ErrorAction SilentlyContinue | Out-Null
New-Item -ItemType Junction -Path "$toolsPath\pwsh" -Target (get-item "$env:USERPROFILE\scoop\apps\pwsh\current").target -ErrorAction SilentlyContinue | Out-Null

Write-FooterBlock

# -------------------- [Update GIT configuration] --------------------
Write-HeadingBlock 'Update GIT configuration'

# if missing or not set then it will just skip the updates.
$gitConfiguration = Get-SimpleSetting -Section 'SystemSetup' -Name "gitConfiguration" -DefaultValue @{}

foreach ($config in $gitConfiguration.PSObject.Properties) {
    wi "Setting git configuration '$($config.Name)' to '$($config.Value)'"
    git config --global $($config.Name) $($config.Value)
}

Write-FooterBlock
# -------------------- [Run Powershell Help update in the background] --------------------
Write-HeadingBlock -Message 'Run Powershell Help update in the background'
$updateHelpJob = Start-Job -ScriptBlock { Update-Help -Scope CurrentUser }

Write-FooterBlock
# -------------------- [Local PS Gallery] --------------------
Write-HeadingBlock 'Setting up Local PS Gallery'
if ($null -ne $env:SYSTEM_USE_LOCAL_PSGALLERY -and $trueValues.ContainsKey($($env:SYSTEM_USE_LOCAL_PSGALLERY).ToUpper())) {
    $localPsGallerySource = Get-SimpleSetting -Section 'SystemSetup' -Name "localPSGallerySourcePath" -DefaultValue '' -ExpandVariables

    if ($localPsGallerySource -eq '') {
        wi "Unable get local PS Gallery Source root. Skipping local PS Gallery setup."
    } else {
        # Check for the management scripts
        $registerScript = Test-Path -Path "$localPsGallerySource\management\Register-LocalPSRepository.ps1"
        $installScript = Test-Path -Path "$localPsGallerySource\management\Install-AllLocalScripts.ps1"

        if ($registerScript -and $installScript) {
            wi "Running Register-LocalPSRepository.ps1"
            & "$localPsGallerySource\management\Register-LocalPSRepository.ps1"
            wi "Running Install-AllLocalScripts.ps1"
            & "$localPsGallerySource\management\Install-AllLocalScripts.ps1"
        } else {
            wi "Unable to find management scripts in $localPsGallerySource. Skipping local PS Gallery setup."
        }
    }
}

# -------------------- [Elevate cache enabled] --------------------
# Cache the elevations to reduce the number of prompts. Not secure but will clear
# once this script is done.
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
    } else {
        $newSettings = Get-ItemProperty -Path "$RegistryKeyPath" -Name $RegistryItemName
        wi "$RegistryItemDescription : Set $RegistryItemName to ($RegistryItemType)$RegistryItemValue"
        wi "$RegistryItemDescription : $RegistryItemName Actually ($RegistryItemType)$($newSettings."$RegistryItemName")"
    }
}

$registryChanges = Get-SimpleSetting -Section 'SystemSetup' -Name "registryChanges" -DefaultValue @()

foreach ($registryChange in $registryChanges) {
    Set-RegistryItem -RegistryKeyPath $registryChange.RegistryKeyPath -RegistryItemName $registryChange.RegistryItemName -RegistryItemType $registryChange.RegistryItemType -RegistryItemValue $registryChange.RegistryItemValue -RegistryItemDescription $registryChange.RegistryItemDescription
}

Write-FooterBlock
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

Write-FooterBlock
# -------------------- [Install Windows Features] --------------------
Write-HeadingBlock 'Install Windows Features'

$windowsFeatures = Get-SimpleSetting -Section 'SystemSetup' -Name "windowsFeatures" -DefaultValue @()   

foreach ($feature in $windowsFeatures) {
    wi "Checking for Windows Feature '$feature'"
    $featureInstalled = (gsudo { Get-WindowsOptionalFeature -FeatureName $args[0] -Online } -args $feature).State
    if (!$featureInstalled) {
        wi "Installing Windows Feature '$feature'"
        gsudo Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart
    } else {
        wi "Windows Feature '$feature' is already installed."
    }
}

Write-FooterBlock
# -------------------- [Update Windows Terminal Configuration] --------------------
Write-HeadingBlock 'Updating Windows Terminal Settings'

$windowsTerminalSettingsPath = Get-SimpleSetting -Section 'SystemSetup' -Name "windowsTerminalSettingsPath" -DefaultValue '' -ExpandVariables
if ($windowsTerminalSettingsPath -eq '') {
    wi 'No Windows Terminal settings path configured'
} else {
    # Even if the path is in the configuration, windows-teminal installed via scoop may not exist. So this will
    # skip if you are not using windows terminal via scoop.
    if ((Test-Path "$env:USERPROFILE\scoop\persist\windows-terminal")) {
        # Delete the settings path if it exists and make sure it points to the path
        # configured in settings.
        $persistedWindowsTerminalSettingsExists = Test-Path "$env:USERPROFILE\scoop\persist\Windows-Terminal\settings"
        if($persistedWindowsTerminalSettingsExists) {
            Remove-Item -Path "$env:USERPROFILE\scoop\persist\Windows-Terminal\settings" -Force -Recurse
        }
        
        wi 'Creating symbolic link for Windows Terminal Settings'
        $wtLink = New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\scoop\persist\Windows-Terminal\settings" -Target $windowsTerminalSettingsPath
        if ($null -eq $wtLink) {
            ww "Unable to create Windows Terminal symlink"
        }
    }
}

Write-FooterBlock
# -------------------- [Setup expected folder structure] --------------------
Write-HeadingBlock 'Check for expected folder structure'
$coreFunctionsRoot = Join-Path -Path $env:SYSTEM_SCRIPTS_ROOT -ChildPath "/powershell/CoreFunctions"
$coreModulesAuto = Join-Path -Path $env:SYSTEM_SCRIPTS_ROOT -ChildPath "/powershell/CoreModulesAuto"
$coreModulesManual = Join-Path -Path $env:SYSTEM_SCRIPTS_ROOT -ChildPath "/powershell/CoreModulesManual"

if (-not (Test-Path $coreFunctionsRoot)) {
    wi "Creating $coreFunctionsRoot"
    New-Item -ItemType Directory -Path $coreFunctionsRoot -Force | Out-Null
}

if (-not (Test-Path $coreModulesAuto)) {
    wi "Creating $coreModulesAuto"
    New-Item -ItemType Directory -Path $coreModulesAuto -Force | Out-Null
}

if (-not (Test-Path $coreModulesManual)) {
    wi "Creating $coreModulesManual"
    New-Item -ItemType Directory -Path $coreModulesManual -Force | Out-Null
}

Write-FooterBlock
# -------------------- [Run any domain or machine specific actions] --------------------
Write-HeadingBlock 'Checking for machine/domain specific scripts...'
$localScript = "$coreFunctionsRoot/Start-SystemSetup-local.ps1"
$domainScript = "$coreFunctionsRoot/Start-SystemSetup-$($userDomain).ps1"
$machineScript = "$coreFunctionsRoot/Start-SystemSetup-$($env:COMPUTERNAME).ps1"

wi "Checking for $localScript"
if (Test-Path $localScript) {
    Write-HeadingBlock "Running $localScript"
        & $pwsh7Exe -ExecutionPolicy Bypass -NoLogo -NonInteractive -Command $localScript

    & $localScript
}

wi "Checking for $domainScript"
if (Test-Path $domainScript) {
    Write-HeadingBlock "Running $domainScript"
    & $domainScript
}

wi "Checking for $machineScript"
if (Test-Path $machineScript) {
    Write-HeadingBlock "Running $machineScript"
    & $machineScript
}

Write-FooterBlock
# -------------------- [Run any admin domain or machine specific actions] --------------------
Write-HeadingBlock 'Checking for machine/domain specific scripts...'
$localScriptAdmin = "$coreFunctionsRoot/Start-SystemSetupAdmin-local.ps1"
$domainScriptAdmin = "$coreFunctionsRoot/Start-SystemSetupAdmin-$($userDomain).ps1"
$machineScriptAdmin = "$coreFunctionsRoot/Start-SystemSetupAdmin-$($env:COMPUTERNAME).ps1"

wi "Checking for $localScriptAdmin"
if (Test-Path $localScriptAdmin) {
    Write-HeadingBlock "Running $localScriptAdmin"
    gsudo & $localScriptAdmin
}

wi "Checking for $domainScriptAdmin"
if (Test-Path $domainScriptAdmin) {
    Write-HeadingBlock "Running $domainScriptAdmin"
    gsudo & $domainScriptAdmin
}

wi "Checking for $machineScriptAdmin"
if (Test-Path $machineScriptAdmin) {
    Write-HeadingBlock "Running $machineScriptAdmin"
    gsudo & $machineScriptAdmin
}

Write-FooterBlock
