## Thank you, Digressive/MDT-Setup for this awesome MDT setup script!
## Source: https://github.com/Digressive/MDT-Setup
$mdt_setup_script = Get-ChildItem -Path "MDT-Setup" -Include "MDT-Setup.ps1" -File -Recurse -ErrorAction SilentlyContinue

if ($mdt_setup_script) {
    Write-Host "MDT-Setup script found. Running the script..."
    Powershell.exe -ExecutionPolicy Bypass -File "$($mdt_setup_script.fullname)"
}
else {
    Write-Host "MDT-Setup script not found. Exiting..."
    exit 1
}

## NOTE: I have tested this successfully on Windows Server 2022 running in a Proxmox VM (currently adding changes into this script)

## Configurations made:
## 1. Monitoring service enabled.
## 2. VirtIO storage drivers for win10 added to WinPE drivers folder in deployment share.
## TODO:
## 3. VirtIO Windows drivers installation via application/msi?

## Import mdt module:
$mdt_module = Get-ChildItem -Path "C:\Program Files\Microsoft Deployment Toolkit\bin" -Filter "MicrosoftDeploymentToolkit.psd1" -File -ErrorAction SilentlyContinue
if (-not $mdt_module) {
    Write-Host "MDT module file not found, exiting."
    exit 1
}

Write-Host "Found $($mdt_module.fullname), importing..."
ipmo $($mdt_module.fullname)




# default deployment share name
$deployshare = "C:\deployshare"
New-PSDrive -Name "DS001" -PSProvider MDTProvider -Root $deployshare -Description "MDT Deployment Share" -Verbose

## Enable MDT Monitor Service
Enable-MDTMonitorService -EventPort 9800 -DataPort 9801 -Verbose
Set-ItemProperty -path DS001: -name MonitorHost -value $env:COMPUTERNAME

## find virtio drivers disk by targeting virtio msi
## Check for virtio 64-bit Windows driver installer MSI file by cycling through base of connected drives.
$drives = Get-PSDrive -PSProvider FileSystem
foreach ($drive in $drives) {
    $file = Get-ChildItem -Path $drive.Root -Filter "virtio-win-gt-x64.msi" -File -ErrorAction SilentlyContinue
    # If/once virtio msi is found - attempt to install silently and discontinue the searching of drives.
    if ($file) {

        ## VirtIO Win10 storage drivers path:
        $w10_folder = Get-Item -Path "$($drive.root)amd64\w10" -ErrorAction SilentlyContinue
        if (-not $w10_folder) {
            Write-Host "amd64/w10 folder not found in $($drive.root)" -Foregroundcolor yellow
            Read-Host "Press enter to continue"
        }
        else {

            ## get model name for folder:
            # $modelname = Get-Ciminstance -class win32_computersystem | select -exp model
            # $makename = Get-Ciminstance -class win32_computersystem | select -exp manufacturer

            Write-Host "Creating VirtIO driver folder in Out-of-box drivers\WinPE folder."
            ## create virtio driver folder:
            New-Item -Path "DS001:\Out-of-box drivers\$makename" -ItemType Directory
            New-Item -Path "DS001:\Out-of-box drivers\$makename\$modelname" -ItemType Directory

            Write-Host "Importing VirtIO drivers to deployment share.."
            ## Import virtio drivers to MDT:
            Import-MDTDriver -Path "DS001:\Out-of-box drivers\$makename\$modelname" -SourcePath $w10_folder.FullName -Verbose

            New-Item -Path "DS001:\Out-of-box drivers\WinPE\VirtIO" -ItemType Directory


            ## Get ALL w10 amd64 drivers from virtio iso and import into make/model folder for injection
            Import-MDTDriver -Path "DS001:\Out-of-box drivers\WinPE\VirtIO" -SourcePath $w10_folder.FullName -Verbose

            $folders = Get-ChildItem -Path $drive.root -Include 'amd64' -Directory -Recurse | ? { $_.Parent.name -eq 'w10' }

            $folders | % {
                Import-MDTDriver -Path "DS001:\Out-of-box drivers\$makename\$modelname" -SourcePath $_.fullname -verbose
            }


        }
        break
    }
}

## update the deployment share:
Update-MDTDeploymentShare -Path "DS001:" -Verbose


