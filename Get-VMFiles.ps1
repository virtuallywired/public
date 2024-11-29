<#
.SYNOPSIS
    Downloads virtual machine screenshots, logs, or other files from the datastore to a local machine.

.DESCRIPTION
    This function connects to a vCenter server, locates the specified virtual machine, 
    and downloads files of the specified type from the VM's directory on the datastore 
    to a specified local directory.

.PARAMETER vCenter
    The URL or IP address of the vCenter server.

.PARAMETER VMName
    The name of the virtual machine from which files are to be downloaded.

.PARAMETER ItemType
    The file extension (e.g., LOG, PNG) of the files to be downloaded.

.PARAMETER LocalPath
    The local directory path where the files will be saved.

.PARAMETER Credential
    The credentials to connect to the vCenter server. Use `Get-Credential` to supply the credentials.

.EXAMPLE
    Get-VMFiles -vCenter "vc.virtuallywired.io" -VMName "win2016" -ItemType "PNG" -LocalPath "C:\VM_LOGS" -Credential (Get-Credential)

.NOTES
    Version: 1.1
    Tested on vSphere 6.7 Update 3, vSAN 6.7 Update 3, and VMFS 6.
    Author: Nicholas Mangraviti #VirtuallyWired
    Blog URL: virtuallywired.io
#>
function Get-VMFiles {
    param (
        [Parameter(Mandatory = $true)]
        [string]$vCenter,

        [Parameter(Mandatory = $true)]
        [string]$VMName,

        [Parameter(Mandatory = $true)]
        [string]$ItemType,

        [Parameter(Mandatory = $true)]
        [string]$LocalPath,

        [Parameter(Mandatory = $true)]
        [PSCredential]$Credential
    )

    try {
        # Connect to vCenter
        Write-Host "Connecting to vCenter: $vCenter" -ForegroundColor Cyan
        $VC = Connect-VIServer -Server $vCenter -Credential $Credential

        # Get the VM object
        Write-Host "Locating VM: $VMName" -ForegroundColor Cyan
        $VM = Get-VM -Name $VMName

        # Create target local directory
        $Target = New-Item -ItemType Directory -Force -Path "$LocalPath\$($VM.Name)"

        # Extract VM path details
        $vmpath = [regex]::Matches(([regex]::Replace(($VM.ExtensionData.Config.Files.LogDirectory), "\s", "")), '\[(.+)\](.+)\/').Groups.Value
        $Datastore = $VM | Get-Datastore -Name $($vmpath[1])

        # Map datastore as a PSDrive
        if ((Get-PSDrive).Name -eq "DSdrive") {
            Remove-PSDrive -Name DSdrive -Confirm:$false -Force | Out-Null
        }
        New-PSDrive -Location $Datastore -Name DSdrive -PSProvider VimDatastore -Root "\" | Out-Null

        # Change location to VM's datastore directory
        Set-Location "DSdrive:\$($vmpath[2])\"

        # Download files
        if (Get-ChildItem "*.$ItemType") {
            Write-Host "'$ItemType' file(s) found, preparing to download..." -ForegroundColor Green
            Copy-DatastoreItem -Item "*.$ItemType" -Destination $Target
            Write-Host "File(s) downloaded successfully to $($Target.FullName)" -ForegroundColor Green
        } else {
            Write-Host "No '$ItemType' file(s) found." -ForegroundColor Red
        }

        # Reset location
        Set-Location C:

        # Cleanup PSDrive
        if (Get-PSDrive -Name DSdrive) {
            Remove-PSDrive -Name DSdrive -Confirm:$false -Force | Out-Null
        }
    } catch {
        Write-Host "An error occurred: $_" -ForegroundColor Red
    } finally {
        # Disconnect from vCenter
        Write-Host "Disconnecting from vCenter..." -ForegroundColor Cyan
        Disconnect-VIServer -Server $VC -Force -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    }
}
