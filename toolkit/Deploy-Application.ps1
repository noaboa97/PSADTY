<#
.SYNOPSIS
	This script performs the installation or uninstallation of an application(s).
	# LICENSE #
	PowerShell App Deployment Toolkit - Provides a set of functions to perform common application deployment tasks on Windows.
	Copyright (C) 2017 - Sean Lillis, Dan Cunningham, Muhammad Mashwani, Aman Motazedian.
	This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or any later version. This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
	You should have received a copy of the GNU Lesser General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.
.DESCRIPTION
	The script is provided as a template to perform an install or uninstall of an application(s).
	The script either performs an "Install" deployment type or an "Uninstall" deployment type.
	The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.
	The script dot-sources the AppDeployToolkitMain.ps1 script which contains the logic and functions required to install or uninstall an application.
.PARAMETER DeploymentType
	The type of deployment to perform. Default is: Install.
.PARAMETER DeployMode
	Specifies whether the installation should be run in Interactive, Silent, or NonInteractive mode. Default is: Interactive. Options: Interactive = Shows dialogs, Silent = No dialogs, NonInteractive = Very silent, i.e. no blocking apps. NonInteractive mode is automatically set if it is detected that the process is not user interactive.
.PARAMETER AllowRebootPassThru
	Allows the 3010 return code (requires restart) to be passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.
.PARAMETER TerminalServerMode
	Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Destkop Session Hosts/Citrix servers.
.PARAMETER DisableLogging
	Disables logging to file for the script. Default is: $false.
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeployMode 'Silent'; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -AllowRebootPassThru; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeploymentType 'Uninstall'; Exit $LastExitCode }"
.EXAMPLE
    Deploy-Application.exe -DeploymentType "Install" -DeployMode "Silent"
.NOTES
	Toolkit Exit Code Ranges:
	60000 - 68999: Reserved for built-in exit codes in Deploy-Application.ps1, Deploy-Application.exe, and AppDeployToolkitMain.ps1
	69000 - 69999: Recommended for user customized exit codes in Deploy-Application.ps1
	70000 - 79999: Recommended for user customized exit codes in AppDeployToolkitExtensions.ps1
.LINK
	http://psappdeploytoolkit.com
#>
    [CmdletBinding()]
Param (
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [string]$DeploymentType = 'Install',
    [Parameter(Mandatory = $false)]
    [ValidateSet('Interactive', 'Silent', 'NonInteractive')]
    [string]$DeployMode = 'Interactive',
    [Parameter(Mandatory = $false)]
    [switch]$AllowRebootPassThru = $false,
    [Parameter(Mandatory = $false)]
    [switch]$TerminalServerMode = $false,
    [Parameter(Mandatory = $false)]
    [switch]$DisableLogging = $false
)

