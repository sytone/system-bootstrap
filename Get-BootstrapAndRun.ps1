#Requires -PSEdition Desktop
# Bootstrap should be run on windows powershell which is the desktop version.

$ESCAPE = $([char]27)
$NORMAL = "$ESCAPE[0m"

$WHITE_FOREGROUND = "$ESCAPE[37m"
$BLUE_FOREGROUND = "$ESCAPE[34m"
$GREEN_FOREGROUND = "$ESCAPE[32m"
$RED_BACKGROUND = "$ESCAPE[41m"
$BOLD = "$ESCAPE[1m"
function Write-StepResult {
    [CmdletBinding()]
    param(
        $StepName,
        $Status,
        [switch] $InitialStatus
    )

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
$steps = @()

$steps += [pscustomobject]@{
    name          = 'Creating system-bootstrap folder'
    description   = 'Creates the temporary bootstrap folder.'
    passed        = $false
    details       = $null
    errorAction   = {
        Write-Host 'Unable to make the temporary bootstrap folder.'
    }
    detailsAction = {}
    script        = {
        $bootstrapFolder = "$env:temp\system-bootstrap"
        New-Item -Path $bootstrapFolder -ItemType Directory -Force | Out-Null

        if (-not (Test-Path $bootstrapFolder)) {
            return $false, "Failed to create folder", "Folder failed to be created at: '$bootstrapFolder'"
        }

        return $true, "Folder created", "Folder created at: '$bootstrapFolder'"
    }
}

$steps += [pscustomobject]@{
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
            'Start-SystemSetup.ps1'
        )

        foreach ($file in $files) {
            $scriptDownload = Invoke-WebRequest "https://raw.githubusercontent.com/sytone/system-bootstrap/main/$file"
            $scriptDownload.Content | Out-File -FilePath "$bootstrapFolder\$file" -Force
        }

        foreach ($file in $files) {
            if (-not (Test-Path "$bootstrapFolder\$file")) {
                return $false, "Failed to download files", "$bootstrapFolder\$file"
            }
        }

        return $true, "Files downloaded", $files
    }
}

$steps += [pscustomobject]@{
    name          = 'Creating desktop shortcut'
    description   = 'Adds a shortcut to the desktop to make future updates simpler.'
    passed        = $false
    details       = $null
    errorAction   = {
        Write-Host 'Unable to create the desktop shortcut.'
    }
    detailsAction = {}
    script        = {

        if ($null -eq $env:SYSTEM_SKIP_DESKTOP_SHORTCUT_CREATION) {
            $linkPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "Update System.lnk"
            if(Test-Path $linkPath) {
                Remove-Item $linkPath -Force | Out-Null
            }
            $link = (New-Object -ComObject WScript.Shell).CreateShortcut($linkPath)
            $link.TargetPath = 'powershell'
            $link.Arguments = "-NoExit -NoProfile -Command `"iwr https://raw.githubusercontent.com/sytone/system-bootstrap/main/Get-BootstrapAndRun.ps1 | iex`""
            $link.Save()

            if (-not (Test-Path $linkPath)) {
                return $false, "Failed to create Update link", $linkPath
            }

            return $true, "Update Link created", $linkPath
        } else {
            return $true, "Update Link Skipped", $null
	}
    }
}


Write-Output ' __                _                      '
Write-Output '(_    __|_ _ ._ _ |_) _  __|_ __|_.__.._  '
Write-Output '__)\/_> |_(/_| | ||_)(_)(_)|__> |_|(_||_) '
Write-Output '   /                                  |   '
Write-Output ''

foreach ($step in $steps) {
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

foreach ($check in $checks) {
    if ($check.passed -and $null -ne $check.details) {
        $check.name
        Invoke-Command -ScriptBlock $check.detailsAction -ArgumentList $check.details
    }
    if ($check.passed -and $null -eq $check.details) {
        "$($check.name) - NA"
    }
}

foreach ($check in $checks) {
    if (!$check.passed) {
        $check.name
        Invoke-Command -ScriptBlock $check.errorAction -ArgumentList $check.details
    }
    if ($check.passed) {
        "$($check.name) - NA"
    }
}

foreach ($check in $checks) {
    if (!$check.passed) {
        exit 1
    }
}

Write-Output ""
Write-Output "Running $bootstrapFolder\Start-SystemBootstrap.ps1"
Write-Output ""
& "$bootstrapFolder\Start-SystemBootstrap.ps1"
