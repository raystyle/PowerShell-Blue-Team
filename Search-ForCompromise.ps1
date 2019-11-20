﻿<#
.Synopsis
    Search-ForCompromise is a cmdlet created to find/identify whether or not a device has been compromised using basic discovery methods.
    This cmdlet was designed for system administrators. No switches need to be defined other than the computer to run this on if desired.

    ALWAYS EXECUTE THIS VERBOSELY FOR EASE OF USE


.DESCRIPTION
    This cmdlet is meant to be used to help determine if a computer has been compromised.
    I would suggest always executing this verbosely.
    It checks the following items
        1.) Sorts the heaviest processes. Make sure they are all legit.
        2.) If the hosts file has been altered the IP Addresses are displayed. The function then requires the admin to enter the IP Addresses manually. This will close any open connections and prevent any more connections to the discovered IP Addresses.
        3.) If an altered start page is configured it will be shown to the admin who will need to remove the setting.
        4.) Checks local machine and current user registry for any previously unknown applications and shows the unknown apps to the admin. The admin should verify these applications are safe.
        5.) Make sure no proxy settings have been configured/altered.
        6.) Lastly Alternate Data Streams are looked for and identified


.NOTES
    Author: Rob Osborne
    Alias: tobor
    Contact: rosborne@osbornepro.com
    https://roberthosborne.com


.SYNTAX
    Search-ForCompromise [ -ComputerName <string[]> ]


.EXAMPLE
    ---------------------  EXAMPLE 1  ----------------------------
   Search-ForCompromise -ComputerName $ComputerName -Verbose
   
   # This example exectus Search-Compromise verbosely on a remote computer

    ---------------------  EXAMPLE 2  ----------------------------
   Search-ForCompromise -Verbose
   
   # This example executes Search-ForCompromise on the local computer verbosely

.INPUT
    Accepts a string or an array of either Hostnames, FQDN's, or IPv4 Addresses
    
.OUTPUT
    There is no object created by this cmdlet. This used for changing settings and identifying a compromise.
#>

