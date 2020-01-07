function Get-SRMHealth {

    [CmdletBinding()]

    Param(
        [Parameter(Mandatory = $true)][string[]]$vcenters,
        [Switch]$CSV
    )
    if ($global:DefaultVIServers.Count -gt 0) { disconnect-viserver * -Force -Confirm:$false }
    if ($global:DefaultSRMServers.Count -gt 0) { disconnect-srmserver * -Force -Confirm:$false }
    $credential = get-credential

    #relies on "Test-ADCredential" function
    $ValidCreds = Test-ADCredential -Credential $credential
    if ($ValidCreds -eq $false) {
        Write-Warning "Credentials are not valid, please try again."
        return
    }
    elseif ($ValidCreds -eq $true) {
        foreach ($vcenter in $vcenters) {

            Connect-VIServer -Server $vcenter -Credential $credential -WarningAction SilentlyContinue
            $SrmApi = (Connect-SrmServer -Credential $credential -RemoteCredential $credential -WarningAction SilentlyContinue).ExtensionData
            $ProtectedVMTable = new-object system.collections.arraylist
            $GroupTable = new-object system.collections.arraylist

            #create list of all datastores
            $DatastoreTable = new-object system.collections.arraylist
            $protecteddatastores = $srmapi.Protection.ListProtectedDatastores()
            $unprotecteddatastores = $SrmApi.Protection.ListUnassignedReplicatedDatastores()
            foreach ($datastore in $unprotecteddatastores) {
                $datastore.UpdateViewData()
                $DatastoreObject = [PSCustomObject]@{
                    MoRef              = $datastore.MoRef.Value
                    Name               = $datastore.Name
                    DatastoreProtected = $false
                }
                $DatastoreTable.Add($DatastoreObject) | out-null
            }
            foreach ($datastore in $protecteddatastores) {
                $datastore.UpdateViewData()
                $DatastoreObject = [PSCustomObject]@{
                    MoRef              = $datastore.MoRef.Value
                    Name               = $datastore.Name
                    DatastoreProtected = $true
                }
                $DatastoreTable.Add($DatastoreObject) | out-null
            }

            #Recovery Plans
            $RecoveryPlans = $SrmApi.Recovery.ListPlans()
            $PlansTable = new-object system.collections.arraylist
            foreach ($plan in $recoveryplans) {
                $planinfo = $plan.getinfo()
                if ($planinfo.state -eq "Ready") { 
                    $recoveryplans.Remove($_) | out-null
                    Continue 
                }
                $grouplist = @()
                foreach ($group in $planinfo.protectiongroups) {
                    $groupinfo = $group.getinfo()
                    $grouplist += $groupinfo.Name
                }
                $PlanObject = [PSCustomObject]@{
                    vCenter          = $vcenter
                    RecoveryPlan     = $planinfo.name
                    ProtectionGroups = ($grouplist -join ", ")
                    State            = $planinfo.State
                }
                $PlansTable.Add($PlanObject) | out-null
            }

            #groups and VMs
            $Groups = $SrmApi.Protection.ListProtectionGroups()
            foreach ($Group in $Groups) {
                $GroupDatastore = $group.ListProtectedDatastores()
                $GroupDatastores = @()
                foreach ($grpdatastore in $GroupDatastore) {
                    foreach ($datastore in $DatastoreTable) {
                        if ($datastore.MoRef -eq $grpdatastore.MoRef.Value) {
                            $Groupdatastores += get-datastore $datastore.name
                        }
                    }
                }
                $GroupState = $Group.GetProtectionState()
                if ($GroupState -eq "Shadowing") { $Groups.Remove($_) | out-null; Continue }
                $Plans = $Group.ListRecoveryPlans()
                $planlist = @()
                foreach ($Plan in $Plans) {
                    $planinfo = $plan.getinfo()
                    $planlist += $planinfo.Name
                }
                $GroupData = $Group.GetInfo()
                $GroupObject = [PSCustomObject]@{
                    vCenter         = $vcenter
                    ProtectionGroup = $GroupData.Name
                    RecoveryPlans   = ($planlist -join ", ")
                    Healthy         = $Group.CheckConfigured()
                    State           = $Group.GetProtectionState()
                }
                $GroupTable.Add($GroupObject) | out-null
            
                $ProtectedVMs = $Group.ListProtectedVms()
                $VMsInDatastore = $GroupDatastores | get-vm
    
                foreach ($VM in $ProtectedVMs) {
                    try {
                        $VM.Vm.UpdateViewData()
                        $VMName = $VM.Vm.Name
                    }
                    catch { $VMName = $_.Exception.InnerException.Message }
                    $ProtectedVMObject = [PSCustomObject]@{
                        vCenter         = $vcenter
                        ProtectionGroup = $GroupData.Name
                        VM              = $VMName
                        State           = $VM.State
                        PeerState       = $VM.PeerState
                        NeedsConfig     = $VM.NeedsConfiguration
                        Faults          = $VM.Faults
                    }
                    $ProtectedVMTable.Add($ProtectedVMObject) | out-null
                }

                foreach ($VMinDatastore in $VMsInDatastore) {
                    $matchfound = $null
                    foreach ($VM in $ProtectedVMs) {
                        if ($VM.Vm.Name -eq $VMinDatastore.name) { $matchfound = $true }
                    }
                    if ($matchfound -ne $true) {
                        $ProtectedVMObject = [PSCustomObject]@{
                            vCenter         = $vcenter
                            ProtectionGroup = $GroupData.Name
                            VM              = $VMinDatastore.name
                            State           = "N/A"
                            PeerState       = "N/A"
                            NeedsConfig     = $true
                            Faults          = $null
                        }
                        $ProtectedVMTable.Add($ProtectedVMObject) | out-null
                    }
                }
            }

            if (!$CSV) {
                $PlansTable | sort RecoveryPlan
                $GroupTable | sort ProtectionGroup | format-table
                $ProtectedVMTable | sort ProtectionGroup, VM | format-table
            }

            if ($CSV) {
                $PlansTable | sort RecoveryPlan | Export-CSV -Path "C:\Users\$env:USERNAME\Desktop\$vcenter`_SRM_RecoveryPlans.csv" -NoTypeInformation -Append -force
                $GroupTable | sort ProtectionGroup | Export-CSV -Path "C:\Users\$env:USERNAME\Desktop\$vcenter`_SRM_ProtectionGroups.csv" -NoTypeInformation -Append -force
                $ProtectedVMTable | sort ProtectionGroup, VM | Export-CSV -Path "C:\Users\$env:USERNAME\Desktop\$vcenter`_SRM_VMs.csv" -NoTypeInformation -Append -force
            }
            if ($global:DefaultVIServers.Count -gt 0) { disconnect-viserver * -Force -Confirm:$false }
            if ($global:DefaultSRMServers.Count -gt 0) { disconnect-srmserver * -Force -Confirm:$false }
        }
    }
}