<#
#>
param(
    [Parameter(Mandatory=$true)]
    [string]
    $environmentFile,
    [Parameter(Mandatory=$true)]
    [alias("Target")]
    [string]
    $ENV_SETTINGS,
    [Parameter(Mandatory=$true)]
    [alias("Source")]
    [string]
    $cleanSettingsFile,
    [Parameter(Mandatory=$true)]
    [string]
    $passwordFile
)
### Setup variables
#$DebugPreference = "Continue"
#$VerbosePreference = "Continue"
$thisScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Debug "ThisScriptDir = $thisScriptDir"

. "$thisScriptDir\DeployFx.ps1"


function DoCore($context)
{
    $settingsDoc = [xml] (Get-Content $cleanSettingsFile)
    $ns = New-Object System.Xml.XmlNamespaceManager $settingsDoc.NameTable
    $ns.AddNamespace("ss", "urn:schemas-microsoft-com:office:spreadsheet")
    
    #target column
    $columns = $settingsDoc.SelectNodes("/ss:Workbook/ss:Worksheet[@ss:Name='Settings']/ss:Table/ss:Row[4]/ss:Cell",$ns)
    $colIndex = 1
    foreach ($col in $columns){
        if ($col.SelectSingleNode("ss:Data[@ss:Type='String']",$ns).InnerText -eq "$($context.TargetEnvironment)_settings.xml") {
            break
        }#if
        $colIndex++
    }
    
	Import-Csv $passwordFile | foreach {
		# lookup
        $settingName = $_.Account
		$passwd = $_.Password
        
        $row = $settingsDoc.SelectSingleNode("/ss:Workbook/ss:Worksheet[@ss:Name='Settings']/ss:Table/ss:Row[ss:Cell[1]/ss:Data[text()='$settingName']]",$ns)
        if ($row -ne $null) {
            #$row.InnerXml
            $cell = $row.SelectSingleNode("ss:Cell[$colIndex]/ss:Data[@ss:Type='String']",$ns)
            if ($cell -ne $null) {
                Write-Host "Before $($cell.OuterXml)"
                $cell.InnerText = $passwd
                Write-Host "After  $($cell.OuterXml)"
            } else {
                $cell = $row.SelectSingleNode("ss:Cell[$colIndex]",$ns)
                Write-Host "Before $($cell.OuterXml)"
                $cell.InnerXml = "<ss:Data ss:Type='String'>$passwd</ss:Data>"
                Write-Host "After  $($cell.OuterXml)"
            }
        }
	}
    
    # save patched doc as Master for the environment (need write access)
    $settingsDoc.Save($context.MasterSettingsFile)
    
    $context.Succeeded = $true
}



function Main()
{
    $context = CreateAndLoadContext $environmentFile $ENV_SETTINGS
    OpenLog $context

    trap {
		DisplaySummaryReport $context
        CloseLogOnError $context
        break #terminate script
    }

    # Now everything is logged
    LoadConfiguration $context
	ValidateConfiguration $context

    $context.Succeeded = $false

	DoCore $context

	DisplaySummaryReport $context

    CloseLog $context
}


Main


#EOF#