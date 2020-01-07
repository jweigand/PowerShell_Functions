function Test-ADCredential {

    [CmdletBinding()]

    Param(
        [Parameter(Mandatory = $false)]$Credential
    )

    if (!$Credential) {$Credential = Get-Credential}

    Add-Type -AssemblyName System.DirectoryServices.AccountManagement
    $ContextType = [System.DirectoryServices.AccountManagement.ContextType]::Domain
    $PrincipalContext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext $ContextType,$env:USERDOMAIN
    $ValidAccount = $PrincipalContext.ValidateCredentials($Credential.Username,$Credential.GetNetworkCredential().Password)
    $ValidAccount
}