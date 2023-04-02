# Site configuration
$SiteCode = "TPH" # Site code 
$ProviderMachineName = "ewo.swisstph.ch" # SMS Provider machine name

# Customizations
$initParams = @{}
#$initParams.Add("Verbose", $true) # Uncomment this line to enable verbose logging
#$initParams.Add("ErrorAction", "Stop") # Uncomment this line to stop the script on any errors

# Do not change anything below this line

# Import the ConfigurationManager.psd1 module 
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}

# Connect to the site's drive if it is not already present
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}
$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
Set-Location $dir
. .\Set-CMImplicitUninstall.ps1

$localPackagePath = (get-childitem -Directory)[0].Fullname
Write-Host "Importing from $localPackagePath"

# Set the current location to be the site code.
Set-Location "$($SiteCode):\" @initParams

# Loads the yaml config file and creates the variables
if (Test-Path -Path "$localPackagePath\Deploy-Application.ps1.yaml") {
    Import-Module "$localPackagePath\ps_modules\powershell-yaml.*\powershell-yaml.psm1"

    $yaml = Get-Content -Raw -Path "$localPackagePath\Deploy-Application.ps1.yaml" -force | ConvertFrom-Yaml

    # For testing:
    Write-Host $yaml

} else {
    throw "Config could not be loaded from [" + $configuratilocalPackagePathonFolder + "] with the name [Deploy-Application.ps1.yaml]"
}

# Defining Toolkitvariables
[string]$appVendor = $yaml.appMetadata.appVendor
[string]$appName = $yaml.appMetadata.appName
[string]$appVersion = $yaml.appMetadata.appVersion
[string]$appLang = $yaml.appMetadata.appLang
[string]$appRevision = $yaml.yamlMetadata.yamlConfigRevision
[string]$appArch = $yaml.appMetadata.appArch

$sccmPSRepo = "\\lucapa.swisstph.ch\SCCM-Repo\PS_Repository\$appVendor\$appName\$appVersion"

[string]$appRegFolderName = $yaml.appMetadata.appCategory + ' - ' + $yaml.appMetadata.appName + ' - ' + $yaml.appMetadata.appVersion 
[string]$appNV = $yaml.appMetadata.appName + ' ' + $yaml.appMetadata.appVersion 

# Switch from PS TPH:\ to C:\ Drive 


$existingApp = Get-CMApplication -name $appNV

Set-Location C:

if(-not(Test-Path $sccmPSRepo) -or -not $existingApp){
    New-Item -Path $sccmPSRepo -ItemType Directory -Force
    Remove-Item "$sccmPSRepo\*" -Recurse -Force
    Copy-Item -Path "$localPackagePath\*" -Destination $sccmPSRepo -Recurse
}else{
    Write-host "Warning: $sccmPSRepo already exists" -ForegroundColor Yellow
    Write-host "Warning: Removing files in $sccmPSRepo" -ForegroundColor Yellow
    Remove-Item "$sccmPSRepo\*" -Recurse -Force
    Write-host "Uploading new files to $sccmPSRepo"
    Copy-Item -Path "$localPackagePath\*" -Destination $sccmPSRepo -Recurse

    Write-host "Updated Content for deployment type $appNV"

    Set-Location TPH:
    Update-CMDistributionPoint -ApplicationName $appNV -DeploymentTypeName $appNV

    $filesExisted = $true
}

Set-Location TPH:

$date = get-date -Format "dd.MM.yyyy HH:mm:ss"

$comment = 'Created with PowerShell script "Create-CMApplicationFromConfig" at ' + $date ## needed in Config

