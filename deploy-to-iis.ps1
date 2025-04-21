# Parameters - adjust these as needed
$siteName = "SampleApp"
$appPoolName = "SampleAppPool"
$physicalPath = "C:\inetpub\wwwroot\SampleApp"
$port = 8080
$publishFolder = ".\publish"
$logsPath = "$physicalPath\logs"
$aspNetCoreModuleInstalled = $false

# Ensure script is run as administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "You need to run this script as an Administrator."
    exit
}

# Import the WebAdministration module
Import-Module WebAdministration

# Check if ASP.NET Core Module is installed
$aspNetCoreModuleInstalled = (Get-WindowsOptionalFeature -Online -FeatureName IIS-ASPNET45).State -eq "Enabled"
if (-not $aspNetCoreModuleInstalled) {
    Write-Warning "ASP.NET Core Module V2 might not be installed. Please ensure you have the .NET Core Hosting Bundle installed."
    Write-Warning "You can download it from: https://dotnet.microsoft.com/download/dotnet/thank-you/runtime-aspnetcore-latest-windows-hosting-bundle-installer"
    
    $installHostingBundle = Read-Host "Do you want to continue anyway? (Y/N)"
    if ($installHostingBundle -ne "Y") {
        exit
    }
}

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

# Create logs directory
if (-not (Test-Path $logsPath)) {
    Write-Host "Creating logs directory..."
    New-Item -ItemType Directory -Path $logsPath -Force
}

# Delete existing content in the physical path
Write-Host "Clearing destination directory..."
Get-ChildItem -Path $physicalPath -Recurse -Exclude "logs" | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# Copy published files to the physical path
Write-Host "Copying files to $physicalPath..."
Copy-Item -Path "$publishFolder\*" -Destination $physicalPath -Recurse -Force

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

# Check for URL reservation and set if needed
$urlacl = "http://+:$port/"
$existingUrlAcl = & netsh http show urlacl url=$urlacl
if ($existingUrlAcl -notmatch "URL reservation successfully") {
    Write-Host "Setting URL ACL for port $port..."
    $networkService = "NT AUTHORITY\NETWORK SERVICE"
    & netsh http add urlacl url=$urlacl user="$networkService" listen=yes
}

# Start the website
Write-Host "Starting website..."
Start-Website -Name $siteName

Write-Host "Deployment complete! Your site should be available at http://localhost:$port"
Write-Host "You can also access the Swagger UI at http://localhost:$port/swagger"
Write-Host "To verify the API is working, try: http://localhost:$port/ping"

# Final checks
Write-Host "`nVerifying ASP.NET Core Module status:"
$modules = & C:\Windows\System32\inetsrv\appcmd.exe list modules /app.name:"$siteName/" | findstr AspNetCore
if ($modules) {
    Write-Host "ASP.NET Core Module is loaded correctly." -ForegroundColor Green
} else {
    Write-Host "WARNING: ASP.NET Core Module may not be loaded correctly." -ForegroundColor Yellow
    Write-Host "Make sure you have installed the .NET Core Hosting Bundle from:"
    Write-Host "https://dotnet.microsoft.com/download/dotnet/thank-you/runtime-aspnetcore-latest-windows-hosting-bundle-installer" -ForegroundColor Cyan
}