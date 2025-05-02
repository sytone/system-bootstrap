#Requires -PSEdition Desktop
# This is run in powershell. It sets up all the 
# installers and gets git and pwsh running and then
# the other installers can run.

. $PSScriptRoot\CommonLibrary.ps1

# This should always be 100% idempotent.
function Get-ScoopApp($Name) {
    $scoopConfiguration = ($env:SYSTEM_STEP_GET_SCOOP_CONFIGURATION | ConvertFrom-Json)
    return $scoopConfiguration.apps | Where-Object { $_.Name -eq $Name }
}

function Update-ScoopApp($Name) {
    $result = "";
    if (((Test-Path 'env:SYSTEM_STEP_GET_SCOOP_STATUS') -eq $false) -or ($null -eq $env:SYSTEM_STEP_GET_SCOOP_STATUS) -or ($env:SYSTEM_STEP_GET_SCOOP_STATUS -eq '')) {
        return
    }
    $scoopStatus = ($env:SYSTEM_STEP_GET_SCOOP_STATUS | ConvertFrom-Json)
    if (($scoopStatus | Where-Object { $_.Name -eq $Name })) { 
        $result += "Updating $Name to: '$(($scoopStatus | Where-Object {$_.Name -eq $Name}).'Latest Version')'`n"
        $command = "scoop update $Name *>&1"
        $result += Invoke-Expression $command
        $result += $updateOutput
    }
    return $result
}

function Install-ScoopApp($Name) {
    $command = "scoop install $Name *>&1"
    $result = Invoke-Expression $command
    return $result
}

function Get-ScoopAppVersion($Name) {
    $scoopVersions = scoop list
    if (($scoopVersions | Where-Object { $_.Name -eq $Name })) { 
        return $(($scoopVersions | Where-Object { $_.Name -eq $Name }).Version)
    }
}

function Get-ScoopAppLatestVersion($Name) {
    if (((Test-Path 'env:SYSTEM_STEP_GET_SCOOP_STATUS') -eq $false) -or ($null -eq $env:SYSTEM_STEP_GET_SCOOP_STATUS) -or ($env:SYSTEM_STEP_GET_SCOOP_STATUS -eq '')) {
        return ''
    }
    $scoopStatus = ($env:SYSTEM_STEP_GET_SCOOP_STATUS | ConvertFrom-Json)
    if (($scoopStatus | Where-Object { $_.Name -eq $Name })) { 
        return $(($scoopStatus | Where-Object { $_.Name -eq $Name }).'Latest Version')
    }

    return ''
}

#
# ---------------------------------- [Log Environment Configuration] ---------------------------------
#
Write-HeadingBlock -Message 'Environment Configuration Used'

wi "        SYSTEM_SCRIPTS_ROOT: '$env:SYSTEM_SCRIPTS_ROOT'"
wi "       SYSTEM_LOGGING_LEVEL: '$env:SYSTEM_LOGGING_LEVEL'"
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
    exit 1
}
wi ""

$steps = @()

# Install Scoop
$steps += [pscustomobject]@{
    id            = 'install_scoop'
    name          = 'Install Scoop'
    description   = 'Installs Scoop and the required packages.'
    passed        = $false
    details       = $null
    errorAction   = {
        Write-Host 'Unable to install scoop.'
    }
    detailsAction = {}
    script        = {
        if ($null -eq (Get-Command -Name scoop -ErrorAction SilentlyContinue)) {
            Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://get.scoop.sh')
            return $true, "Scoop installed", $null
        } else {
            return $true, "Scoop already installed", $null
        }
    }
}

# Update Scoop
$updateScoopStep += [pscustomobject]@{
    id            = 'update_scoop'
    name          = 'Update Scoop'
    description   = 'Updates Scoop.'
    passed        = $false
    details       = $null
    errorAction   = {
        Write-Host 'Unable to update scoop.'
    }
    detailsAction = {}
    script        = {
        scoop update *> $null
        return $true, "Scoop updated", $null
    }
}