Function Search-ForCompromise {

    [CmdletBinding()]
        param (
            [Parameter(
                Mandatory=$false,
                ValueFromPipeline=$True,
                ValueFromPipelineByPropertyName=$True,
                HelpMessage="Enter The hostname of the remote computer you want to check."
            )] # End Parameter
        [string[]]$ComputerName) # End Param

BEGIN {

    # ControlAPpListFile is a list of known applications and should not cause any alarm.
    $ControlAppListFile = <\\NETWORKSHARE\file\AppList>

    #ControlCUApplistFile is a list of the current users installed applications and is used as a reference
    $ControlCUAppListFile = <\\NETWORKSHARE\file\CUAppList>

    # ControlHostsFile should be a copy of C:\Windows\system32\Drivers\etc\hosts If this file is ever edited we want to know it has been changed
    $ControlHostsFile = <\\NETWORKLOCATION\file\hosts>
    
    # This variable is used for mapping the network location as a drive in order to update the files in the network locations
    $NetworkShareLoationsAbove = <\\NETWORKLOCATION\file>

} # End BEGIN

PROCESS 
{

     If (!($ComputerName.IsPresent)) 
     {

        $ComputerName = $env:COMPUTERNAME

     } # End If


    Invoke-Command -ComputerName $ComputerName -ScriptBlock {

        Write-Verbose "Finding the heaviest running processes....`n"

        Get-Process | Sort-Object -Property CPU -Descending 

        Read-Host "`nAbove is a list of the top 20 heaviest processes currently running. Take note of anything unusual. Press Enter to continue"

        Write-Verbose "Checking for altered hosts file. Block connections to IP Addresses added to the hosts file if they are malicious"
        Write-Verbose "`nDetermining whether or not the hosts file has been altered...."

        $Diff = Get-Content -Path "C:\Windows\system32\Drivers\etc\hosts"
        $Ref = Get-Content -Path $ControlHostsFile

        If (Compare-Object -ReferenceObject $Ref -DifferenceObject $Diff)
        {

            $Diff

            Write-Warning 'Hosts file has been altered. Take note of any IP Addresses and break their connections by completing the next steps.'

            $NumberOfBad = Read-Host 'How many IP Address have been added to the hosts file? Example: 2'

            For ($i = 1; $i -le $NumberOfBad; $i++)
            {

                Function Block-BadGuy
                {
                    [CmdletBinding()]
                        param(
                            [Parameter(
                                Mandatory=$true,
                                HelpMessage="Enter an IP Address that was added to the hosts file listed in the above output."
                            )] # End Parameter
                       [string[]]$IPaddress
                     ) # End Param

                    If ($IPAddress) 
                    {

                        New-NetFirewallRule -Name "Deny Inbound Connections to $IPAddress" -DisplayName "Deny Inbound Connections from $IPAddress" -Enabled True -Direction Inbound -Protocol ANY -Action Block -Profile ANY -RemoteAddress $IPAddress
                        New-NetFirewallRule -Name "Deny Outbound Connections to $IPAddress" -DisplayName "Deny Outbound Connections from $IPAddress" -Enabled True -Direction Outbound -Protocol ANY -Action Block -Profile ANY -RemoteAddress $IPAddress

                        Write-Verbose 'New Firewall rules added to block inbound and outbound connections to the malicious IP Address.'
                        $BadGuyProcessIDs = Get-NetTCPConnection -RemoteAddress $IPAddress | Select-Object -Property OwningProcess

                        ForEach ($ProcessId in $badGuyProcessIDs) 
                        {

                            Stop-Process -Id $ProcessId -Force -PassThru
                            Write-Verbose "Above are the processes that were stopped which connected to the remote address.`nFirewall rules have been added to block anymore connections to those addresses."

                        } # End Foreach

                    } # End if bad guy IP response
                    Else 
                    { 

                        Write-Warning "No IP Address was entered." 

                    } # End Else

                } # End Function Block-BadGuy

                Block-BadGuy -Verbose

            } # End for loop

        } # End if for finding an altered hosts file
        Else
        {

            Write-Verbose 'Hosts file has not been altered. Moving on to next check.....'

        } # End Else

     # Check for altered Internet Explorer Start Page

        If (Get-Childitem -Path "HKCU:\software\Microsoft\Internet Explorer\Main\Start Page Redirect=*")
        {

            Write-Warning 'Internet Explorer start page redirect found. Make sure it is not malicious.'

        } # End if for finding start page redirect

        Write-Verbose "Checking $ComputerName's registry..."

        $LMAppRef = Import-Csv -Path $ControlAppListFile
        $LMAppDiff = Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\' | Select-Object -Property PSChildName

        If ($LMApplist = Compare-Object -DifferenceObject $LMAppDiff -ReferenceObject $LMAppRef -Property PsChildName | Where-Object -Property SideIndicator -like "<=" | Select-Object -ExpandProperty PSChildName ) 
        {

            $LMApplist

            Write-Warning 'This is a list of previously unrecorded Application Processes. Check these results to find any possibly malicous applications.'

            $LMApplist | Export-Csv -Path $ControlAppListFile -Append

        } # End if AppList
        Else 
        { 

            Write-Verbose 'No previously unknown application services were found under Local Machine.'

        } # End Else

        Write-Verbose "Checking Current User Registry"

        $CUAppRef = Import-Csv -Path $ControlCUAppListFile
        $CUAppDiff = Get-ChildItem -Path 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\' | Select-Object -Property PSChildName

        If ($Applist = Compare-Object -DifferenceObject $CUAppDiff -ReferenceObject $CUAppRef -Property PsChildName | Where-Object -Property SideIndicator -like "<=" | Select-Object -ExpandProperty PSChildName ) 
        {

            $CUApplist

            Write-Warning 'This is a list of previously unrecorded Application Processes. Check these results to find any possibly malicous applications.'

            $CUApplist | Export-Csv -Path $ControlCUAppListFile -Append

        } # End if AppList

        Else 
        { 

            Write-Verbose 'No previously unknown application services were found under Current User.'

        } # End Else

        Write-Verbose "Checking proxy settings"

        If (Get-ChildItem -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Proxy*')
        {

            Write-Warning 'Proxy settings have been configured. This may mean trouble.'

        } # End If
        Else
        {

            Write-Verbose 'No proxy settings detected.'

        } # End Else

        $ADSFiles = Get-ChildItem -Path 'C:\' -Recurse | ForEach-Object { Get-Item $_.FullName -Stream * } | Where-Object { ($_.Stream -ne ':$Data') -and ($_.Stream -ne 'Zone.Identifier') }

        If ($ADSFiles)
        {

            ForEach ($ADSFile in $ADSFiles)
            {

                $ADSFilePath = $ADSFile.FileName

                $ADSFileNameStream1,$ADSFileNameStream2 = ($ADSFilePath.PSChildName).Split(':')

                Remove-Item –Path { $ADSFilePath } –Stream { $ADSFileNameStream2 }

            } # End ForEach

        } # End If

    } # End Invoke-Command

} # End PROCESS

END
{

    Write-Verbose "Execution of command has completed."

} # End END

} # End Function
