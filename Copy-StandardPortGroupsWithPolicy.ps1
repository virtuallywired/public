<#
.EXAMPLE
Copy standard vSwitch port groups and their policies from one ESXi host to another,
excluding the Management Network.

Copy-StandardPortGroupsWithPolicy `
    -vCenterServer "vcenter.example.local" `
    -SourceHostName "esxi01.example.local" `
    -DestinationHostName "esxi02.example.local" `
    -ExcludePortGroups "Management Network"

.SYNOPSIS
Copies standard vSwitch port groups and their policies between ESXi hosts.

.DESCRIPTION
Connects to vCenter and copies standard (non-distributed) port groups from a source
ESXi host to a destination ESXi host. Missing vSwitches are created automatically.

Copies VLAN ID, security policy, NIC teaming/failover, and traffic shaping.
Does not copy VMkernel adapters, physical uplinks, or distributed switch config.
#>

function Copy-StandardPortGroupsWithPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$vCenterServer,

        [Parameter(Mandatory)]
        [string]$SourceHostName,

        [Parameter(Mandatory)]
        [string]$DestinationHostName,

        [string]$ExcludePortGroups = "",

        [pscredential]$Credential
    )

    # Build exclude array (trimmed, case-insensitive)
    $ExcludedPGArray = @()
    if ($ExcludePortGroups) {
        $ExcludedPGArray = $ExcludePortGroups.Split(",") |
            ForEach-Object { $_.Trim().ToLower() } |
            Where-Object { $_ }
    }

    if (-not $Credential) {
        $Credential = Get-Credential
    }

    Write-Host "Connecting to vCenter Server '$vCenterServer'..."
    Connect-VIServer -Server $vCenterServer -Credential $Credential | Out-Null

    try {
        $SourceHost      = Get-VMHost -Name $SourceHostName -ErrorAction Stop
        $DestinationHost = Get-VMHost -Name $DestinationHostName -ErrorAction Stop

        $SourceStandardSwitches = Get-VirtualSwitch -VMHost $SourceHost -Standard

        foreach ($vSwitch in $SourceStandardSwitches) {

            # Ensure vSwitch exists on Destination
            $DestinationVSwitch = Get-VirtualSwitch -VMHost $DestinationHost -Name $vSwitch.Name -ErrorAction SilentlyContinue
            if (-not $DestinationVSwitch) {
                Write-Host "Creating vSwitch '$($vSwitch.Name)' on destination host..."
                $DestinationVSwitch = New-VirtualSwitch `
                    -VMHost $DestinationHost `
                    -Name $vSwitch.Name `
                    -NumPorts $vSwitch.NumPorts `
                    -Mtu $vSwitch.Mtu
            }

            # Source Port Groups
            $SourcePortGroups = Get-VirtualPortGroup -VirtualSwitch $vSwitch -ErrorAction SilentlyContinue

            foreach ($SourcePG in $SourcePortGroups) {

                if ($ExcludedPGArray -contains $SourcePG.Name.ToLower()) {
                    Write-Host "Skipping excluded Port Group '$($SourcePG.Name)'" -ForegroundColor Yellow
                    continue
                }

                Write-Host "Processing Port Group '$($SourcePG.Name)' on vSwitch '$($vSwitch.Name)'"

                $DestPG = Get-VirtualPortGroup `
                    -VirtualSwitch $DestinationVSwitch `
                    -Name $SourcePG.Name `
                    -ErrorAction SilentlyContinue

                if (-not $DestPG) {
                    Write-Host "Creating Port Group '$($SourcePG.Name)' on destination..."
                    $DestPG = New-VirtualPortGroup `
                        -VirtualSwitch $DestinationVSwitch `
                        -Name $SourcePG.Name `
                        -VLanId $SourcePG.VLanId
                } else {
                    if ($DestPG.VLanId -ne $SourcePG.VLanId) {
                        Set-VirtualPortGroup `
                            -VirtualPortGroup $DestPG `
                            -VLanId $SourcePG.VLanId `
                            -Confirm:$false | Out-Null
                    }
                }

                # Copy policies via ExtensionData
                $srcSpec = $SourcePG.ExtensionData.Spec

                $newSpec = New-Object VMware.Vim.HostPortGroupSpec
                $newSpec.Name        = $DestPG.Name
                $newSpec.VlanId      = $srcSpec.VlanId
                $newSpec.VswitchName = $DestinationVSwitch.Name
                $newSpec.Policy      = $srcSpec.Policy

                $networkSystem = Get-View -Id $DestinationHost.ExtensionData.ConfigManager.NetworkSystem
                $networkSystem.UpdatePortGroup($DestPG.Name, $newSpec)

                Write-Host "Updated policies for '$($DestPG.Name)'" -ForegroundColor Green
            }
        }

    } finally {
        Write-Host "Disconnecting from vCenter Server..."
        Disconnect-VIServer -Server $vCenterServer -Force -Confirm:$false | Out-Null
    }
}
