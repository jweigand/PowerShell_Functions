function Get-LAPSPassword {

    [CmdletBinding()]

    Param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Mandatory = $true)][string[]]$Name,
        [Parameter(Mandatory=$false)][string]$DomainController

    )

    [datetime]$origin = '1970-01-01 00:00:00'

    if (!$DomainController) {$DomainController = $env:LOGONSERVER.Replace("\\","")}

    foreach ($computer in $Name) {
        get-adcomputer -Identity $computer -server $DomainController -Properties ms-Mcs-AdmPwd, ms-Mcs-AdmPwdExpirationTime | select name, @{N="Password";E={$_."ms-Mcs-AdmPwd"}}, @{N="PasswordExpiration";E={[datetime]::fromFileTime($_."ms-Mcs-AdmPwdExpirationTime")}}
    }
}