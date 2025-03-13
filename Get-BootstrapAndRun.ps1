#Requires -PSEdition Desktop
# Bootstrap should be run on windows powershell which is the desktop version.
$bootstrapFolder = "$env:temp\system-bootstrap"

function Write-StepResult {
    [CmdletBinding()]
    param(
        $StepName,
        $Status,
        [switch] $InitialStatus
    )

    $ESCAPE = $([char]27)
    $NORMAL = "$ESCAPE[0m"
    $WHITE_FOREGROUND = "$ESCAPE[37m"
    $GREEN_FOREGROUND = "$ESCAPE[32m"
    $RED_BACKGROUND = "$ESCAPE[41m"
    $dots = $("." * (80 - $StepName.length - $Status.length) )

    if ($Status -eq 'Failed') {
        Write-Host "`r$($StepName)$($dots)$WHITE_FOREGROUND$RED_BACKGROUND$($Status)$NORMAL"
    } else {
        if ($InitialStatus) {
            Write-Host "$($StepName)$($dots)$GREEN_FOREGROUND$($Status)$NORMAL" -NoNewline
        } else {
            Write-Host "`r$($StepName)$($dots)$GREEN_FOREGROUND$($Status)$NORMAL"
        }
    }
}
# To add checks, just duplicate one of the below checks and add the script blocks and
# update descriptions.
$initialSteps = @()

$initialSteps += [pscustomobject]@{
    id            = 'create_temp_folder'
    name          = 'Creating system-bootstrap folder'
    description   = 'Creates the temporary bootstrap folder.'
    passed        = $false
    details       = $null
    errorAction   = {
        Write-Host 'Unable to make the temporary bootstrap folder.'
    }
    detailsAction = {}
    script        = {
        New-Item -Path $bootstrapFolder -ItemType Directory -Force | Out-Null

        if (-not (Test-Path $bootstrapFolder)) {
            return $false, "Failed to create folder", "Folder failed to be created at: '$bootstrapFolder'"
        }

        return $true, "Folder created", "Folder created at: '$bootstrapFolder'"
    }
}

$initialSteps += [pscustomobject]@{
    id            = 'download_files'
    name          = 'Downloading system-bootstrap files'
    description   = 'Downloads the files from the system-bootstrap repo on github.'
    passed        = $false
    details       = $null
    errorAction   = {
        Write-Host 'Unable to download the files from github.'
    }
    detailsAction = {}
    script        = {
        $files = @(
            'Start-SystemBootstrap.ps1',
            'basesystem.dsc.yaml',
            'Start-SystemSetup.ps1',
            'CommonLibrary.ps1'
        )

        foreach ($file in $files) {
            try {
                if ($null -eq $env:SYSTEM_LOCAL_TEST) {
                    $scriptDownload = Invoke-WebRequest "https://raw.githubusercontent.com/sytone/system-bootstrap/main/$file"
                    $scriptDownload.Content | Out-File -FilePath "$bootstrapFolder\$file" -Force | Out-Null
                } else {
                    # testing locally. Copy the files from the local repo to the temp folder.
                    $scriptDownload = Copy-Item -Path "$PSScriptRoot\$file" -Destination "$bootstrapFolder\$file" -Force | Out-Null
                }

            } catch {
                return $false, "Failed to download files", "$bootstrapFolder\$file"
            }
        }

        foreach ($file in $files) {
            if (-not (Test-Path "$bootstrapFolder\$file")) {
                return $false, "Failed to download files", "$bootstrapFolder\$file"
            }
        }

        return $true, "Files downloaded", $files
    }
}

Write-Output "SYSTEM_LOCAL_TEST: '$env:SYSTEM_LOCAL_TEST'"

# Create folder and download first.

