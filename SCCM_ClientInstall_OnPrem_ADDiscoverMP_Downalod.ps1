<# 
.SYNOPSIS
    Get the computers Domain
    Search that Domain for published SCCM Management Points that are active (updated is the past 1 month)
    Select from that list at Random which one to use
    Perform a Directory Download from the MP's HTTP CCM_Client folder - download the SCCM Client install source
    Execute the ccmsetup from that downloaded source
 
.DESCRIPTION
    
 
.AUTHOR
    Donald J. Rowland Sr.
 
.DATE
    June 2, 2020
 
.Version 
    202006021400
#>
 
Function Find_SCCMMPs(
     [Parameter(Mandatory=$true)] [String] $Domain
    )
{
    $ADSPath = "LDAP://$Domain"
    Write-host "[$(Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")] `tPreparing to search for Computers in $ADSPath" -BackgroundColor White -ForegroundColor Blue
    #LogWrite -Mylogfile $LogfilePath -MyLogEntry "`tINFO: `tPreparing to search for Computers in $ADSPath with a PwdLastSet $MonthsAgo months ago."
    $LDAPMonthsAgo = $($(get-date).AddMonths(-$MonthsAgo).ToFileTime())
    $table = $null
    $ADDatetoUse = (Get-date -date (Get-date).AddMonths(-1) -Format "yyyyMMddHHmmss.0Z")
    $DirectoryEntry = New-Object System.DirectoryServices.DirectoryEntry($ADSPath)
    $DirectorySearcher = New-Object System.DirectoryServices.DirectorySearcher
    $DirectorySearcher.SearchRoot = $DirectoryEntry
    $DirectorySearcher.PageSize = 1000
    $DirectorySearcher.Filter = "(&(objectClass=mSSMSManagementPoint)(whenChanged>=$($ADDatetoUse)))"
    $DirectorySearcher.SearchScope = "Subtree"
 
    $junk = $DirectorySearcher.PropertiesToLoad.Add("dNSHostName")
    $junk = $DirectorySearcher.PropertiesToLoad.Add("name")
    $junk = $DirectorySearcher.PropertiesToLoad.Add("DistinguishedName")
    $junk = $DirectorySearcher.PropertiesToLoad.Add("whenChanged")
    $junk = $DirectorySearcher.PropertiesToLoad.Add("whenCreated") 
 
    Write-host "[$(Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")] `tSearching : $($DirectorySearcher.Filter)" -BackgroundColor Gray -ForegroundColor Blue
    #LogWrite -Mylogfile $LogfilePath -MyLogEntry "`tSearching : $($DirectorySearcher.Filter)"
    $ADObjects = $DirectorySearcher.FindAll()
    $DirectorySearcher.Dispose()
    $DirectoryEntry.Dispose()
    
    Write-Host "[$(Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")] `t$($ADObjects.Count) objects found in $ADSPath meeting the above criteria." -BackgroundColor DarkBlue -ForegroundColor White
 
    #$ADObjects | SELECT @{L="Name";E={$_.properties["name"]}},@{L="dNSHostName";E={$_.properties["dNSHostName"]}},@{L="DistinguishedName";E={$_.properties["distinguishedname"]}},@{L="whenChanged";E={$_.properties["whenChanged"]}},@{L="whenCreated";E={$_.properties["whenCreated"]},@{L="mSSMSCapabilities";E={$_.properties["mSSMSCapabilities"]}}}
    
    Return $ADObjects
 
    $ADObjects.Dispose() 
    Remove-Variable $ADObjects
    Remove-Variable $DirectorySearcher
    Remove-Variable $DirectoryEntry
    [gc]::Collect()
}
 
Function Do_HTTP_DIR_Download 
(
    [Parameter(Mandatory=$true)] [String] $HTTPFolder,
    [Parameter(Mandatory=$true)] [String] $DownloadPath
)
{
    $HTTPGet = Invoke-WebRequest $HTTPFolder -ErrorAction Stop
    $AllLinks = $HTTPGet.links | Where-Object {$_.innerHTML -ne "[To Parent Directory]" -and $_.innerHTML -ne 'web.config'} #| Select -Skip 23
    #$CMDBrowser.links | format-table
    foreach ($link in $AllLinks) {
        $RawWebsite = $HTTPFolder -split '/'
        $WebSite = $RawWebsite[0,2] -join '//'
        If($link.innerText.Contains(".")) {
            $FileUrl = "{0}{1}" -f $WebSite, $Link.href
            $FilePath = "{0}\{1}" -f $DownloadPath, $Link.innerText
            If(Test-Path -Path $FilePath) { 
                #Write-Host "$LevelString$($Link.innerText) --Already exist - Overwritten" -ForegroundColor DarkYellow
                Write-Host "[$(Get-Date -Format "yyyy/MM/dd HH:mm:ss zzz")] $FilePath --Already exist - Overwritten" -ForegroundColor DarkYellow
                LogWrite -Mylogfile $LogfilePath -MyLogEntry "$FilePath --Already exist - Overwritten"
                Remove-Item $FilePath -Force 
            } Else {
                Write-Host "[$(Get-Date -Format "yyyy/MM/dd HH:mm:ss zzz")] $FilePath" -BackgroundColor DarkGreen -ForegroundColor Yellow
                LogWrite -Mylogfile $LogfilePath -MyLogEntry "$FilePath"
            }
            Invoke-WebRequest -Uri $FileUrl -OutFile $FilePath
 
        } Else {
            $NewDownloadPath = "$($DownloadPath)\$($link.innerText)"
            $HTTPSubFolder = "$($HTTPFolder)/$($link.innerText)/"
            Write-Host "[$(Get-Date -Format "yyyy/MM/dd HH:mm:ss zzz")] $NewDownloadPath" -BackgroundColor DarkGreen
            LogWrite -Mylogfile $LogfilePath -MyLogEntry "$NewDownloadPath"
            if (!(Test-Path $NewDownloadPath)) {
                New-Item -Path $NewDownloadPath -ItemType Directory | Out-Null
            }
            Do_HTTP_DIR_Download -HTTPFolder $HTTPSubFolder -DownloadPath $NewDownloadPath
        }
    }
 
}
 
 
Function LogWrite 
(
    [string] $MyLogfile = (throw "Missing Log File Path"),
    [string] $MylogEntry = (throw "Missing Log Entry")
)
{
    $TimeStamp = Get-Date
    Add-content $MyLogfile -value "$TimeStamp  $MylogEntry"
}
 
 
<#------------------------------------------------------#
   --             M A I N          --
##------------------------------------------------------#>
CLS
$MyUser = [Environment]::UserName
$MyDomain = [Environment]::UserDomainName
$MyComputername = [Environment]::MachineName
$MyScriptFullPath = Split-Path $SCRIPT:MyInvocation.MyCommand.Path -parent
$MyScriptName = Split-Path $SCRIPT:MyInvocation.MyCommand.Path -leaf
Write-Host "Executing:     $MyScriptFullPath\$MyScriptName"
$MyLogFileName = "$MyScriptName.log"
$LogfilePath = "$($MyScriptFullPath)\$($MyScriptName.Replace('.ps1',''))_$(Get-Date -format "yyyyMMddHHmmss").log"
 
LogWrite -Mylogfile $LogfilePath -MyLogEntry "Executing:    $MyScriptFullPath\$MyScriptName"
LogWrite -Mylogfile $LogfilePath -MyLogEntry "Running As:   $MyDomain\$MyUser on $MyComputername"
 
 
#Test to see if the SCCM Client is present and when it last spoke to SCCM
$CCMExecService = $null
$CCMExecService = Get-Service -Name CcmExec
If($CCMExecService) {
    Write-Host "[$(Get-Date -Format "yyyy/MM/dd HH:mm:ss zzz")] Found existsing of the CCMEXEC Service | " -BackgroundColor Yellow -ForegroundColor Black -NoNewline
    
    #when did it last talk to an SCCM MP?
    $LastMPExchange = $null
    $LastMPExchange = (Get-CimInstance -namespace root\ccm\LocationServices -classname SMS_MPInformation | Select MP, MPLastUpdateTime | Sort MPLastUpdateTime -Descending).MPLastUpdateTime[0]
    $MPSpan = New-Timespan -Start $($LastMPExchange) -End $(Get-Date)
    If($MPSpan.Days -le 14) {
        #This is within allowed range, let it go
        Write-Host " Last MP exchange was $($MPSpan.Days) days ago ($($LastMPExchange)) - No action required" -BackgroundColor DarkGreen -ForegroundColor White
        LogWrite -Mylogfile $LogfilePath -MyLogEntry "Found existsing of the CCMEXEC Service | Last MP exchange was $($MPSpan.Days) days ago ($($LastMPExchange)) - No action required"
        Return 0
    } Else {
        Write-Host " Last MP exchange was $($MPSpan.Days) days ago ($($LastMPExchange)) - Taking Action" -BackgroundColor DarkRed -ForegroundColor White
        LogWrite -Mylogfile $LogfilePath -MyLogEntry "Found existsing of the CCMEXEC Service | Last MP exchange was $($MPSpan.Days) days ago ($($LastMPExchange)) - Taking Action"
        
    }
} Else {
    Write-Host "[$(Get-Date -Format "yyyy/MM/dd HH:mm:ss zzz")] CCMEXEC Service does not exist | Taking Action " -BackgroundColor DarkRed -ForegroundColor White
    LogWrite -Mylogfile $LogfilePath -MyLogEntry "CCMEXEC Service does not exist | Taking Action"
}
 
#NULL out used vaeriables
$CIM_This_ComputerSystem, $DomainToSearch, $ListofSCCMMPs, $MPS, $MPToUse = $Null
 
#Get the Domain the computer is joined to
$CIM_This_ComputerSystem = get-ciminstance -classname win32_computersystem
$DomainToSearch = "DC=$($CIM_This_ComputerSystem.Domain.Replace(".",",DC="))"
Write-Host "[$(Get-Date -Format "yyyy/MM/dd HH:mm:ss zzz")] Searching Domain '$($DomainToSearch)' to find an SCCM Mamagement Point (MP) to use..." -BackgroundColor DarkBlue -ForegroundColor White
LogWrite -Mylogfile $LogfilePath -MyLogEntry "Searching Domain '$($DomainToSearch)' to find anSCCM Mamagement Point (MP) to use..."
 
#Search that domain for a list of any published SCCM Management Servers
$ListofSCCMMPs = Find_SCCMMPs -Domain $DomainToSearch 
Write-Host "[$(Get-Date -Format "yyyy/MM/dd HH:mm:ss zzz")] Found $($ListofSCCMMPs.count) SCCM Mamagement Points" -BackgroundColor DarkBlue -ForegroundColor White
LogWrite -Mylogfile $LogfilePath -MyLogEntry "Found $($ListofSCCMMPs.count) SCCM Mamagement Points"
 
If($ListofSCCMMPs.count -eq 0) {
    Write-Host "[$(Get-Date -Format "yyyy/MM/dd HH:mm:ss zzz")] Unable to discover a MP to download the client from - Exit with Error. 4292" -BackgroundColor DarkRed -ForegroundColor White
    LogWrite -Mylogfile $LogfilePath -MyLogEntry "Unable to discover a MP to download the client from - Exit with Error. 4292"
    Return 4292
}
 
#Convert that list to useable format and then select at random which one to use
$MPS = $ListofSCCMMPs | SELECT @{L="Name";E={$_.properties["name"]}},@{L="dNSHostName";E={$_.properties["dNSHostName"]}},@{L="DistinguishedName";E={$_.properties["distinguishedname"]}},@{L="whenChanged";E={$_.properties["whenChanged"]}},@{L="whenCreated";E={$_.properties["whenCreated"]}}
$MPToUse = $MPS[$(Get-Random -Maximum $MPS.Count)]
Write-Host "[$(Get-Date -Format "yyyy/MM/dd HH:mm:ss zzz")] Randomly selected to use MP: $($MPToUse.dNSHostName)" -BackgroundColor White -ForegroundColor Blue
LogWrite -Mylogfile $LogfilePath -MyLogEntry "Randomly selected to use MP: $($MPToUse.dNSHostName)"
$SCCMClientDownloadURI = "http://$($MPToUse.dNSHostName)/CCM_Client/"
 
#Define Download targets
[String]$Downloadurl = $SCCMClientDownloadURI   #[alias('DownloadPath')]
[String]$DownloadToFolder = 'C:\Temp\CCM_Client'
Write-Host "[$(Get-Date -Format "yyyy/MM/dd HH:mm:ss zzz")] URL to Download From: $Downloadurl" -BackgroundColor White -ForegroundColor Blue
Write-Host "[$(Get-Date -Format "yyyy/MM/dd HH:mm:ss zzz")] Path to Download To: $DownloadToFolder" -BackgroundColor White -ForegroundColor Blue
 
LogWrite -Mylogfile $LogfilePath -MyLogEntry "URL to Download From: $Downloadurl"
LogWrite -Mylogfile $LogfilePath -MyLogEntry "Path to Download To: $DownloadToFolder"
 
#Attempt to download...
try 
{
    if (!(Test-Path -Path $DownloadToFolder)) {
        New-Item -Path $DownloadToFolder -Type Directory -Force -ErrorAction Stop | Out-Null
    }
    
    Do_HTTP_DIR_Download -HTTPFolder $Downloadurl -DownloadPath $DownloadToFolder
 
}
catch {
    Write-Host "[$(Get-Date -Format "yyyy/MM/dd HH:mm:ss zzz")] $($error[0])"
    LogWrite -Mylogfile $LogfilePath -MyLogEntry "$($error[0])"
}
 
 
 
$ClientInstallCommand = "$($DownloadToFolder)\ccmsetup.exe /forceinstall SMSSITECODE=AUTO /source:""$DownloadToFolder"" resetinformationkey=true SMSCACHEFLAGS=PERCENTDISKSPACE SMSCACHESIZE=60"
Write-Host "[$(Get-Date -Format "yyyy/MM/dd HH:mm:ss zzz")] Client Install Command: $ClientInstallCommand" -BackgroundColor DarkBlue -ForegroundColor White
Write-Host "[$(Get-Date -Format "yyyy/MM/dd HH:mm:ss zzz")] Executing Client Install Command..." -BackgroundColor Yellow -ForegroundColor Black
cd $DownloadToFolder
$CommandResult = .\ccmsetup.exe /forceinstall SMSSITECODE=AUTO /source:"$($DownloadToFolder)" resetinformationkey=true SMSCACHEFLAGS=PERCENTDISKSPACE SMSCACHESIZE=60
Write-Host "[$(Get-Date -Format "yyyy/MM/dd HH:mm:ss zzz")] Command Returned: $CommandResult" -BackgroundColor DarkYellow -ForegroundColor Black
 
$CCMSETUPService = Get-Service -Name ccmsetup
If($CCMSETUPService -and $CCMSETUPService.Status -eq "Running") {
    Write-Host "[$(Get-Date -Format "yyyy/MM/dd HH:mm:ss zzz")] The CCMSETUP Service is now running, monitor the log file 'C:\windows\ccmsetup\logs\ccmsetup.log' for status" -BackgroundColor White -ForegroundColor Blue
} Else {
    Write-Host "[$(Get-Date -Format "yyyy/MM/dd HH:mm:ss zzz")] The CCMSETUP Service failed to start, Check the log file 'C:\windows\ccmsetup\logs\ccmsetup.log' for errors" -BackgroundColor DarkRed -ForegroundColor Whote
} 
 
