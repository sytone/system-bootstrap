# system-bootstrap

The following enviroment variables need to be set to provide the path to the configuration used in bootstrap and your scripts root. If you are using OneDrive for this you can use the commands below.

```PowerShell
# Consumer
[System.Environment]::SetEnvironmentVariable('SYSTEM_SCRIPTS_ROOT', "$env:OneDriveConsumer\scripts", [System.EnvironmentVariableTarget]::User)
[System.Environment]::SetEnvironmentVariable('SIMPLESETTINGS_CONFIG_FILE', "$env:OneDriveConsumer\scripts\systemconfiguration.json", [System.EnvironmentVariableTarget]::User)
$env:SYSTEM_SCRIPTS_ROOT = "$env:OneDriveConsumer\scripts"
$env:SIMPLESETTINGS_CONFIG_FILE = "$env:OneDriveConsumer\scripts\systemconfiguration.json"

# Work or School
[System.Environment]::SetEnvironmentVariable('SYSTEM_SCRIPTS_ROOT', "$env:OneDriveCommercial\scripts", [System.EnvironmentVariableTarget]::User)
[System.Environment]::SetEnvironmentVariable('SIMPLESETTINGS_CONFIG_FILE', "$env:OneDriveConsumer\scripts\systemconfiguration.json", [System.EnvironmentVariableTarget]::User)
$env:SYSTEM_SCRIPTS_ROOT = "$env:OneDriveCommercial\scripts"
$env:SIMPLESETTINGS_CONFIG_FILE = "$env:OneDriveConsumer\scripts\systemconfiguration.json"

```

```PowerShell
iwr https://raw.githubusercontent.com/sytone/system-bootstrap/main/Get-BootstrapAndRun.ps1 | iex

```