try {
    ## Set the script execution policy for this process
    try {
        Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop'
    } catch {
    }

    ##*===============================================
    ## Variables: Install Titles (Only set here to override defaults set by the toolkit)
    ## [string]$installName = ''
    ## [string]$installTitle = ''

    ##* Do not modify section below
    #region DoNotModify

    ## Variables: Exit Code
    [int32]$mainExitCode = 0

    ## Variables: Script
    [string]$deployAppScriptFriendlyName = 'Deploy Application'
    [version]$deployAppScriptVersion = [version]'3.8.4'
    [string]$deployAppScriptDate = '26/01/2021'
    [hashtable]$deployAppScriptParameters = $psBoundParameters

    ## Variables: Environment
    if (Test-Path -LiteralPath 'variable:HostInvocation') {
        $InvocationInfo = $HostInvocation
    } else {
        $InvocationInfo = $MyInvocation
    }
    # $scriptDirectory is the root of the SoftwarePackageModule
    [string]$scriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent
    # Loads the config file and creates the variables
    # Goes two levels up from current directory. SoftwarePackageModule.x.y.z -> ps_modules -> Version of App to be packaged ($configurationFolder)
    $configurationFolder = $scriptDirectory | Split-Path | Split-Path
    if (Test-Path -Path "$configurationFolder\Deploy-Application.ps1.yaml") {
        Import-Module "$configurationFolder\ps_modules\powershell-yaml.*\powershell-yaml.psm1"

        $yaml = Get-Content -Raw -Path "$configurationFolder\Deploy-Application.ps1.yaml" -force | ConvertFrom-Yaml

        # For testing:
        Write-Host $yaml

    } else {
        throw "Config could not be loaded from [" + $configurationFolder + "] with the names [Deploy-Application.ps1.config], [deploy-application-config.json] or [deploy-config.yaml]"
    }

    # Defining Toolkitvariables
    [string]$appVendor = $yaml.appMetadata.appVendor
    [string]$appName = $yaml.appMetadata.appName
    [string]$appVersion = $yaml.appMetadata.appVersion
    [string]$appLang = $yaml.appMetadata.appLang
    [string]$appRevision = $yaml.yamlMetadata.yamlConfigRevision
    [string]$appArch = $yaml.appMetadata.appArch

    ## Dot source the required App Deploy Toolkit Functions
    Try {
        [string]$moduleAppDeployToolkitMain = "$scriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
        if (-not(Test-Path -LiteralPath $moduleAppDeployToolkitMain -PathType 'Leaf')) {
            Throw "Module does not exist at the specified location [$moduleAppDeployToolkitMain]."
        }
        if ($DisableLogging) {
            . $moduleAppDeployToolkitMain -DisableLogging
        } else {
            . $moduleAppDeployToolkitMain
        }
    } catch {
        if ($mainExitCode -eq 0) {
            [int32]$mainExitCode = 60008
        }
        Write-Error -Message "Module [$moduleAppDeployToolkitMain] failed to load: `n$( $_.Exception.Message )`n `n$( $_.InvocationInfo.PositionMessage )" -ErrorAction 'Continue'
        ## Exit the script, returning the exit code to SCCM
        if (Test-Path -LiteralPath 'variable:HostInvocation') {
            $script:ExitCode = $mainExitCode; Exit
        } else {
            exit $mainExitCode
        }
    }

    ## Readying paths for Files and SupportFiles folder
    [string]$dirFiles = Join-Path -Path $configurationFolder -ChildPath 'Files'
    [string]$dirSupportFiles = Join-Path -Path $configurationFolder -ChildPath 'SupportFiles'

    ## Variables: RegistryKey
    [string]$appRegFolderName = $yaml.appMetadata.appPackagePublisher + ' - ' + $yaml.appMetadata.appName + ' - ' + $yaml.appMetadata.appVersion
    [string]$appRegDisplayName = "[$( $yaml.appMetadata.appCategory )] " + $yaml.appMetadata.appVendor + ' ' + $yaml.appMetadata.appName + ' ' + $yaml.appMetadata.appVersion

    if ($yaml.appMetadata.appArch -eq 'x64') {
        [string]$appRegUninstallFolder = $regKeyApplications[0] + '\' + $appRegFolderName
    }
    else {
        [string]$appRegUninstallFolder = $regKeyApplications[1] + '\' + $appRegFolderName
    }

    ## Variables: App Environment
    ## [string]$installerLocation = "$envProgramFiles\$($yaml.appMetadata.appName)\$yaml.installerName"
    [string]$appVendorFolder = "$envProgramFiles\$( $yaml.appMetadata.appVendor )"
    [string]$appInstallFolder = "$envProgramFiles\$( $yaml.appMetadata.appVendor )\$( $yaml.appMetadata.appName )"

    # Gets the user profile path for all users
    [string[]]$ProfilePaths = Get-UserProfiles | Select-Object -ExpandProperty 'ProfilePath'

    #endregion
    ##* Do not modify section above
    ##*===============================================
    ##* END VARIABLE DECLARATION
    ##*===============================================

    # Check if script version matches by checking the Folder name of the installed package
    Write-Output $scriptDirectory
    if (-not($scriptDirectory -like "*SoftwarePackageModule.$( $yaml.softwarePackageModuleVersion )")) {
        throw "Version of config [*SoftwarePackageModule.$( $yaml.softwarePackageModuleVersion )] is not included in the module name [$scriptDirectory] while installing $( $yaml.appMetadata.appName ). Is the correct version of the SoftwarePackageModule installed and defined in the config?"
    }

    if ($deploymentType -ine 'Uninstall' -and $deploymentType -ine 'Repair') {
        ##*===============================================
        ##* PRE-INSTALLATION
        ##*===============================================
        [string]$installPhase = 'Pre-Installation'


        ## Show Welcome Message, close given Apps if required, allow up to X deferrals, verify there is enough disk space to complete the install, and persist the prompt
        if ([bool]($yaml.keys -eq "closeApps")) {

            if ($yaml.closeApps.count -gt 1) {
                [string]$closeApps = $yaml.closeApps -join ","
            } else {
                [string]$closeApps = $yaml.closeApps
            }

            Show-InstallationWelcome -AllowDefer -DeferTimes $yaml.maxUserDefer -CheckDiskSpace -PersistPrompt -CloseApps $closeApps -MinimizeWindows $false
        } else {
            Show-InstallationWelcome -AllowDefer -DeferTimes $yaml.maxUserDefer -CheckDiskSpace -PersistPrompt -MinimizeWindows $false
        }

        ## Show Progress Message (with the default message)
        Show-InstallationProgress -TopMost $false

        ## <Perform Pre-Installation tasks here>
        ## Creates and copies the file to all user profiles including default so new user will also have the file

        if ($yaml.installerName -notlike "*.exe" -and $yaml.installerName -like "*.msi") {
            if (-Not(Test-Path $appInstallFolder)) {
                New-Item -ItemType Directory -Path $appInstallFolder
            }
        }

        ##*===============================================
        ##* INSTALLATION
        ##*===============================================
        [string]$installPhase = 'Installation'

        ## <Perform Installation tasks here>
        if ($yaml.installerName -like "*.exe") {
            Execute-Process -Path $yaml.installerName -Parameters $yaml.installParameter
        } elseif($yaml.installerName -like "*.msi") {
            Execute-MSI -Action install -Path $yaml.installerName -Parameters $yaml.installParameter
        }elseif($yaml.installerName -eq "msiexec") {
                Execute-MSI -Action install -Parameters $yaml.installParameter
        } else {
            Write-Log -Message "Copying Files from [$dirFiles] to [$appInstallFolder]" -Severity 1 -Source $deployAppScriptFriendlyName
            Copy-Item -Path $dirFiles -Destination $appInstallFolder -Force -Recurse
        }

        ##*===============================================
        ##* POST-INSTALLATION
        ##*===============================================
        [string]$installPhase = 'Post-Installation'

        ## <Perform Post-Installation tasks here>

        if ([bool]($yaml.keys -eq "copy")) {
            foreach ($folder in $yaml.copy) {
                if([bool]($folder.step -eq "post-install")){
                    if($folder.source -like "*:\*" -or $folder.source -like "\\*\*"){
                        $srcpath = $folder.source
                        Write-Log -Message "Using absolut path [$srcpath]" -Severity 1 -Source $deployAppScriptFriendlyName

                    }else{
                        Write-Log -Message "Using relative path [$($folder.source)]" -Severity 1 -Source $deployAppScriptFriendlyName
                        $srcpath = "$dirSupportFiles\$($folder.source)"
                        Write-Log -Message "Got absolut path [$srcpath]" -Severity 1 -Source $deployAppScriptFriendlyName
                    }

                    if($folder.destination -eq "AllUserProfiles"){
                        Write-Log -Message "Destination User Profiles detected" -Severity 1 -Source $deployAppScriptFriendlyName

                        foreach ($ProfilePath in $ProfilePaths) {
                            Write-Log -Message "Copying Files from [$srcpath] to [$ProfilePath]" -Severity 1 -Source $deployAppScriptFriendlyName
                            New-Folder -Path "$ProfilePath\$($folder.source)"
                            Copy-Item -Path $srcpath -Destination "$ProfilePath\$($folder.source)" -Force -Recurse

                        }

                    }else{

                        Write-Log -Message "Copying Files from [$srcpath] to [$($folder.destination)]" -Severity 1 -Source $deployAppScriptFriendlyName
                        Copy-Item -Path $srcpath -Destination $folder.destination -Force -Recurse

                    }
                }
            }
        }

        if ([bool]($yaml.keys -eq "originalAppRegKey")) {
            foreach ($regKey in $yaml.originalAppRegKey) {
                if ($regKey.hide) {
                    $key = $regKey.path
                    Set-RegistryKey -Key $key -Name 'SystemComponent' -Type DWord -Value 1
                }
            }
        }

        ## Delete files if specified in config
        if ([bool]($yaml.deleteFilePathsAfterInstall)) {
            Write-Log -Message ("Deleting the following files according to configuration in Post-Install: " + $yaml.deleteFilePathsAfterInstall) -Severity 1 -Source $deployAppScriptFriendlyName
            foreach ($path in $yaml.deleteFilePathsAfterInstall) {
                Remove-Item -Recurse -Path $path
            }
        }

        if ([bool]($yaml.keys -eq "shortcut")) {
            if ([bool]($yaml.shortcut.startMenu)) {
                if ([bool]($yaml.shortcut.startMenu.startIn)) {
                    New-Shortcut -Path "$envCommonStartMenuPrograms\$($yaml.appMetadata.appName)`.lnk" -TargetPath $yaml.appExePath -IconLocation $yaml.displayIcon -Description $yaml.appMetadata.appName -WorkingDirectory $yaml.shortcut.startMenu.startIn
                } else {
                    New-Shortcut -Path "$envCommonStartMenuPrograms\$($yaml.appMetadata.appName)`.lnk" -TargetPath $yaml.appExePath -IconLocation $yaml.displayIcon -Description $yaml.appMetadata.appName -WorkingDirectory $appInstallFolder
                }
            }
            if ([bool]($yaml.shortcut.desktop)) {
                if ([bool]($yaml.shortcut.startMenu.startIn)) {
                    New-Shortcut -Path "C:\Users\Public\Desktop\$($yaml.appMetadata.appName)`.lnk" -TargetPath $yaml.appExePath -IconLocation $yaml.displayIcon -Description $yaml.appMetadata.appName -WorkingDirectory $yaml.shortcut.startMenu.startIn
                } else {
                    New-Shortcut -Path "C:\Users\Public\Desktop\$($yaml.appMetadata.appName)`.lnk" -TargetPath $yaml.appExePath -IconLocation $yaml.displayIcon -Description $yaml.appMetadata.appName -WorkingDirectory $appInstallFolder
                }
            }
        }


        ## Registry Keys for displaying in Windows under applications and unaable to modify or uninstall
        Set-RegistryKey -Key $appRegUninstallFolder -Name 'DisplayName' -Type 'String' -Value $appRegDisplayName
        Set-RegistryKey -Key $appRegUninstallFolder -Name 'DisplayVersion' -Type 'String' -Value $yaml.appMetadata.appVersion
        Set-RegistryKey -Key $appRegUninstallFolder -Name 'Publisher' -Type 'String' -Value $yaml.appMetadata.appPackagePublisher
        Set-RegistryKey -Key $appRegUninstallFolder -Name 'DisplayIcon' -Type 'String' -Value $yaml.displayIcon
        Set-RegistryKey -Key $appRegUninstallFolder -Name 'PackageGuid' -Type 'String' -Value $yaml.appMetadata.appRegPackageGuid

        # Firewall
        if ([bool]($yaml.keys -eq "firewall")) {
            foreach ($firewallConfig in $yaml.firewall) {
                foreach ($ruleProtocol in $firewallConfig.ruleProtocols) {
                    Write-Log -Message "Creating Firwall rule: $($firewallConfig.ruleName) - $ruleProtocol" -Severity 1 -Source $deployAppScriptFriendlyName
                    New-NetFirewallRule -DisplayName "$($firewallConfig.ruleName) - $ruleProtocol" -Direction $($firewallConfig.ruleDirection) -Program $($firewallConfig.ruleProgram) -Action $($firewallConfig.ruleAction) -Profile $($firewallConfig.ruleProfile)
                }
            }
        }

    } elseIf ($deploymentType -ieq 'Uninstall') {
        ##*===============================================
        ##* PRE-UNINSTALLATION
        ##*===============================================
        [string]$installPhase = 'Pre-Uninstallation'

        ## Show Welcome Message, close Internet Explorer with a 60 second countdown before automatically closing
        if ($yaml.closeApps) {
            if ($yaml.closeApps.count -gt 1) {
                [string]$closeApps = $yaml.closeApps -join ","
            } else {
                [string]$closeApps = $yaml.closeApps
            }

            Show-InstallationWelcome -CloseApps $closeApps -CloseAppsCountdown 60 -MinimizeWindows $false
        }
        else {
            Show-InstallationWelcome -MinimizeWindows $false
        }
        ## Show Progress Message (with the default message)
        Show-InstallationProgress -StatusMessage "Uninstalling $installTitle. Please Wait..." -TopMost $false

        ## <Perform Pre-Uninstallation tasks here>

        if ([bool]($yaml.keys -eq "copy")) {
            foreach ($folder in $yaml.copy) {
                if($folder.step -eq "pre-uninstall"){
                    if($folder.source -like "*:\*" -or $folder.source -like "\\*\*"){
                        $srcpath = $folder.source
                        Write-Log -Message "Using absolut path [$srcpath]" -Severity 1 -Source $deployAppScriptFriendlyName

                    }else{
                        Write-Log -Message "Using relative path [$($folder.source)]" -Severity 1 -Source $deployAppScriptFriendlyName
                        $srcpath = "$dirSupportFiles\$($folder.source)"
                        Write-Log -Message "Got absolut path [$srcpath]" -Severity 1 -Source $deployAppScriptFriendlyName
                    }

                    if($folder.destination -eq "AllUserProfiles"){
                        Write-Log -Message "Destination User Profiles detected" -Severity 1 -Source $deployAppScriptFriendlyName

                        foreach ($ProfilePath in $ProfilePaths) {
                            Write-Log -Message "Copying Files from [$srcpath] to [$ProfilePath]" -Severity 1 -Source $deployAppScriptFriendlyName
                            Copy-Item -Path $srcpath -Destination "$ProfilePath\$($folder.source)" -Force -Recurse

                        }

                        }else{

                            Write-Log -Message "Copying Files from [$srcpath] to [$($folder.destination)]" -Severity 1 -Source $deployAppScriptFriendlyName
                            Copy-Item -Path $srcpath -Destination $folder.destination -Force -Recurse

                    }
                }
            }
        }

        ##*===============================================
        ##* UNINSTALLATION
        ##*===============================================
        [string]$installPhase = 'Uninstallation'

        <## Handle Zero-Config MSI Uninstallations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Uninstall'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat
		}#>

        # <Perform Uninstallation tasks here>
        if ($yaml.uninstallerName -like "*.exe") {
            if (-Not(Test-Path $yaml.uninstallerName)) {
                # Get uninstaller by absolute path
                if (Test-Path "$dirFiles\$( $yaml.uninstallerName )") {
                    # Get uninstaller from Files/ directory
                    $yaml.uninstallerName = Join-Path -Path $dirFiles -ChildPath $yaml.uninstallerName
                } else {
                    throw "Can't find the uninstaller at " + $pwd + "\" + $yaml.uninstallerName
                }
            }
            Execute-Process -Path $yaml.uninstallerName -Parameters $yaml.uninstallParameter
        } elseif ($yaml.installerName -like "*.msi") {
            Execute-MSI -Action Uninstall -Path $yaml.uninstallerName -Parameters $yaml.uninstallParameter
        } else {
            Remove-Folder -Path $appInstallFolder

            if (-not(Get-ChildItem $appVendorFolder).count) {
                Remove-Folder -Path $appVendorFolder
            }

        }

        if ([bool]($yaml.additionalMSIUninstaller)) {
            Write-Log -Message "Uninstalling following MSI $($yaml.additionalMSIUninstaller)" -Severity 1 -Source $deployAppScriptFriendlyName

            foreach ($guid in $yaml.additionalMSIUninstaller) {
                Write-Log -Message "Uninstalling: $guid" -Severity 1 -Source $deployAppScriptFriendlyName

                $name = (Get-Package | Where-Object { $_.FastPackageReference -eq $guid }).name
                if ($null -eq $name) {
                    Write-Log -Message "Package not found: $guid" -Severity 1 -Source $deployAppScriptFriendlyName
                    Write-Log -Message "Using guid as name" -Severity 1 -Source $deployAppScriptFriendlyName
                    $name = $guid
                }

                Execute-MSI -Action Uninstall -Path $guid -Parameters "/Q /NORESTART"
            }
        }



        ##*===============================================
        ##* POST-UNINSTALLATION
        ##*===============================================
        [string]$installPhase = 'Post-Uninstallation'

        ## <Perform Post-Uninstallation tasks here>


        if ([bool]($yaml.deleteFilePathsOnUninstall)) {
            foreach ($path in $yaml.deleteFilePathsOnUninstall) {
                Remove-Item -Recurse -Path $path -Force
            }
        }


        Remove-RegistryKey -Key $appRegUninstallFolder
        Remove-Item -Path "$envCommonStartMenuPrograms\$($yaml.appMetadata.appName)`.lnk"

        if ([bool]($yaml.keys -eq "shortcut")) {
            if ([bool]($yaml.shortcut.startMenu)) {
                    Remove-Item -Path "C:\Users\Public\Desktop\$($yaml.appMetadata.appName)`.lnk"
            }
            if ([bool]($yaml.shortcut.desktop)) {
                    Remove-Item -Path "$envCommonStartMenuPrograms\$($yaml.appMetadata.appName)`.lnk"
            }

        }


        if ([bool]($yaml.firewall)) {
            foreach ($firewallConfig in $yaml.firewall) {
                foreach ($ruleProtocol in $firewallConfig.ruleProtocols) {
                    Write-Log -Message "Deleting Firwall rule: $($yaml.firewallRuleName) - $ruleProtocol"
                    Remove-NetFirewallRule -DisplayName "$($yaml.firewallRuleName) - $ruleProtocol"
                }
            }
        }

    } elseIf ($deploymentType -ieq 'Repair') {
        ##*===============================================
        ##* PRE-REPAIR
        ##*===============================================
        [string]$installPhase = 'Pre-Repair'

        ## Show Progress Message (with the default message)
        Show-InstallationProgress -TopMost $false

        ## <Perform Pre-Repair tasks here>

        ##*===============================================
        ##* REPAIR
        ##*===============================================
        [string]$installPhase = 'Repair'

        <## Handle Zero-Config MSI Repairs
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Repair'; Path = $defaultMsiFile; }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat
		}#>
        # <Perform Repair tasks here>

        ##*===============================================
        ##* POST-REPAIR
        ##*===============================================
        [string]$installPhase = 'Post-Repair'

        ## <Perform Post-Repair tasks here>


    }
    ##*===============================================
    ##* END SCRIPT BODY
    ##*===============================================

    ## Call the Exit-Script function to perform final cleanup operations
    Exit-Script -ExitCode $mainExitCode
} catch {
    [int32]$mainExitCode = 60001
    Write-Log -Message $_ -Severity 3 -Source $deployAppScriptFriendlyName
    Write-Log -Message "$( Resolve-Error )" -Severity 3 -Source $deployAppScriptFriendlyName
    Show-DialogBox -Text $_ -Icon 'Stop'
    Exit-Script -ExitCode $mainExitCode
}
