function Get-VCenterStats {

    [CmdletBinding()]

    Param(
        [Parameter(Mandatory = $false)][string[]]$vcenters,
        [switch]$ConsoleOutput
    )

    if (!$ConsoleOutput) {
        $SaveChooser = New-Object -Typename System.Windows.Forms.SaveFileDialog
        $SaveChooser.Filter = "CSV (Comma delimited)|*.csv"
        $SaveChooser.FileName = "vcenterstats.csv"
        $SaveChooser.ShowDialog()
    }

    $creds = Get-Credential "$env:USERDOMAIN\$env:USERNAME"
    $ValidCreds = Test-ADCredential -Credential $creds
    if ($ValidCreds -eq $false) {
        Write-Warning "Credentials are not valid, please try again."
        return
    }
    elseif ($ValidCreds -eq $true) {
        #connect to each vcenter, get data

        if (!$vcenters) {
            $vcenters = get-allvcenters
        }
        $totalCount = ($vcenters).Count
        $counter = 0
        $ClusterTable = new-object system.collections.arraylist
        foreach ($vcenter in $vcenters) {
            $counter++
            Write-Progress -Activity "Getting vCenter statistics from $totalcount servers..." -CurrentOperation "Getting data from $vcenter ($counter of $totalCount)" -PercentComplete (($counter / $totalCount) * 100)
            #disconnects currently connected vcenters
            if ($global:DefaultVIServers.Count -gt 0) { disconnect-viserver * -Force -Confirm:$false }
            $connected = $null
            $connectionfailure = $null
            $connected = connect-viserver $vcenter -Credential $creds -ErrorVariable $connectionfailure
            if ($connected) {
                $clusters = get-cluster
                foreach ($cluster in $clusters) {
                    $vmhosts = $cluster | get-vmhost
                    $HostsTable = new-object system.collections.arraylist
                    foreach ($vmhost in $vmhosts) {
                        $HostObject = [PSCustomObject]@{
                            Cluster         = $cluster.name
                            Host            = $vmhost.name
                            ConnectionState = $vmhost.ConnectionState
                            PowerState      = $vmhost.PowerState
                            NumCPUs         = $vmhost.numcpu
                            'CPUUsage%'     = ($vmhost.cpuusagemhz * 100 / $vmhost.cputotalmhz)
                            CPUUsageMhz     = $vmhost.cpuusagemhz
                            CPUTotalMhz     = $vmhost.cputotalmhz
                            'MemUsage%'     = ($vmhost.MemoryUsageGB * 100 / $vmhost.MemoryTotalGB)
                            MemUsageGB      = [int]$vmhost.MemoryUsageGB
                            MemTotalGB      = [int]$vmhost.MemoryTotalGB
                        }
                        $HostsTable.Add($HostObject) | out-null
                    }

                    $ClusterVMs = ($cluster | get-vm | Where-Object { $_.ExtensionData.Config.ManagedBy.ExtensionKey -ne 'com.vmware.vcDr' })
                    $PoweredOff = $ClusterVMs | group powerstate | where-object name -EQ "PoweredOff"
                    $PoweredOn = $ClusterVMs | group powerstate | where-object name -EQ "PoweredOn"

                    $ClusterTotals = [PSCustomObject]@{
                        vCenter       = $global:DefaultVIServers.name
                        Cluster       = $cluster.name
                        Hosts         = ($HostsTable.host).Count
                        NumCPUs       = ($HostsTable | measure NumCPUs -Sum).Sum
                        MemGB         = ($HostsTable | measure MemTotalGB -Sum).Sum
                        'CPUUsage%'   = ([int](($HostsTable | measure CPUUsage% -Sum).Sum / ($HostsTable.host).Count))
                        'MemUsage%'   = [math]::Truncate(($HostsTable | measure MemUsage% -Sum).Sum / ($HostsTable.host).Count)
                        TotalVMs      = ($ClusterVMs.Count)
                        PoweredOnVMs  = $PoweredOn.count
                        PoweredOffVMs = $PoweredOff.count
                        VMsCPU        = ($ClusterVMs | measure NumCPU -Sum).Sum
                        VMsMemGB      = ($ClusterVMs | measure MemoryGB -Sum).Sum
                        'CPUAll%'     = [int]((($ClusterVMs | measure NumCPU -Sum).Sum / ($HostsTable | measure NumCPUs -Sum).Sum) * 100)
                        'MemAll%'     = [int]((($ClusterVMs | measure MemoryGB -Sum).Sum / ($HostsTable | measure MemTotalGB -Sum).Sum) * 100)
                    }
                    $ClusterTable.Add($ClusterTotals) | out-null
                
                    $SumTotals = [PSCustomObject]@{
                        vCenter       = "All vCenters"
                        Cluster       = "All Clusters"
                        Hosts         = ($ClusterTable | measure Hosts -Sum).Sum
                        NumCPUs       = ($ClusterTable | measure NumCPUs -Sum).Sum
                        MemGB         = ($ClusterTable | measure MemGB -Sum).Sum
                        'CPUUsage%'   = [int](($ClusterTable | measure CPUUsage% -Sum).Sum / ($ClusterTable.Hosts).Count)
                        'MemUsage%'   = [math]::Truncate(($ClusterTable | measure MemUsage% -Sum).Sum / ($ClusterTable.Hosts).Count)
                        TotalVMs      = ($ClusterTable | measure TotalVMs -Sum).Sum
                        PoweredOnVMs  = ($ClusterTable | measure PoweredOnVMs -Sum).Sum
                        PoweredOffVMs = ($ClusterTable | measure PoweredOffVMs -Sum).Sum
                        VMsCPU        = ($ClusterTable | measure VMsCPU -Sum).Sum
                        VMsMemGB      = [int](($ClusterTable | measure VMsMemGB -Sum).Sum)
                        'CPUAll%'     = [int](($ClusterTable | measure CPUAll% -Average).Average)
                        'MemAll%'     = [int](($ClusterTable | measure MemAll% -Average).Average)
                    }
                    $ClusterTable.Add($SumTotals) | out-null
                }
            }
            elseif ($connectionfailure) { write-warning $vcenter $connectionfailure }
        }

        if ($ConsoleOutput) { $ClusterTable }
        else {
            $clustertable | export-csv -Path $SaveChooser.FileName -NoTypeInformation
            write-output "vCenter stats saved to: $($SaveChooser.FileName)"
        }

    }

}