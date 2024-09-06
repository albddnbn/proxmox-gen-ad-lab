## Thank you, Digressive/MDT-Setup for this awesome MDT setup script!
## Source: https://github.com/Digressive/MDT-Setup
$MDT_SETUP_GITHUB_URL = "https://github.com/albddnbn/MDT-Setup/archive/refs/heads/main.zip"

# Download the MDT-Setup repository
Invoke-WebRequest -Uri $MDT_SETUP_GITHUB_URL -OutFile "MDT-Setup.zip"

Expand-Archive ./MDT-Setup.zip

$mdt_setup_script = Get-ChildItem -Path "MDT-Setup" -Include "MDT-Setup.ps1" -File -Recurse -ErrorAction SilentlyContinue

if ($mdt_setup_script) {
    Write-Host "MDT-Setup script found. Running the script..."
    Powershell.exe -ExecutionPolicy Bypass -File "$($mdt_setup_script.fullname)"
}
else {
    Write-Host "MDT-Setup script not found. Exiting..."
}