$steps += $updateScoopStep


# Get Scoop Configuration
$getScoopConfigurationStep = [pscustomobject]@{
    id            = 'get_scoop_configuration'
    name          = 'Get Scoop Configuration'
    description   = 'Gets the scoop configuration.'
    passed        = $false
    details       = $null
    errorAction   = {
        Write-Host 'Unable to get scoop configuration.'
    }
    detailsAction = {}
    script        = {
        $scoopConfiguration = (scoop export | ConvertFrom-Json)
        return $true, "Scoop configuration retrieved", $scoopConfiguration
    }
}

$steps += $getScoopConfigurationStep

# Get Scoop Status
$getScoopStatusStep += [pscustomobject]@{
    id            = 'get_scoop_status'
    name          = 'Get Scoop Status'
    description   = 'Gets the scoop status.'
    passed        = $false
    details       = $null
    errorAction   = {
        Write-Host 'Unable to get scoop status.'
    }
    detailsAction = {}
    script        = {
        $scoopStatus = (scoop status --local)
        return $true, "Scoop status retrieved", $scoopStatus
    }
}

$steps += $getScoopStatusStep


# Check for GIT and install if missing.
$steps += [pscustomobject]@{
    id            = 'check_git'
    name          = 'Check for GIT'
    description   = 'Checks for GIT and installs it if missing.'
    passed        = $false
    details       = $null
    errorAction   = {
        'Unable to check for GIT.'
        (Get-ChildItem function: | Where-Object { $_.Name -eq "Update-ScoopApp" } | ConvertTo-Json -Depth 1)
        # Write-Host $(Get-Command Update-ScoopApp -ErrorAction SilentlyContinue | ConvertTo-Json -Depth 10)
        # Update-ScoopApp -Name 'git'
    }
    detailsAction = {}
    script        = {
        if ($null -eq (Get-ScoopApp -Name 'git')) {
            $result = Install-ScoopApp -Name 'git'
            return $true, "GIT installed", @((scoop info git).Version, $result)
        } else {
            $result = Update-ScoopApp -Name 'git'
            return $true, "GIT already installed", @((scoop info git).Version, $result)
        }
    }
}

# Set default git configuration
$steps += [pscustomobject]@{
    id            = 'set_git_config'
    name          = 'Set GIT Configuration'
    description   = 'Sets the GIT configuration.'
    passed        = $false
    details       = $null
    errorAction   = {
        Write-Host 'Unable to set GIT configuration.'
    }
    detailsAction = {}
    script        = {
        git config --global credential.helper manager
        git config --global credential.helperselector.selected manager
        return $true, "GIT configuration set", $null
        # git config --system credential.helper "!`"$((scoop info git -v).Installed.Replace("\","/"))/mingw64/bin/git-credential-manager.exe`""

    }
}

# Add the scoop buckets
$steps += [pscustomobject]@{
    id            = 'add_scoop_buckets'
    name          = 'Add SCOOP Buckets'
    description   = 'Adds the SCOOP buckets.'
    passed        = $false
    details       = $null
    errorAction   = {
        Write-Host 'Unable to add SCOOP buckets.'
    }
    detailsAction = {}
    script        = {
        $buckets = @('main', 'extra')

        # if ((Get-Command 'git' -ErrorAction SilentlyContinue)) {
        #     git config --global --add safe.directory "$ENV:USERPROFILE/scoop/buckets/extras".Replace('\', '/')
        #     git config --global --add safe.directory "$ENV:USERPROFILE/scoop/buckets/main".Replace('\', '/')
        # }        
        foreach ($bucket in $buckets) { 
            if (-not (scoop bucket list).Name -contains $bucket) {
                scoop bucket add $bucket
            }
        }

        return $true, "SCOOP buckets added ($($buckets -join ','))", $buckets
    }
}

# Run Scoop updates and get status/config again.
$steps += $updateScoopStep
$steps += $getScoopConfigurationStep
$steps += $getScoopStatusStep

