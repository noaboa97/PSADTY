# Remove ps_modules folder
Remove-Item ".\ps_modules" -Recurse

# Install the packages declared in ./packages.config
nuget install packages.config -OutputDirectory "./ps_modules"

# Execute the installer. Fails if there are multiple verisons installed in ps_modules
# .\ps_modules\SoftwarePackageModule.*\Deploy-Application.exe $args