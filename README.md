# system-bootstrap

The following environment variables need to be set to provide the path to the configuration used in bootstrap and your scripts root. If you are using OneDrive for this you can use the commands below.

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

## Configuration

The configuration for this uses the PowerShell module SimpleSettings. Data is stored as a json file and there is an example in this repo to look at.

### Configuring Scoop Config

To specify any scoop configuration you can use the command below to set a value, this will be checked and updated prior to any scoop application installation or update. Update as needed for your environment.

```PowerShell
Set-SimpleSetting -Section 'SystemSetup' -Name 'ScoopConfiguration' -DefaultValue @{
    "aria2-enabled" = "FALSE"
    "use_lessmsi" = "TRUE"
    "use_sqlite_cache" = "TRUE"
}
```

## Bootstrap Options

### Auto Run Start-SystemSetup

To automatically run the setup without prompt set `$env:SYSTEM_AUTO_RUN_SETUP` to `'TRUE'` or `'Y'`

```PowerShell
[System.Environment]::SetEnvironmentVariable('SYSTEM_AUTO_RUN_SETUP', "TRUE", [System.EnvironmentVariableTarget]::User)
$env:SYSTEM_AUTO_RUN_SETUP = "TRUE"
```

### Skip the WinGet DSC

To skip the WinGet DSC running on bootstrap `$env:SYSTEM_SKIP_WINGET_DSC` to `'TRUE'` or `'Y'`

```PowerShell
[System.Environment]::SetEnvironmentVariable('SYSTEM_SKIP_WINGET_DSC', "TRUE", [System.EnvironmentVariableTarget]::User)
$env:SYSTEM_SKIP_WINGET_DSC = "TRUE"
```

### Desktop Shortcut

By default a desktop shortcut is created so you can run this process again to update your system. A shortcut is created on the desktop the pulls the latest version and runs the bootstrap process again. The process is idempotent so safe to run as many times as you want. To disable the creation of the shortcut set an environment variable called `SYSTEM_SKIP_DESKTOP_SHORTCUT_CREATION`

```PowerShell
[System.Environment]::SetEnvironmentVariable('SYSTEM_SKIP_DESKTOP_SHORTCUT_CREATION', "TRUE", [System.EnvironmentVariableTarget]::User)
$env:SYSTEM_SKIP_DESKTOP_SHORTCUT_CREATION = "TRUE"
```
## Local Powershell Repository

To make scripts a bit more portable, this uses a local PSRepository. The packages are all stored in `{onedrive work/personal}/localpsgallery` and published to that location or installed from that location. It is a simple way to manage your personal scripts and have history if you want.

To use this create a folder where you want to master your power shell scripts to be used across machines, this can be in a cloud based store like OneDrive, currently only OneDrive is supported but others could be added if there are ENV variables available. You could use a git repo but again that is not supported in the scripts currently.

In this folder create a management directory and copy the files from the management folder in this repo to that folder.

- Add-NewScrIpt - Creates a new script in the folder below management with the right headers to allow publishing.
- Install-AllLocalScripts.ps1 - Installs all scripts in the repo to the local machine.
- Publish-ScriptLocally.ps1 - Publishes all scripts in the local folder to the repo.
- Register-LocalPSRepository.ps1 - Registers the local repo so powershell can use it.

## Script directory structure

There are some conventions with this script. Under the scripts root it is expected to have folders per area/language. So for powershell the expected folder is `powershell`. Under this folder for powershell there is expected to be three subfolders. There are

- CoreFunctions
- CoreModulesAuto
- CoreModulesManual

If they do not exist the script creates them. CoreFunctions contains all your script that you write. CoreModulesAuto/Manual is where you put any customer modules, anything in the Auto folder will be automatically imported as a module.

## Testing Locally

To run and test this locally you can just run the `Get-BootstrapAndRun.ps1` command in powershell from the root of the repo, all paths are relative to the script location.
