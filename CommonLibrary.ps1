# Common Library and variables.

$version = "1.0.2"
$bootstrapFolder = "$env:temp\system-bootstrap"

$trueValues = @{
    'Y'    = $true
    'YES'  = $true
    'TRUE' = $true
    1      = $true
}

function Set-EnvironmentVariable($name, $value) {
    [System.Environment]::SetEnvironmentVariable($name, $value, "User")
    [System.Environment]::SetEnvironmentVariable($name, $value, "Process")
}


function Test-ValueIsTrue($Value) {
    if ($null -eq $Value) {
        return $false
    }

    if ($trueValues.ContainsKey($($Value).ToUpper())) {
        return $true
    } else {
        return $false
    }
}

if ($null -eq $env:SYSTEM_LOGGING_LEVEL) {
    Set-EnvironmentVariable 'SYSTEM_LOGGING_LEVEL' "INFO"
}

if ($null -eq $env:SYSTEM_SHOW_LOG_PREAMBLE) {
    Set-EnvironmentVariable 'SYSTEM_SHOW_LOG_PREAMBLE' "FALSE"
}

if ($null -eq $env:SYSTEM_SCRIPTS_ROOT) {
    Set-EnvironmentVariable 'SYSTEM_SCRIPTS_ROOT' "$($env:USERPROFILE)\scriptsrepo"
}

function Get-LoggingVerbose {
    if ($env:SYSTEM_LOGGING_LEVEL -eq 'VERBOSE') {
        return $true
    } else {
        return $false
    }
}

# Backup logging commands
function wi($message) {
    if (Test-ValueIsTrue $env:SYSTEM_SHOW_LOG_PREAMBLE) {
        Write-Host "[$(Get-Date -Format 'yyyyMMdd-hhmmss')][INF] $message"
    } else {
        Write-Host "$message"
    }
}

function wv($message) {
    if (Test-ValueIsTrue $env:SYSTEM_SHOW_LOG_PREAMBLE) {
        Write-Host "[$(Get-Date -Format 'yyyyMMdd-hhmmss')][VRB] $message"
    } else {
        Write-Host "[VRB] $message"
    }
}

function ww($message) {
    if (Test-ValueIsTrue $env:SYSTEM_SHOW_LOG_PREAMBLE) {
        Write-Host "[$(Get-Date -Format 'yyyyMMdd-hhmmss')][WRN] $message"
    } else {
        Write-Host "[WRN] $message"
    }
}

function Write-HeadingBlock($Message) {
    if (Test-ValueIsTrue $env:SYSTEM_SHOW_LOG_PREAMBLE) {
        Write-Host "[$(Get-Date -Format 'yyyyMMdd-hhmmss')][INF] "
        Write-Host "[$(Get-Date -Format 'yyyyMMdd-hhmmss')][INF] --- [$Message] ---"
    } else {
        Write-Host ""
        Write-Host "--- [$Message] ---"
    }
}

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
    if ($StepName.length -gt 80) {
        $StepName = $StepName.Substring(0, 30)
    }
    if ($Status.length -gt 80) {
        $Status = $Status.Substring(0, 40)
    }
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

function Start-StepExecution($steps) {
    foreach ($step in $steps) {
        Write-StepResult -StepName $step.name -Status 'Running' -InitialStatus

        if (-not ($step.PSObject.Properties.Name -contains "VerboseOutput")) {
            $step | Add-Member -MemberType NoteProperty -Name VerboseOutput -Value ""
        }
        if (-not ($step.PSObject.Properties.Name -contains "ErrorsOutput")) {
            $step | Add-Member -MemberType NoteProperty -Name ErrorsOutput -Value ""
        }
        if (-not ($step.PSObject.Properties.Name -contains "OutputVariable")) {
            $step | Add-Member -MemberType NoteProperty -Name OutputVariable -Value ""
        }
        $step.OutputVariable = "SYSTEM_STEP_$($step.id.ToUpper())"
        $status = Invoke-Command -ScriptBlock $step.script
    
        if ($status[0]) {
            $step.passed = $true
        } else {
            $step.passed = $false
        }

        $step.details = $status[2]     
        Set-EnvironmentVariable -name $step.OutputVariable -value $($step.details | ConvertTo-Json -Depth 10)
        Write-StepResult -StepName $step.name -Status $status[1]

        if ($step.passed -eq $false) {
            break
        }
    }

    if (Get-LoggingVerbose) {
        foreach ($step in $steps) {
            $verboseOutput = ""
            if ($step.passed -and $null -ne $step.details) {
                $detailsOutput = Invoke-Command -ScriptBlock $step.detailsAction -ArgumentList $step.details
                $verboseOutput += "$($detailsOutput)`n"
            }
            if ($step.passed -and $null -eq $step.details) {
                $verboseOutput += "$($step.name) - NA`n"
            }

            $step.VerboseOutput = $verboseOutput
        }
    }
    
    foreach ($step in $steps) {
        $errorsOutput = ""

        if (!$step.passed) {
            $errorOutput = Invoke-Command -ScriptBlock $step.errorAction -ArgumentList $step.details
            $errorsOutput += "$($errorOutput)`n"
        }

        $step.ErrorsOutput = $errorsOutput
    }

    $failedSteps = 0
    foreach ($step in $steps) {
        if (!$step.passed) {
            $failedSteps++
        }
    }

    return @{
        FailedSteps = $failedSteps
    }

}