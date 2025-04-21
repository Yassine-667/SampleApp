# Parameters - adjust these as needed
$siteName = "SampleApp"
$appPoolName = "SampleAppPool"
$physicalPath = "C:\inetpub\wwwroot\SampleApp"
$port = 8080
$publishFolder = ".\publish"

# Ensure script is run as administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "You need to run this script as an Administrator."
    exit
}

# Import the WebAdministration module
Import-Module WebAdministration

# Publish the application (if not already done)
Write-Host "Publishing application..."
dotnet publish --configuration Release --output $publishFolder

# Stop the site if it exists
if (Test-Path "IIS:\Sites\$siteName") {
    Write-Host "Stopping existing site..."
    Stop-Website -Name $siteName
}

# Create the directory if it doesn't exist
if (-not (Test-Path $physicalPath)) {
    Write-Host "Creating directory $physicalPath..."
    New-Item -ItemType Directory -Path $physicalPath -Force
}

# Delete existing content in the physical path
Write-Host "Clearing destination directory..."
Get-ChildItem -Path $physicalPath -Recurse | Remove-Item -Recurse -Force

# Copy published files to the physical path
Write-Host "Copying files to $physicalPath..."
Copy-Item -Path "$publishFolder\*" -Destination $physicalPath -Recurse -Force

# Set appropriate permissions
Write-Host "Setting permissions..."
$acl = Get-Acl $physicalPath
$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("IIS_IUSRS", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.SetAccessRule($accessRule)
Set-Acl $physicalPath $acl

# Create or update app pool
if (Test-Path "IIS:\AppPools\$appPoolName") {
    Write-Host "App pool $appPoolName exists, reconfiguring..."
    Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name managedRuntimeVersion -Value ""
    Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name managedPipelineMode -Value Integrated
    Restart-WebAppPool -Name $appPoolName
} else {
    Write-Host "Creating app pool $appPoolName..."
    New-WebAppPool -Name $appPoolName
    Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name managedRuntimeVersion -Value ""
    Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name managedPipelineMode -Value Integrated
}

# Create or update website
if (Test-Path "IIS:\Sites\$siteName") {
    Write-Host "Site $siteName exists, updating..."
    Set-ItemProperty "IIS:\Sites\$siteName" -Name physicalPath -Value $physicalPath
    Set-ItemProperty "IIS:\Sites\$siteName" -Name applicationPool -Value $appPoolName
} else {
    Write-Host "Creating site $siteName..."
    New-Website -Name $siteName -PhysicalPath $physicalPath -ApplicationPool $appPoolName -Port $port -Force
}

# Start the website
Write-Host "Starting website..."
Start-Website -Name $siteName

Write-Host "Deployment complete! Your site should be available at http://localhost:$port"