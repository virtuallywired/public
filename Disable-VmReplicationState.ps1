function Disable-VmReplicationState {

    <#
   .Synopsis
   Disables VM Replication State
   
   .DESCRIPTION
   Disables VM Replication State Requires Posh-SSH - Install-Module Posh-SSH  to Run on Powershell 7 Posh-SSH version 3.x or higher is required.
   
   .EXAMPLE
   Disable-VmReplicationState -vCenter "vc.virtuallywired.io" -VcCredentials $vccreds -VmName $vm -EsxiCredentials $esxicreds 
   
   .INPUTS
   vCenter and ESXi credentials must be Encrypted, VM names can be array of VMs.
   
   .OUTPUTS
   Output from this cmdlet (if any)
   
   .NOTES
   Must be connected to vCenter for this function to operate and vCenter and ESXi credentials must be Encrypted.
   
   .AUTHOR
   Nicholas Mangraviti - virtuallywired.io
   #>
   
    [CmdletBinding(DefaultParameterSetName = 'Parameter Set 1', 
        SupportsShouldProcess = $true, 
        PositionalBinding = $false,
        HelpUri = 'http://www.microsoft.com/',
        ConfirmImpact = 'Medium')]
    [Alias()]
    [OutputType([String])]
    Param 
    (
   
        #Specifies vCenter IP / URL
        [Parameter(Mandatory = $true,      
            ValueFromPipelineByPropertyName = $true, 
            ParameterSetName = 'Parameter Set by Properties')]
        [ValidateNotNull()]
        [string]
        $vCenter,
   
        #Specifies vCenter Credentials
        [Parameter(Mandatory = $true,      
            ValueFromPipelineByPropertyName = $true, 
            ParameterSetName = 'Parameter Set by Properties')]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        $VcCredentials,
  
        #Specifies ESXi root Credentials
        [Parameter(Mandatory = $true,      
            ValueFromPipelineByPropertyName = $true, 
            ParameterSetName = 'Parameter Set by Properties')]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        $EsxiCredentials,
  
        #Specifies VM Name
        [Parameter(Mandatory = $true,      
            ValueFromPipelineByPropertyName = $true, 
            ParameterSetName = 'Parameter Set by Properties')]
        [ValidateNotNull()]
        [array]
        $VmNames
    
    )
  
    If ($null -eq (Get-Module -Name Posh-SSH -ErrorAction SilentlyContinue)) {
      
        Import-Module "Posh-SSH" -Force:$true -WarningAction SilentlyContinue
      
    }
  
  
    ## Connecting to vCenter Server ##
  
    Write-Host "Connecting to vCenter Server: $($vCenter)"
    Start-Sleep -Seconds 1
    $server = Connect-VIServer -Server $vCenter -Credential $VcCredentials
  
    If ($server.IsConnected -eq $true) {
        Write-Host "Successfully Connected to $($server.Name)"
    }
    else {
  
        Write-Host "Failed to Connect to vCenter Server: $($vc)" -ForegroundColor Red
        Write-Host "--- Script Aborted! ---" -ForegroundColor Red
        Exit
  
    }
  
    $GetVM = Get-VM
  
    $VMs = $GetVM | Where-Object { $_.name -in $VmNames }
  
    $InvalidVMs = $vmnames | Where-Object { $_ -notin $GetVM.name }
  
    If ($InvalidVMs -gt "") {
  
        Foreach ($InvalidVM in $InvalidVMs) {
  
            Write-Host "Note, the following VM '$($InvalidVM)' was not found" -ForegroundColor Red
  
            Start-Sleep -Seconds 1
  
        }
    }
  
    Foreach ($VM in $VMs) {
  
        $VmHost = Get-VM $vm | Get-VMHost
  
        Write-Host "Enabling SSH on $($VmHost)"
  
        $sshpolicy = Get-VMHostService -VMHost $VmHost | Where-Object { $_.Key -eq "TSM-SSH" }
     
        If ($sshpolicy.Running -eq $false) {
  
            $result = Start-VMHostService $sshpolicy -Confirm:$false
  
        }
  
        $ssh = New-SSHSession -ComputerName $VmHost -Credential $EsxiCredentials -Acceptkey -WarningAction SilentlyContinue
  
        If ($ssh.Connected -eq $true) {
  
            Write-Host "Successfully Connected to '$($VmHost)'"
  
            Start-Sleep -Seconds 1
  
            [string]$vmID = ((Invoke-SSHCommand $ssh -Command "vim-cmd vmsvc/getallvms | grep $VM").output).substring(0, 7).trim()
  
            [String]$output = (Invoke-SSHCommand $ssh -Command "vim-cmd hbrsvc/vmreplica.getState $vmID").output
  
            If ($output -like "*The VM is configured for replication.*") {
  
                Write-host -ForegroundColor Yellow "$($VM) is configured for replication and will now be disabled."
  
                $DisableResult = (Invoke-SSHCommand $ssh -Command "vim-cmd hbrsvc/vmreplica.disable $vmID").output # << Disable Command
  
                Write-Host "Disconnecting from $($VMHost)"
  
                $Session = Get-SSHSession | Remove-SSHSession
  
                Write-Host "Disabling SSH on $($VmHost)"
  
                $sshpolicy = Get-VMHostService -VMHost $VmHost | Where-Object { $_.Key -eq "TSM-SSH" }
     
                If ($sshpolicy.Running -eq $true) {
  
                    $result = Stop-VMHostService $sshpolicy -Confirm:$false
  
                }
            }
  
            else { 
                    
                Write-host -ForegroundColor Green "$($vm) is NOT configured for replication, exiting." 
  
                Write-Host "Disconnecting from $($VMHost)"
       
                $Session = Get-SSHSession | Remove-SSHSession
  
                Write-Host "Disabling SSH on $($VmHost)"
  
                $sshpolicy = Get-VMHostService -VMHost $VmHost | Where-Object { $_.Key -eq "TSM-SSH" }
     
                If ($sshpolicy.Running -eq $true) {
  
                    $result = Stop-VMHostService $sshpolicy -Confirm:$false
  
                }
  
            }
  
        }
   
    }
  
    
    Write-Host "Disconnecting vCenter $($vCenter)"
    Disconnect-VIServer * -Confirm:$false
  
  
}
