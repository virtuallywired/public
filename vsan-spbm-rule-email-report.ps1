# This script extracts the Rules from vSAN Storage Policies and formats into a report.
# Added Email Feature with HTML Formatting 
# Tested on vSphere 6.7 Update 3.
# Script Author: Nicholas Mangraviti #VirtuallyWired
# Date: 9th December 2019
# Version: 1.1
# Blog URL: virtuallywired.io
# Usage: Just enter the vCenter URL or IP and Specify the Names of Policies to Explude from the Report.


# You can add multiple vCenter Servers. Note Credentials need to work on all vCenters.

$vCenter = ("vc.virtuallywired.io") 

# Prompt for vCenter Credentials

$Creds = Get-Credential # Or Import Stored Credentials

# If you want to Exclude specific vSAN Policies from the Report, Add the name of the policy to this Array.

[array]$SpbmExclude = ("vSAN Default Storage Policy")

## Don't Edit Below This Line ##

Connect-VIServer -Server $vCenter -Credential $Creds

$VsanPolicies = Get-SpbmStoragePolicy | Where-Object { $_.AnyOfRuleSets -like "*VSAN*" -and $_.Name -notin $SpbmExclude }
$RuleSetReport = @()
Foreach ($VsanPolicy in $VsanPolicies) {

    $RuleSet = $VsanPolicy.AnyOfRuleSets.allOfRules

    $hostFailuresToTolerate = $RuleSet.Where( { $_.Capability.Name -eq "VSAN.hostFailuresToTolerate" }).Value
    $subFailuresToTolerate = $RuleSet.Where( { $_.Capability.Name -eq "VSAN.subFailuresToTolerate" }).Value
    $locality = $RuleSet.Where( { $_.Capability.Name -eq "VSAN.locality" }).Value
    $checksumDisabled = $RuleSet.Where( { $_.Capability.Name -eq "VSAN.checksumDisabled" }).Value
    $stripeWidth = $RuleSet.Where( { $_.Capability.Name -eq "VSAN.stripeWidth" }).Value
    $forceProvisioning = $RuleSet.Where( { $_.Capability.Name -eq "VSAN.forceProvisioning" }).Value
    $iopsLimit = $RuleSet.Where( { $_.Capability.Name -eq "VSAN.iopsLimit" }).Value
    $cacheReservation = $RuleSet.Where( { $_.Capability.Name -eq "VSAN.cacheReservation" }).Value
    $proportionalCapacity = $RuleSet.Where( { $_.Capability.Name -eq "VSAN.proportionalCapacity" }).Value
    $replicaPreference = $RuleSet.Where( { $_.Capability.Name -eq "VSAN.replicaPreference" }).Value

    $RuleSetReport += New-Object PSObject -Property ([ordered]@{
                
            StoragePolicyName      = $VsanPolicy.Name
            hostFailuresToTolerate = IF ($hostFailuresToTolerate -ne $null) { $hostFailuresToTolerate } else { "--" }
            subFailuresToTolerate  = IF ($subFailuresToTolerate -ne $null) { $subFailuresToTolerate } else { "--" }
            locality               = IF ($locality -ne $null) { $locality } else { "--" }            
            checksumDisabled       = IF ($checksumDisabled -ne $null) { $checksumDisabled } else { "--" }    
            stripeWidth            = IF ($stripeWidth -ne $null) { $stripeWidth } else { "--" }          
            forceProvisioning      = IF ($forceProvisioning -ne $null) { $forceProvisioning } else { "--" }    
            iopsLimit              = IF ($iopsLimit -ne $null) { $iopsLimit } else { "--" }           
            cacheReservation       = IF ($cacheReservation -ne $null) { $cacheReservation } else { "--" }     
            proportionalCapacity   = IF ($proportionalCapacity -ne $null) { $proportionalCapacity } else { "--" }  
            replicaPreference      = IF ($replicaPreference -ne $null) { $replicaPreference } else { "RAID-0 (No Data Redundancy)" }
            vCenter                = ([regex]::Matches($VsanPolicy.Uid, '@(.+):').Groups[1].Value)     

        })
}

Disconnect-VIServer * -Force -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

$RuleSetReport | Format-Table -Property *

## Create HTML Email Report

## Setup Email parameters

$ReportTitle = "vSAN Storage Policy Rules Report"

$subject = $("$ReportTitle - $date")
$priority = "Normal"
$smtpServer = "smtp.gmail.com"
$emailFrom = "company@email.com"
$mailsend = "company@email.com" 
$emailTo = $mailsend
$emailCreds = Get-Credential # Or Import Stored Credentials

$Date = (Get-Date -Format F).ToString()

$fragments = @()
$fragments += "<H1>$($ReportTitle)</H1>" 
[xml]$html = $RuleSetReport | convertto-html -Fragment

## Highlight Cell with Value "RAID-0 (No Data Redundancy)"

for ($i = 1; $i -le $html.table.tr.count - 1; $i++) {
    if ($html.table.tr[$i].td[10] -eq "RAID-0 (No Data Redundancy)") {
        $class = $html.CreateAttribute("class")
        $class.value = 'alert'
        $html.table.tr[$i].childnodes[10].attributes.append($class) | out-null
    }
}
$fragments += $html.InnerXml
$fragments += "<p class='footer'>$($date)</p>"
$cssParams = @{ 
    head = @"
<style>h1{font-size:20px;color:#808080}
body{background-color:#e5e4e2;font-family:Tahoma;font-size:8pt;text-align:left}
td,th{border:0 solid black;border-collapse:collapse;white-space:pre}
th{color:white;background-color:#5b90bf}
table,tr,td,th{padding:5px;margin:0;white-space:pre}
tr:nth-child(even){background-color:lightgray}
table{width:95%;margin-left:5px;margin-bottom:20px}
h2{font-family:Tahoma;color:#6d7b8d}
.alert{color:red;font-weight: Bold;}
.footer{color:#5b90bf;margin-left:10px;font-family:Tahoma;font-size:8pt;font-weight:bold;font-style:italic;</style>
"@
    body = $fragments
}

$htmlBody = Convertto-html @cssParams
  
# Send the Report Email
Send-MailMessage -To $emailTo -Subject $subject -BodyAsHtml ($htmlBody | Out-String) -SmtpServer $smtpServer -From $emailFrom -Priority $priority -Port 587 -UseSsl -Credential $emailCreds
