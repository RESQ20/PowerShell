<#
# *************************************************
# * AUTHOR   : Don Rowland
# * DATE     : January 18, 2019
# * PURPOSE  : Obtain the OS Rules on SCCM 2012 Application Deployment Types 
# *************************************************
 Comments:  This script does require full language mode. Simple method =open Powershell as Admin (start menu -> Powershell -> Right Click -> Run as Adminsitrator)
            This script assumes that the ID you are running it as has DataReader access to the SQL DB for your SCCM Instance
            This script generate a CSV file in the same folder as the script and names it using the script name and appending the start time as execution
#>
param (
    [Parameter(Mandatory,HelpMessage="Enter the SCCM SQL Instance:")] $SCCMSQL = $(throw "`nMissing -SCCMSQL"),
    [Parameter(Mandatory,HelpMessage="Enter the SCCM Site DB Name:")] $SCCMDB = $(throw "`nMissing -SCCMDB")
)

Function LogWrite 
(
   [string] $MyLogfile = (throw "Missing Log File Path"),
   [string] $MylogEntry = (throw "Missing Log Entry")
)
{
	$TimeStamp = Get-Date
	Add-content $MyLogfile -value "$TimeStamp	$MylogEntry"
}

Function GetSQLData
(
    [Parameter(Mandatory=$true)] [string]$SQLInstance = $(throw "`nMissing -SQLInstance"),
    [Parameter(Mandatory=$true)] [string]$SQLDB = $(throw "`nMissing -SQLDB"),
    [Parameter(Mandatory=$true)] [string]$SQLQuery = $(throw "`nMissing -SQLQuery"),
    [Parameter(Mandatory=$true)] [string]$SQLTimeOut = $(throw "`nMissing -SQLTimeOut")
)
{
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $SqlConnection.ConnectionString = "Server = $SQLInstance; Database = $SQLDB; Integrated Security = True; Timeout = $SQLTimeOut"
    
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.CommandText = $SQLQuery
    $SqlCmd.Connection = $SqlConnection
    $SqlCmd.CommandTimeout = 300

    $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
    $SqlAdapter.SelectCommand = $SqlCmd

    $DataSet = New-Object System.Data.DataSet
    $MyReturn = $SqlAdapter.Fill($DataSet)

    $SqlConnection.Close()

    $SearchResult = $DataSet.Tables[0] 
    Return $SearchResult 
    [GC]::Collect()
}


CLS

$MyUser = [Environment]::UserName
$MyDomain = [Environment]::UserDomainName
$MyComputername = [Environment]::MachineName
$MyScriptFullPath = Split-Path $SCRIPT:MyInvocation.MyCommand.Path -parent
$MyScriptName = Split-Path $SCRIPT:MyInvocation.MyCommand.Path -leaf
Write-Host "Executing: 	$MyScriptFullPath\$MyScriptName"
$MyLogFileName = "$MyScriptFullPath\$MyScriptName.log"
$csvFileName = "$MyScriptFullPath\$MyScriptName" + "_" + $(Get-Date -Format yyyyMMdd-HH_mm_ss) + ".csv"
Write-Host "LogFile: $MyLogFileName"
Write-Host "Output: $csvFileName"

LogWrite -MyLogfile $MyLogFileName -MylogEntry "Executing: 	$MyScriptFullPath\$MyScriptName"
LogWrite -MyLogfile $MyLogFileName -MylogEntry "Running AS: $MyDomain\$MyUser on $MyComputername"
LogWrite -MyLogfile $MyLogFileName -MylogEntry "Using Parameters: SCCMSQL = $SCCMSQL   SCCMDB = $SCCMDB"

$SQL_SCCMSITE_Instance = $SCCMSQL
$SQL_SCCMSITE_DB = $SCCMDB
$SQL_GETAllApplications = "SELECT 
	                             vPKG.PackageID
	                             , vPKG.Manufacturer
	                             , vPKG.Name
	                             , vPKG.Version
	                             , vPKG.SecurityKey
	                             , fnCI.CI_ID
	                             , fnCI.ModelName
	                             , fnCI.SDMPackageDigest

                            FROM v_Package vPKG
	                            JOIN fn_ListDeploymentTypeCIs(1033) fnCI ON fnCI.AppModelName = vPKG.SecurityKey
                            ORDER BY vPKG.PackageID
                            "

$SCCM_Applications = GetSQLData -SQLInstance $SQL_SCCMSite_Instance -SQLDB $SQL_SCCMSITE_DB -SQLQuery $SQL_GETAllApplications -SQLTimeOut 300

LogWrite -MyLogfile $MyLogFileName -MylogEntry "Found $($SCCM_Applications.count) Applications"

$current = 0
Foreach($SCCM_Application in $SCCM_Applications) {
    $current = $current + 1
    Write-Host "[$(Get-Date -Format yyyyMMdd-HH:mm:ss)] $current/$($SCCM_Applications.count) `t$($SCCM_Application.PackageID) `t$($SCCM_Application.Manufacturer) $($SCCM_Application.Name) $($SCCM_Application.Version)" -BackgroundColor White -ForegroundColor Blue
    
    $temp = "" | select "TimeStamp", "PackageID", "Manufacture", "Name", "Version", "DeploymentType_OSRule_Count", "DeploymentType_OSRule"

    $temp.TimeStamp = Get-Date -Format yyyyMMdd-HH:mm:ss
    $temp.PackageID = $SCCM_Application.PackageID
    $temp.Manufacture = $SCCM_Application.Manufacturer
    $temp.Name = $SCCM_Application.Name
    $temp.Version = $SCCM_Application.Version
    $temp.DeploymentType_OSRule_Count = $null
    $temp.DeploymentType_OSRule = $null

    $All_DeploymentType_OSRules = $null

    If($SCCM_Application.SDMPackageDigest -like "*OperatingSystemExpression*") {
        [XML]$SDMPackageDigest_XML = $SCCM_Application.SDMPackageDigest
        $DeploymentType_OSRules = $SDMPackageDigest_XML.AppMgmtDigest.DeploymentType.Requirements.Rule.OperatingSystemExpression.Operands.RuleExpression.RuleId
        $temp.DeploymentType_OSRule_Count = $DeploymentType_OSRules.Count
        
        $current = 0
        Foreach($DeploymentType_OSRule in $DeploymentType_OSRules) {
            $current = $current + 1
            If($current -eq 1) {
                $All_DeploymentType_OSRules = $DeploymentType_OSRule
            } Else {
                $All_DeploymentType_OSRules = $All_DeploymentType_OSRules + ',' + $DeploymentType_OSRule
            }
            
            $temp.DeploymentType_OSRule = $DeploymentType_OSRule

            $temp | Export-Csv $csvFileName -Append -noType
        }
        $temp.DeploymentType_OSRule = $All_DeploymentType_OSRules
        
    } Else {
        
    }
    $Temp | Format-List
    $temp = $null
    [GC]::Collect()
}
Write-Host "[$(Get-Date -Format yyyyMMdd-HH:mm:ss)] Script Finished.  Output: $csvFileName"
LogWrite -MyLogfile $MyLogFileName -MylogEntry "Script Finished, CSV Output: $csvFileName"