foreach ($step in $initialSteps) {
    Write-StepResult -StepName $step.name -Status 'Running' -InitialStatus

    $status = Invoke-Command -ScriptBlock $step.script

    if ($status[0]) {
        $step.passed = $true
        $step.details = $status[2]
        Write-StepResult -StepName $step.name -Status $status[1]
    } else {
        $step.passed = $false
        $step.details = $status[2]
        Write-StepResult -StepName $step.name -Status $status[1]
    }
}
if ($env:SYSTEM_LOGGING_LEVEL -eq 'VERBOSE') {

    foreach ($step in $initialSteps) {
        if ($step.passed -and $null -ne $step.details) {
            $step.name
            Invoke-Command -ScriptBlock $step.detailsAction -ArgumentList $step.details
        }
        if ($step.passed -and $null -eq $step.details) {
            "$($step.name) - NA"
        }
    }
}

foreach ($step in $initialSteps) {
    if (!$step.passed) {
        $step.name
        Invoke-Command -ScriptBlock $step.errorAction -ArgumentList $step.details
    }
}

foreach ($step in $initialSteps) {
    if (!$step.passed) {
        exit 1
    }
}

# Common library now available to use. Everything before this is native powershell commands only and nothing special.
$commonLibrary = "$bootstrapFolder\CommonLibrary.ps1"
. $commonLibrary

$finalSteps = @()

$finalSteps += [pscustomobject]@{
    id            = 'create_desktop_shortcut'
    name          = 'Creating desktop shortcut'
    description   = 'Adds a shortcut to the desktop to make future updates simpler.'
    passed        = $false
    details       = $null
    errorAction   = {
        Write-Host 'Unable to create the desktop shortcut.'
    }
    detailsAction = {}
    script        = {
        $linkPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "Update System.lnk"

        if ($null -eq $env:SYSTEM_SKIP_DESKTOP_SHORTCUT_CREATION) {
            # $latestCommit = ((Invoke-WebRequest "https://api.github.com/repos/sytone/system-bootstrap/branches/main") | ConvertFrom-Json).commit.sha
            # $downloadLink = "https://raw.githubusercontent.com/sytone/system-bootstrap/$($latestCommit)/Get-BootstrapAndRun.ps1"
            $downloadLink = "https://raw.githubusercontent.com/sytone/system-bootstrap/refs/heads/main/Get-BootstrapAndRun.ps1"
            if (Test-Path $linkPath) {
                Remove-Item $linkPath -Force | Out-Null
            }
            $link = (New-Object -ComObject WScript.Shell).CreateShortcut($linkPath)
            $link.TargetPath = 'powershell'
            $link.Arguments = "-NoExit -NoProfile -Command `"iwr $downloadLink | iex`""
            $link.Save()

            if (-not (Test-Path $linkPath)) {
                return $false, "Failed to create Update link", $linkPath
            }

            return $true, "Update Link created", $linkPath
        } else {
            return $true, "Update Link Skipped", $linkPath
        }
    }
}

if ($null -eq $env:SYSTEM_SKIP_DESKTOP_SHORTCUT_CREATION) {
    Set-EnvironmentVariable 'SYSTEM_SKIP_DESKTOP_SHORTCUT_CREATION' "FALSE"
}
# https://patorjk.com/software/taag/#p=display&h=0&v=0&f=Straight&t=System%20Bootstrap
wi '__                    __                               '
wi '(_      _ |_  _  _    |__)  _   _  |_  _ |_  _  _   _  '
wi '__) \/ _) |_ (- |||   |__) (_) (_) |_ _) |_ |  (_| |_) '
wi '    /                                              |   '
wi ''
wi "Version: $version"
Write-HeadingBlock -Message 'Environment Configuration Used'
wi " SYSTEM_SKIP_DESKTOP_SHORTCUT_CREATION: '$env:SYSTEM_SKIP_DESKTOP_SHORTCUT_CREATION'"
wi ""

$stepsOutcome = Start-StepExecution $finalSteps

if ($stepsOutcome.FailedSteps -gt 0) {
    Write-Host "One or more steps failed"
    exit 1
}

Write-HeadingBlock -Message "Running $bootstrapFolder\Start-SystemBootstrap.ps1"

& "$bootstrapFolder\Start-SystemBootstrap.ps1"