# Check for GSUDO and install if missing.
$steps += [pscustomobject]@{
    id            = 'check_gsudo'
    name          = 'Check for gsudo'
    description   = 'Checks for gsudo and installs it if missing.'
    passed        = $false
    details       = $null
    errorAction   = {
        Write-Host 'Unable to check for gsudo.'
    }
    detailsAction = {}
    script        = {
        if ($null -eq (Get-ScoopApp -Name 'gsudo')) {
            $result = Install-ScoopApp -Name 'gsudo'
            return $true, "gsudo installed", @((scoop info gsudo).Version, $result)
        } else {
            $result = Update-ScoopApp -Name 'gsudo'
            return $true, "gsudo already installed", @((scoop info gsudo).Version, $result)
        }
    }
}

# check for powershell core and install if missing or update if out of date.
$steps += [pscustomobject]@{
    id            = 'check_pwsh'
    name          = 'Check for PowerShell Core'
    description   = 'Checks for PowerShell Core and installs it if missing.'
    passed        = $false
    details       = $null
    errorAction   = {
        Write-Host 'Unable to check for PowerShell Core.'
    }
    detailsAction = {}
    script        = {
        $runningInPowerShell = $host.Version.Major -le 5
        if ($runningInPowerShell) {

            if ($null -eq (Get-ScoopApp -Name 'pwsh')) {
                $result = Install-ScoopApp -Name 'pwsh'
                return $true, "PowerShell Core installed", @((scoop info pwsh).Version, $result)
            } else {
                $updateVersion = Get-ScoopAppLatestVersion -Name 'pwsh'
                if ($updateVersion -ne '') {
                    $retryCount = 0
                    $attemptInstall = $true
                    while ((Get-Process -Name pwsh -ErrorAction SilentlyContinue).count -gt 0) {
                        if($retryCount -gt 5) {
                            # Skip PWSH update if process is still running after 5 checks.
                            $attemptInstall  = $false
                            break
                        }
                        Write-StepResult -StepName $step.name -Status "Waiting for PWSH process to stop ($retryCount)"
                        Start-Sleep -Seconds 5
                        $retryCount++
                    }
                    if($attemptInstall) {
                        $result = Update-ScoopApp -Name 'pwsh'
                        return $true, "PowerShell Core updated", @((scoop info pwsh).Version, $result)
                    } else {
                        # Not a failure but notify user.
                        return $true, "PowerShell Core Update Skipped", (scoop info pwsh).Version

                    }
                }
                return $true, "PowerShell Core up to date", (scoop info pwsh).Version
            }
        } else {
            return $false, "Failed, run in PowerShell Desktop not PowerShell Core", "You are running this in PowerShell Core (pwsh) please run this in Windows Powershell so PowerShell Core can be installed."
        } 
    }
}

# Check for WinGet and install if missing.
$steps += [pscustomobject]@{
    id            = 'check_winget'
    name          = 'Check for WinGet'
    description   = 'Checks for WinGet and installs it if missing.'
    passed        = $false
    details       = $null
    errorAction   = {
        Write-Host 'Unable to check for WinGet.'
    }
    detailsAction = {}
    script        = {
        if ($null -eq (Get-PackageProvider -Name Nuget)) {
            Install-PackageProvider -Name NuGet -Force -Scope CurrentUser -Confirm:$false
        }

        if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
        }

        $pwsh7Cmd = Get-Command 'pwsh.exe' -ErrorAction SilentlyContinue
        $pwsh7Exe = $pwsh7Cmd.Path   

        Write-StepResult -StepName 'Check for WinGet' -Status 'Checking: Microsoft.WinGet.Client'
        $clientResult = & $pwsh7Exe -ExecutionPolicy Bypass -NoProfile -NoLogo -NonInteractive -Command "if (`$null -eq (Get-Module -Name 'Microsoft.WinGet.Client' -All -ListAvailable)) { Install-Module Microsoft.WinGet.Client -Scope CurrentUser -Force }"
        Write-StepResult -StepName 'Check for WinGet' -Status 'Checking: Microsoft.WinGet.Configuration'
        $configurationResult = & $pwsh7Exe -ExecutionPolicy Bypass -NoProfile -NoLogo -NonInteractive -Command "if (`$null -eq (Get-Module -Name 'Microsoft.WinGet.Configuration' -All -ListAvailable)) { Install-Module Microsoft.WinGet.Configuration -Scope CurrentUser -Force }"
        Write-StepResult -StepName 'Check for WinGet' -Status 'Checking: Repair-WinGetPackageManager'
        $repairWinGetPackageManagerResult = & $pwsh7Exe -ExecutionPolicy Bypass -NoProfile -NoLogo -NonInteractive -Command 'Repair-WinGetPackageManager -Latest -Force'
        return $true, "WinGet Updated", @($clientResult, $configurationResult, $repairWinGetPackageManagerResult)

    }
}

