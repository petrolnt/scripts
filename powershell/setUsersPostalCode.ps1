#This script was designed for add value to Users AD attribute "PostaCode"
Param(
    [Parameter(Mandatory=$true)]
    [String]$logfile = "c:\script\PostalCodeLog.csv",
    [Parameter(Mandatory=$true)]
    [String]$sourceFile ="c:\script\tabelNumber.xls"
)
#file for writing logs

if(-Not (Test-Path $logfile))
{
	New-Item $logfile -type file
}

#set value to PostalCode attribute
function setPostalCode($accountName, $personalNumber){
	$User = Get-ADUser -Filter {sAMAccountName -eq $accountName} -Properties PostalCode
	$string=""
	if($User -eq $Null)
	{
		$string = "$accountName;user does not exist in AD"
		
	}
	Else 
	{
		$userPostalCode = $User.PostalCode
		if($userPostalCode -eq $null)
		{
			$User.PostalCode=$personalNumber
			Set-ADUser -Instance $User
			$string = "$accountName;Set PostaCode: $personalNumber"
		}
		else
		{
			$string = "$accountName;Postal Code is already defined: $userPostalCode"
		}

	}
	LogWrite -logstring $string
	Write-Output $string
}

#write log
function LogWrite($logstring)
{
   Add-content $Logfile -value $logstring
}

#reading values from excel file

$objExcel=New-Object -ComObject Excel.Application
$objExcel.Visible=$false
$WorkBook=$objExcel.Workbooks.Open($sourceFile)
$worksheet = $workbook.sheets.item("Лист2")
$intRowMax = 150#($worksheet.UsedRange.Rows).count

#set changes for each user in cycle
for($intRow = 1 ; $intRow -le $intRowMax ; $intRow++)
{
	$userLogin = $worksheet.cells.item($intRow, 2).value2
	$tabelNumber = $worksheet.cells.item($intRow, 3).value2
	setPostalCode -accountName $userLogin -personalNumber $tabelNumber
}
$WorkBook.close()
$objExcel.quit()