# Get ico file
$iconname = (get-childitem "$localPackagePath\Files\" | where {$_.name -like "*.ico"}).name

if($iconname.count -gt 1){
    $iconname = $iconname[0]
    Write-Host "Warning: more than one ICON found. Selected first" -ForegroundColor Yellow
}elseif($iconname.count -eq 0){
    Throw 'Error: no icon found in $localPackagePath\Files\'
}

$icon = "$localPackagePath\Files\$iconname" #only ico



# Defining registrypath variables based on app architecture
if($yaml.appMetadata.appArch -eq 'x64'){
    [string]$appRegUninstallFolder = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' + '\' + $appRegFolderName
}else{
    [string]$appRegUninstallFolder = 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' + '\' + $appRegFolderName
}

if(-not $existingApp){
    $newApp = New-CMApplication -name $appNV -Description $comment -Publisher $yaml.appMetadata.appVendor -SoftwareVersion $yaml.appMetadata.appVersion -IconLocationFile $icon -OptionalReference $yaml.appMetadata.appDownloadLink -LocalizedDescription $yaml.appMetadata.appSccmDescription -UserDocumentation $yaml.appMetadata.appSccmUserDocumentationLink
    $newApp | Set-CMapplication -AddAppCategory (Get-CMCategory -name "Deployable")

    # Moves the newly created application to the test folder
    Move-CMobject -FolderPath 'TPH:\Application\!Test' -InputObject $newApp
}


# Detection Method to check for custom app reg key (which is diplayed and made by the deployment script)
$hive = 'LocalMachine'
# $keyname = 'path of the key2'
$valuename = 'DisplayVersion'
# $value = 'value2'
$clause1 = New-CMDetectionClauseRegistryKeyValue -Hive $hive -KeyName $appRegUninstallFolder -ValueName $valuename -Value -ExpectedValue $yaml.appMetadata.appVersion -ExpressionOperator IsEquals -PropertyType String

# Check for Version number on file (usually exe)
# add version to keyname in the deploy script. Otherwise only one reg key per app (two apps with diffrent version will only show the newer version)
$path = [System.IO.Path]::GetDirectoryName($yaml.appExePath)
$filename = [System.IO.Path]::GetFileName($yaml.appExePath)
# $value = '1.0.234'
$clauseFile = New-CMDetectionClauseFile -Path $path -FileName $filename -Value -ExpectedValue $yaml.appMetadata.appVersion -PropertyType Version -ExpressionOperator IsEquals

# Defining the command to install this application (Deployment Type -> Programs)
$install = "ps_modules\SoftwarePackageModule.$($yaml.softwarePackageModuleVersion)\Deploy-Application.exe"
$uninstall = "ps_modules\SoftwarePackageModule.$($yaml.softwarePackageModuleVersion)\Deploy-Application.exe Uninstall"

if($yaml.installerName -like "*.exe" -or $yaml.installerName -like "*.msi"){
    # Registry check for original app reg key (which should be hidden) not applicable for filecopy
    $hive = 'LocalMachine'
    # $keyname = 'path of the key'

    #if($yaml.originalAppRegKey -like "*,*"){
    #    $originalAppRegKey = $yaml.originalAppRegKey.split(",")[0]
    #}

    foreach($obj in $yaml.originalAppRegKey){
        if($obj.main -eq $true){
            $originalAppRegKey = $obj.path
        }
    }

    $originalAppRegKey = $originalAppRegKey.Substring($originalAppRegKey.IndexOf("\")+1,$originalAppRegKey.Length - $originalAppRegKey.IndexOf("\") -1)
    $valuename = 'DisplayVersion'
    # $value = 'value'
    $clause2 = New-CMDetectionClauseRegistryKeyValue -Hive $hive -KeyName $originalAppRegKey -ValueName $valuename -Value -ExpectedValue $appVersion -ExpressionOperator IsEquals -PropertyType String

    if($existingApp){
        # Update script deployment type
        Set-CMScriptDeploymentType -Application $existingApp -DeploymentTypeName $appNV -ContentLocation $sccmPSRepo -InstallCommand $install -UninstallCommand $uninstall -AddDetectionClause $clause1,$clause2,$clauseFile -InstallationBehaviorType 'InstallForSystem' -LogonRequirementType 'OnlyWhenUserLoggedOn' -RequireUserInteraction
    }else{
        # Create new script deployment type
        Add-CMScriptDeploymentType -ApplicationName $appNV -DeploymentTypeName $appNV -ContentLocation $sccmPSRepo -InstallCommand $install -UninstallCommand $uninstall -AddDetectionClause $clause1,$clause2,$clauseFile -InstallationBehaviorType 'InstallForSystem' -LogonRequirementType 'OnlyWhenUserLoggedOn' -RequireUserInteraction
    }
}else{
    if($existingApp){
        # Update script deployment type
        Set-CMScriptDeploymentType -ApplicationName $existingApp -DeploymentTypeName $appNV -ContentLocation $sccmPSRepo -InstallCommand $install -UninstallCommand $uninstall -AddDetectionClause $clause1,$clauseFile -InstallationBehaviorType 'InstallForSystem' -LogonRequirementType 'OnlyWhenUserLoggedOn' -RequireUserInteraction
    }else{
        # If file copy doesn't create detection method for original app registry key
        Add-CMScriptDeploymentType -ApplicationName $appNV -DeploymentTypeName $appNV -ContentLocation $sccmPSRepo -InstallCommand $install -UninstallCommand $uninstall -AddDetectionClause $clause1,$clauseFile -InstallationBehaviorType 'InstallForSystem' -LogonRequirementType 'OnlyWhenUserLoggedOn' -RequireUserInteraction
    }
}

$existingCollection = Get-CMCollection -Name $appNV

if(-not $existingCollection){
    ## create collection
    $newCollection = New-CMDeviceCollection -Name $appNV -LimitingCollectionName 'All Systems' -Comment $comment
    # Move collection to test folder
    Move-CMobject -FolderPath 'TPH:\DeviceCollection\Testing' -InputObject $newCollection

    ## deploy application to collection
    New-CMApplicationDeployment -Name $appNV -Collection $newCollection -DeployAction Install -DeployPurpose Required -DistributeContent -DistributionPointGroupName 'All'
}else{
    Set-CMApplicationDeployment -Name $appNV -Collection $existingCollection -DeployAction Install -DeployPurpose Required -DistributeContent -DistributionPointGroupName 'All'
}

Set-CMImplicitUninstall -name $appNV -FlagValue true -RemoteMachine $ProviderMachineName

$Server = 'TPH-X21002'
## Add Testing Device to Collection
Add-CMDeviceCollectionDirectMembershipRule -CollectionName $appNV -ResourceID (Get-CMDevice -Name $Server).ResourceID 


#App Deployment Evaluation Cycle
Invoke-WMIMethod -ComputerName $Server -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule '{00000000-0000-0000-0000-000000000121}'
Invoke-WMIMethod -ComputerName $Server -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule '{00000000-0000-0000-0000-000000000021}'

# To do
## Supersedence

## Deployment Types -> User Experience (done)
#### Allow users to view and interact with the progam installation

## -------------------------------------DO MANUALLY --------------------------------
## Deployments (currently not possible - no parameter for cmdlet) 
#### When a resource is no longer a member of the collection, uninstall this application



