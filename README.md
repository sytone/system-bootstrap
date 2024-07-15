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
[System.Environment]::SetEnvironmentVariable('SIMPLESETTINGS_CONFIG_FILE', "$env:OneDriveCommercial\scripts\systemconfiguration.json", [System.EnvironmentVariableTarget]::User)
$env:SYSTEM_SCRIPTS_ROOT = "$env:OneDriveCommercial\scripts"
$env:SIMPLESETTINGS_CONFIG_FILE = "$env:OneDriveCommercial\scripts\systemconfiguration.json"

```

```PowerShell
iwr https://raw.githubusercontent.com/sytone/system-bootstrap/main/Get-BootstrapAndRun.ps1 | iex
```

## Local Powershell Repository

To make scripts a bit more portable, this uses a local PSRepository. The packages are all stored in `{onedrive work/personal}/localpsgallery` and published to that location or installed from that location. It is a simple way to manage your personal scripts and have history if you want.

To use this create a folder where you want to master your power shell scripts to be used across machines, this can be in a cloud based store like onedrive, currently only onedrive is supported but others could be added if there are ENV variables availible. You could use a git repo but again that is not supported in the scripts currently.

In this folder create a management directory and copy the files from the management folder in this repo to that folder.

- Add-NewScrIpt - Creates a new script in the folder below management with the right headers to allow publishing.
- Install-AllLocalScripts.ps1 - Installs all scripts in the repo to the local machine.
- Publish-ScriptLocally.ps1 - Publishes all scripts in the local folder to the repo.
- Register-LocalPSRepository.ps1 - Registers the local repo so powershell can use it.
