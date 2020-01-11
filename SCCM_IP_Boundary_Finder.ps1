<#
# *************************************************
# * AUTHOR   : Don Rowland
# * DATE     : September 28, 2017
# * PURPOSE  : Find the proper site code for a worksation based on its current IP address
# *************************************************
#>

param (
    [Parameter(Mandatory,HelpMessage="Provide IP Address to find a Boundary for:")] $IP, 
    [Parameter(Mandatory,HelpMessage="What SCCM Server do you want to search on:")] $SCCMServer 
)

function Convert-IPv4
{
	param   
    (   
        [Parameter(Mandatory = $true)]   
        [ValidateScript({$_ -match [IPAddress]$_ })]
		[Alias("IP")]
        [String] $IPv4Addr,
		
		[Parameter(Mandatory = $false)]
		[ValidateSet('Binary','Decimal')]
		[String] $To = 'Binary'
    )
	
	$IPv4 = [IPAddress] $IPv4Addr
    
	 if ($To -eq 'Binary')
	 {
    	foreach ($Decimal in $IPv4.GetAddressBytes())
		{
			$Byte = [Convert]::ToString($Decimal,2)
		
			if ($Byte.Length -lt 8)
			{
				for ($i = $Byte.Length; $i -lt 8; $i++)
				{
						$Byte = "0$Byte"
				}
			}
		
			$IPv4_Binary = $IPv4_Binary + $Byte
		}
	
		return $IPv4_Binary
	}
	
	else
	{
		$IPv4_Decimal = 0
		$Byte_Position = 4
		
		foreach ($Decimal in $IPv4.GetAddressBytes())
		{
			$Byte_Position--
			$Byte = [Convert]::ToString($Decimal,2)
			$Bit_Index = $null
			
			foreach ($Bit in $Byte.ToCharArray())
			{
				$Bit_Index++
				$IPv4_Decimal = $IPv4_Decimal + ( [Int]$Bit.ToString() * [Math]::Pow( 2, ( $Byte.Length - $Bit_Index + (8*$Byte_Position) ) ) )
			}
		}
		
		return $IPv4_Decimal
	}
}

CLS
<# Testing stuff
$RemoteComputer = "."
$MyIpaddress = $null
Foreach($IpAddress in (get-wmiobject -ComputerName $RemoteComputer -namespace "root/cimv2" -class "Win32_NetworkAdapterconfiguration" -ErrorAction SilentlyContinue | select * | where{$_.Ipaddress -ne $null}).Ipaddress) { 
    If($IpAddress.substring(0,7) -ne "192.168") {
        $MyIPAddress = $IpAddress 
    }
}
#>

$MyIpAddress = $IP 

Write-host "Searching for IP: $MyIpaddress "

If($MyIpaddress) {

    $SCCMServerName = $SCCMServer 
    $SiteNameSpace = "root\sms\" + (Get-WmiObject -ComputerName $SCCMServerName -Namespace "root\sms" -class "__NAMESPACE" | Select name).name
    Write-Host "SCCM WMI: $SCCMServerName $SiteNameSpace"

    $protocol = "DCOM"
    $cimsess = New-CimSession -ComputerName $SCCMServerName -SkipTestConnection -SessionOption (New-CimSessionOption -Protocol $protocol)

    Write-Host "Cim: Getting SMS_Boundary..."
    $Boundaries = Get-CimInstance -CimSession $cimsess -ClassName SMS_Boundary -Namespace $SiteNameSpace -OperationTimeoutSec 10 
    #$Boundaries | Select DisplayName, Value, DefaultSiteCode, SiteSystems | Format-Table

    $cimsess.Close()
    Write-Host "Searching $($Boundaries.count) boundries..."
    Foreach($Boundary in $Boundaries) {
        $IPRange = $Boundary.value
        $IPRangeStart, $IPRangeEnd = $IPRange.Split("-")
    
        $MyIPinBinary = Convert-IPv4 -IPv4Addr $MyIPAddress -To Binary
        $RangeStartinBinary = Convert-IPv4 -IPv4Addr $IPRangeStart -To Binary
        $RangeEndinBinary = Convert-IPv4 -IPv4Addr $IPRangeEnd -To Binary

        If($MyIPinBinary -ge $RangeStartinBinary -and $MyIPinBinary -le $RangeEndinBinary) {
           Write-host "$MyIPAddress `tYES `t$($Boundary.DefaultSiteCode[1]) `t$IPRange `t $($Boundary.DisplayName) `t$MyIPinBinary -ge $RangeStartinBinary -and $MyIPinBinary -le $RangeEndinBinary" 
           $Boundary | Select * | Format-list
        } Else {
           #Write-host "$MyIPAddress `tNO  `t$($Boundary.DefaultSiteCode[1]) `t$IPRange `t$MyIPinBinary -ge $RangeStartinBinary -and $RangeEndinBinary" 
        }
    }
} Else {
    Write-Host "Invalid IP address"
}
