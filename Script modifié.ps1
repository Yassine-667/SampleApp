# This script needs administrators rights
# Check if ASP.NET Core Module is installed
# Create or update web.config

# Parameters - adjust these as needed
$siteName = "Sample.NET-3"
$appPoolName = "SampleNET3Pool"
$physicalPath = "C:\inetpub\wwwroot\Sample.NET-3"
$port = 9090
$publishFolder = ".\publish"
$logsPath = "$physicalPath\logs"

# Import the WebAdministration module
Import-Module WebAdministration

# Publish the application (if not already done)
dotnet publish "Sample.NET-3.csproj" --configuration Release --output $publishFolder

# Create the directory if it doesn't exist
if (-not (Test-Path $physicalPath)) {
    Write-Host "Creating directory $physicalPath..."
    New-Item -ItemType Directory -Path $physicalPath -Force
}

# Create logs directory
if (-not (Test-Path $logsPath)) {
    Write-Host "Creating logs directory..."
    New-Item -ItemType Directory -Path $logsPath -Force
}

# Stop the site if it exists
if (Test-Path "IIS:\Sites\$siteName") {
    Write-Host "Stopping existing site..."
    Stop-Website -Name $siteName
}

# Delete existing content in the physical path
Write-Host "Clearing destination directory..."
Get-ChildItem -Path $physicalPath -Recurse -Exclude "logs" | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# Copy published files to the physical path
Write-Host "Copying files to $physicalPath..."
Copy-Item -Path "$publishFolder\*" -Destination $physicalPath -Recurse -Force

# Update web.config with correct DLL name
$webConfigPath = "$physicalPath\web.config"
if (Test-Path $webConfigPath) {
    Write-Host "Updating web.config..."
    $webConfig = Get-Content $webConfigPath -Raw
    $webConfig = $webConfig -replace '\\.\[ACTUAL-DLL-NAME\].dll', '\Sample.NET-3.dll'
    Set-Content $webConfigPath $webConfig
}

# Set appropriate permissions
Write-Host "Setting permissions..."
$acl = Get-Acl $physicalPath
$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("IIS_IUSRS", "ReadAndExecute, Write", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.SetAccessRule($accessRule)
Set-Acl $physicalPath $acl

# Set additional permissions on logs directory
$logsAcl = Get-Acl $logsPath
$logsAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("IIS_IUSRS", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$logsAcl.SetAccessRule($logsAccessRule)
Set-Acl $logsPath $logsAcl

# Create or update app pool
if (Test-Path "IIS:\AppPools\$appPoolName") {
    Write-Host "App pool $appPoolName exists, reconfiguring..."
    Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name managedRuntimeVersion -Value ""
    Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name managedPipelineMode -Value Integrated
    Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name "processModel.identityType" -Value ApplicationPoolIdentity
    Restart-WebAppPool -Name $appPoolName
} else {
    Write-Host "Creating app pool $appPoolName..."
    New-WebAppPool -Name $appPoolName
    Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name managedRuntimeVersion -Value ""
    Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name managedPipelineMode -Value Integrated
    Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name "processModel.identityType" -Value ApplicationPoolIdentity
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
Write-Host "You can also access the Swagger UI at http://localhost:$port/swagger"
Write-Host "To verify the API is working, try: http://localhost:$port/ping"