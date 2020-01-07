function Get-NTAPSMBSecurity {

    [CmdletBinding()]

    Param(
        [Parameter(Mandatory = $false)][string[]]$Clusters
	
    )

    if (!$credentials) {$credentials = Get-Credential}
    $CIFSTable = new-object system.collections.arraylist
    $totalCount = $clusters.count
    $counter = 0
    foreach ($cluster in $clusters) {
        $counter++
        Write-Progress -Activity "Querying Vserver SMB Settings from $totalCount clusters" -CurrentOperation "$cluster ($counter of $totalCount)" -PercentComplete (($counter/$totalCount)*100)
        Try {
            connect-nccontroller $cluster -credential $credentials -ErrorAction SilentlyContinue | out-null
            if (!$global:currentnccontroller) { connect-nccontroller $cluster -credential $LocalCreds -ErrorAction Stop | out-null }
            $cifsservers = get-nccifsserver
            foreach ($server in $cifsservers) {
                $cifsoptions = $server | get-nccifsoption
                $cifssecurity = $server | Get-NcCifsSecurity
                $CIFSItem = [PSCustomObject]@{
                    Cluster                     = $cluster
                    Vserver                     = $server.cifsserver
                    IsSmb1Enabled               = $cifsoptions.IsSmb1Enabled
                    IsSigningRequired           = $cifssecurity.IsSigningRequired
                    IsSmbEncryptionRequired     = $cifssecurity.IsSmbEncryptionRequired
                    #Smb1EnabledForDcConnections = $cifssecurity.Smb1EnabledForDcConnections
                    #Smb2EnabledForDcConnections = $cifssecurity.Smb2EnabledForDcConnections
                }
                $CIFSTable.add($CIFSItem) | out-null
            }

        }
        Catch {
            write-warning $_.Exception.Message
            write-warning "There was an exception"
        }  
			
    }
    $global:CurrentNcController = $null
    $CIFSTable
}