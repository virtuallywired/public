# This Script Finds Downloads Virtual Machine Screenshots, Logs or any other files from the Datastore VM directory to your local machine.
# Version: 1.0
# Tested on vSphere 6.7 Update 3, vSAN 6.7 Update 3 and VMFS 6.
# Script Author: Nicholas Mangraviti #VirtuallyWired
# Blog URL: virtuallywired.io
# Usage: Just the vCenter URL or IP, VM Name, Item Type, eg. LOG or PNG for Screenshots, specify the local path to download the file to.

$vCenter = "vc.virtuallywired.io"
$Creds = Get-Credential # Prompt for vCenter Credentials

$VM = "win2016"
$ItemType = "PNG" # This is the Extension of the file/s you want to download, eg. log, png
$LocalPath = "C:\VM_LOGS" #LocalPath of location to Download files to

## Don't Edit Below This Line ##

$VC = Connect-VIServer -Server $vCenter -Credential $Creds

$VM = Get-VM -Name "$VM"
$Target = New-Item -ItemType Directory -Force -Path "$($LocalPath)\$($VM.Name)"

$vmpath = [regex]::Matches(([regex]::Replace(($VM.ExtensionData.Config.Files.LogDirectory), "\s", "")), '\[(.+)\](.+)\/').Groups.Value

$Datastore = $VM | Get-Datastore -Name $($vmpath[1])

If ((Get-PSDrive).Name -eq "DSdrive") {

   Remove-PSDrive -Name DSdrive -Confirm:$false -Force | Out-Null
  
}

New-PSDrive -Location $Datastore -Name DSdrive -PSProvider VimDatastore -Root "\" | Out-Null

Set-Location "DSdrive:\$($vmpath[2])\"

If (Get-ChildItem "*.$($ItemType)") {

   Write-Host -ForegroundColor Green "'$($ItemType)' File/s Found, Preparing To Download."
   Copy-DatastoreItem -Item "*.$($ItemType)" -Destination $Target
   Write-Host -ForegroundColor Green "File/s Downloaded, Check Directory > $($Target.FullName)"
}
else {
   Write-Host -ForegroundColor Red "'$($ItemType)' File/s Not Found."
}

Set-Location C:

If (Get-PSDrive -Name DSdrive) {

   Remove-PSDrive -Name DSdrive -Confirm:$false -Force | Out-Null

}

Disconnect-VIServer -Server $VC -Force -Confirm:$false -ErrorAction SilentlyContinue 
