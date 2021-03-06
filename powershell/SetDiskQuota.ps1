# This script set quota settings on disk.
# Disk by defaults is "C:", please change it in Param block if you need or pass disk name as parameter: ./SetDiskQuota.ps1 c:
# Users with No Limit quota please add in $unlimitedUsers array in format NETBIOSDOMAINNAME\USERNAME
Param(
          [string]$drive = "c:"
)

#Max value of UINT64 - No Limit analog
$No_Limit = "18446744073709551615"


#Enable/Disable disk quota, 0 - disable disk quota, 1 - enable disk quota without Limit Disk Usage, 2 - enable quota with Limit Disk Usage
$enableDiskQuota = 2
#default disk quota in gigabites
$defaultDiskQuota = 40
$defaultDiskQuota = $defaultDiskQuota * ([Math]::Pow(1024,3))
#Warning level 90%
$warningLevel = $defaultDiskQuota * 0.9

#Domain name and computername
$computerName = $env:COMPUTERNAME
$userDomain = $env:USERDOMAIN

#List of unlimited users
$unlimitedUsers = "NT SERVICE\TrustedInstaller", ($computerName + "\SYSTEM"), ($userDomain + "\InstService")


#Enable quota on disk
Write-Host "Enabling disk quota..."
$query_quota = "Select * from Win32_QuotaSetting where VolumePath = '" + $drive + "\\'"
$colDisks = Get-WmiObject -Query $query_quota
foreach($disk in $colDisks){
   $disk.State = $enableDiskQuota
   $disk.DefaultLimit = $defaultDiskQuota
   $disk.DefaultWarningLimit = $warningLevel
   $disk.WarningExceededNotification = 1
   $disk.ExceededNotification = 1
   $res = $disk.Put()
}

#check for user in list of unlimited users
function isUnlimited($relPath){
    $unlimited = $false
    foreach($user in $unlimitedUsers){
        $userRelPath = 'Win32_Account.Domain="' + $user.split("\")[0] + '",Name="' + $user.split("\")[1] + '"'
        if($userRelPath -eq $relPath){
            $unlimited = $true
        }
    }
    return $unlimited
}

#Create or rewrite quota entries for unlimited users
function createOrRewriteQuotaEntries{
    foreach($user in $unlimitedUsers){
        Write-Host "Creating quota entry for user " $user "..."
        $userRelPath = 'Win32_Account.Domain="' + $user.split("\")[0] + '",Name="' + $user.split("\")[1] + '"'
        $query_disk = "select * from Win32_LogicalDisk where DeviceID='"+$drive+"'"
        $objDisk = get-wmiobject -query $query_disk
        $objquota = (new-object management.managementclass Win32_DiskQuota).CreateInstance()
        $objquota.User = $userRelPath
        $objquota.QuotaVolume = $objDisk.Path.RelativePath
        $objquota.Limit = $No_Limit
        $objquota.WarningLimit = $No_Limit
        try{
            $res = $objquota.put()
            Write-Host "Done."
            }
        catch [System.UnauthorizedAccessException]{
            Write-Host $_.Exception.GetType().FullName " You not have permissions to change quota entry for user " $user
            }
    }
}

#set quota for users except unlimited users
Write-Host "Set Limit for existing quota entries..."
$col_quota_query = "Select * from Win32_DiskQuota"
$col_quota = Get-WmiObject -Query $col_quota_query
foreach($objQuota in $col_quota ){
    $isUnlimited = isUnlimited $objQuota.User
    # If user not unlimited set default settings
    if(!($isUnlimited)){
        #$objQuota.Limit = $No_Limit
        #$objQuota.WarningLimit = $No_Limit
        #$res = $objQuota.put()
        $objQuota.Limit = $defaultDiskQuota
        $objQuota.WarningLimit = $warningLevel
        try{
            $res = $objQuota.put()
            }
        catch [System.UnauthorizedAccessException]{
            Write-Host $_.Exception.GetType().FullName " You not have permissions to change quota entry for user " $objQuota.User
        }      
    } 
 }
 createOrRewriteQuotaEntries