# Configure DSC if enabled
$steps += [pscustomobject]@{
    id            = 'configure_dsc'
    name          = 'Configure DSC'
    description   = 'Configures the DSC.'
    passed        = $false
    details       = $null
    errorAction   = {
        Write-Host 'Unable to configure DSC.'
    }
    detailsAction = {}
    script        = {
        if ($null -eq $env:SYSTEM_SKIP_WINGET_DSC -or -not $trueValues.ContainsKey($($env:SYSTEM_SKIP_WINGET_DSC).ToUpper())) {
            $baseSystemDscFile = Resolve-Path $PSScriptRoot/basesystem.dsc.yaml
            gsudo winget configure -f $baseSystemDscFile --accept-configuration-agreements
            return $true, "DSC configured", $null
        } else {
            return $true, "DSC skipped", $null
        }
    }
}

# Check and install required modules
$steps += [pscustomobject]@{
    id            = 'check_required_modules'
    name          = 'Check for Required Modules'
    description   = 'Checks for required modules and installs them if missing.'
    passed        = $false
    details       = $null
    errorAction   = {
        Write-Host 'Unable to check for required modules.'
    }
    detailsAction = {}
    script        = {
        $expectedPowerShellModules = @(
            'poshlog',
            'Microsoft.PowerShell.ConsoleGuiTools',
            'SimpleSettings'
        )
        $pwsh7Cmd = Get-Command 'pwsh.exe' -ErrorAction SilentlyContinue
        $pwsh7Exe = $pwsh7Cmd.Path   
        $installCommands = @()

        foreach ($moduleName in $expectedPowerShellModules) {
            Write-StepResult -StepName 'Check for Required Modules' -Status "Checking: $moduleName"
            $installCommand = "if (`$null -eq (Get-Module -Name '$moduleName' -All -ListAvailable)) { Install-Module $moduleName -Scope CurrentUser -Force } else { Write-Host 'Module $moduleName is installed.' }"
            $installCommands += $installCommand
            & $pwsh7Exe -ExecutionPolicy Bypass -NoProfile -NoLogo -NonInteractive -Command "& { $installCommand }"
        }
        return $true, "Required modules installed", @($expectedPowerShellModules, $installCommands)
    }
}

$stepsOutcome = Start-StepExecution $steps

foreach ($step in $steps) {
    $step | ConvertTo-Json | Set-Content -Path "$PSScriptRoot\Logs\$($step.id).json"
}

if ($stepsOutcome.FailedSteps -gt 0) {
    Write-HeadingBlock -Message "One or more steps failed"

    foreach ($step in $steps) {
        if (!$step.passed) {
            Write-HeadingBlock -Message "$($step.name) failed."
            Write-Host "Details: $($step.details)"
            Write-Host "Output Variable: $($step.OutputVariable)"
            Write-Host "Verbose Output: $($step.VerboseOutput)"
            Write-Host "Error Output: $($step.ErrorsOutput)"
        }
    }
    
    exit 1
}

$pwsh7Cmd = Get-Command 'pwsh.exe' -ErrorAction SilentlyContinue
$pwsh7Exe = $pwsh7Cmd.Path   

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
