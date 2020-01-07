Function Get-NTAPSnapmirrorProgress {


[CmdletBinding()]

Param(
    [Parameter(Mandatory=$true)][string]$DRCluster,
    [Parameter(Mandatory=$true)][string]$DRVolume
)

if (!$credentials) {$credentials = Get-Credential}
connect-nccontroller $drcluster -Credential $credentials | out-null
$drsnap = get-ncsnapmirror -DestinationVolume $drvolume #| select destinationlocation, sourcevserver, sourcevolume, status, maxtransferrate, newestsnapshot, lagtime, snapshotprogress, lasttransferduration, lasttransfersize
$drvol = Get-NcVol -Name $DRVolume
$sourcecluster = (Get-NcVserverPeer | where-object {$_.PeerVserver -eq $drsnap.SourceVserver}).PeerCluster
connect-nccontroller $sourcecluster -Credential $credentials | out-null
$dpvol = Get-NcVol -Name $drsnap.SourceVolume
$snapdelta = get-ncsnapshotdelta -Volume $drsnap.SourceVolume -Snapshot1 $drsnap.newestSnapshot -VserverContext $drsnap.SourceVserver
try {$transferrate = [math]::round($drsnap.lasttransfersize/$drsnap.lasttransferduration)}
catch {<#suppresses division by zero error#>}
$remainingdata = $snapdelta.ConsumedSize - $drsnap.SnapshotProgress
if ($null -eq $transferrate -and $drsnap.maxtransferrate -ne 0) {
    $remainingtime = [math]::round($remainingdata/$drsnap.maxtransferrate)
}
else {$remainingtime = [math]::round($remainingdata/$transferrate)}
$formattedtransferrate = convertto-formattednumber -Value $transferrate -Type datasize -NumberFormatString "0.00"
$transferrateoutput = "$formattedtransferrate/S"
$formattedthrottle = convertto-formattednumber -Value $drsnap.maxtransferrate -Type datasize -NumberFormatString "0.00"
$throttleoutput = "$formattedthrottle/S"
if ($drsnap.maxtransferrate -eq "0") {$throttleoutput = "unlimited"}
if ($drsnap.status -eq "idle") {$transferrateoutput = $null}


$transferobject = [PSCustomObject]@{
    DestinationLocation = $drsnap.destinationlocation
    Status = $drsnap.status
    Progress = convertto-formattednumber -Value $drsnap.SnapshotProgress -Type datasize -NumberFormatString "0.00"
    TotalData = convertto-formattednumber -Value $snapdelta.consumedsize -Type datasize -NumberFormatString "0.00"
    LastTransferRate = $transferrateoutput
    Throttle = $throttleoutput
    LagTime = [timespan]::fromseconds($drsnap.LagTime)
    EstimatedTimeLeft = [timespan]::fromseconds($remainingtime)
}
$global:CurrentNcController = $null
$transferobject
}
