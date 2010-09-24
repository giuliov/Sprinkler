<#
	Configuration, Logging & Synch
#>

#general configuration
Set-Variable -Name "TranscriptHosts" -Value @("ConsoleHost") -Option ReadOnly
$script:thisScriptPath = $MyInvocation.MyCommand.Path
$script:thisScriptDir = Split-Path -Parent $script:thisScriptPath

#debug only
$DeployContextClassName = "DeployContext"

$DeployContextSource = @"
using System.Xml;
public class $DeployContextClassName {
    public XmlDocument RawConfiguration;
    public string TargetEnvironment;
    public string LogFile;
    public string LogDirectory;
    public string BaseDirectory;
    public string ConfigDirectory;
    public string ScriptDirectory;
    public string ToolsDirectory;
    public string DataDirectory;
    public string[] Servers;
    public string MasterServer;
    public bool IAmTheMaster;
    public string MyStatusFilename;
    public string[] AllStatusFilenames;
    public string MasterStatusFilename;
    public bool DeployToDB;
    public int PollingInterval;
    public string MasterSettingsFile;
    public string SettingsFile;
    public bool Succeeded;
	public string[] ReportLines = new string[0];
}
"@
if (![Type]::GetType($DeployContextClassName)) {
    Add-Type -TypeDefinition $DeployContextSource -Language CSharpVersion3 -IgnoreWarnings -ReferencedAssemblies "System.Xml.dll"
}


### Context handling
. $script:thisScriptDir/DeployFx-Config.ps1

### Log handling
. $script:thisScriptDir/DeployFx-Log.ps1

### Distributed synchronization
. $script:thisScriptDir/DeployFx-Sync.ps1


### Settings


function PrepareSettingsFiles($context)
{
    Write-Output "Preparing Settings Files"
	
	if (Test-Path $context.MasterSettingsFile) {
		$context.Servers | foreach {
			$server = $_
			Write-Output "Exporting master Settings file $($context.masterSettingsFile) for $server"
			# create per-server subdirectory in log folder (guarantees write access)
			$dir = Join-Path $context.LogDirectory -ChildPath $server
			New-Item -Type Directory -Path $dir -Force | Out-Null
			# export settings
			Write-Output "`"$($context.ToolsDirectory)\EnvironmentSettingsExporter.exe`" `"$($context.MasterSettingsFile)`" `"$dir`" /f:XmlPreprocess2"
			& "$($context.ToolsDirectory)\EnvironmentSettingsExporter.exe" "$($context.MasterSettingsFile)" "$dir" /f:XmlPreprocess2 | Write-Output
			$context.SettingsFile = Join-Path $dir -ChildPath "$($context.TargetEnvironment)_settings.xml"
			# HACK post-processing (using not the name but the filename!)
			Write-Output "`"$($context.ToolsDirectory)\XmlPreprocess.exe`" /i:`"$($context.SettingsFile)`" /x:`"$($context.MasterSettingsFile)`" /er:4 /e:`"$($context.TargetEnvironment)_settings.xml`""
			& "$($context.ToolsDirectory)\XmlPreprocess.exe" /i:"$($context.SettingsFile)" /x:"$($context.MasterSettingsFile)" /er:4 /e:"$($context.TargetEnvironment)_settings.xml" | Write-Output
			Write-Output "Export for $server completed"
		}#for
	} else {
		Write-Error "Master Settings file $($context.MasterSettingsFile) not found."
	}#if
}
function RemoveSettingsFiles($context)
{
    Write-Output "Removing Settings Files"
	
    if (Test-Path $context.MasterSettingsFile) {
		$context.Servers | foreach {
			$server = $_
        	Write-Output "Clean-up of $($context.MasterSettingsFile) exports for $server."
            #HACK DRY
			$dir = Join-Path $context.LogDirectory -ChildPath $server
            Remove-Item $dir -Force -Recurse
        }#for
    }#if
}


function DisplaySummaryReport($context)
{
    Write-Output ""
    Write-Output "****************************"
    Write-Output "*****  SUMMARY REPORT  *****"
    Write-Output "****************************"
    Write-Output ""
	Write-Output $context.ReportLines
    Write-Output ""
    if ($context.Succeeded) {
    	Write-Output "Script completed on $env:COMPUTERNAME with success."
    } else {
    	Write-Output "Script completed on $env:COMPUTERNAME with ERROR(S)."
    }
}

############ MAIN BODY


function RunDistributedDeployEngine([string] $environmentFile, [string] $ENV_SETTINGS, [ScriptBlock] $FarmInitialize, [ScriptBlock] $ServerInitialize, [ScriptBlock] $ServerCore, [ScriptBlock] $ServerFinalize, [ScriptBlock] $FarmFinalize)
{
    $context = CreateAndLoadContext $environmentFile $ENV_SETTINGS
    OpenLog $context

    trap {
		#TODO revise failure handling
		SetMyStatus $context "FAILED"
		DisplaySummaryReport $context
        CloseLogOnError $context
        break #terminate script
    }

    # Now everything is logged
    LoadConfiguration $context
	ValidateConfiguration $context

    Transition-To-BetaState $context

    $context.Succeeded = $true

    if ($context.IAmTheMaster) {
		PrepareSettingsFiles $context
		& $FarmInitialize $context
	} else {
		#HACK this works if we have a Master...
		$context.SettingsFile = Join-Path $context.LogDirectory -ChildPath "$env:COMPUTERNAME\$($context.TargetEnvironment)_settings.xml"
	}

    Transition-To-GammaState $context

    & $ServerInitialize $context
    & $ServerCore $context
    & $ServerFinalize $context

    Transition-To-DeltaState $context

	if ($context.IAmTheMaster) {
		& $FarmFinalize $context
		RemoveSettingsFiles $context
	}

    Transition-To-EpsilonState $context

	DisplaySummaryReport $context
	
    CloseLog $context
}



function RunSimpleDeployEngine([string] $environmentFile, [string] $ENV_SETTINGS, [ScriptBlock] $DeployCore)
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

    PrepareSettingsFiles $context
    
    $context.Succeeded = $false

    & $DeployCore $context

    RemoveSettingsFiles $context

	DisplaySummaryReport $context

    CloseLog $context
}

### DEBUG ONLY
#RunDistributedDeployEngine "C:\temp\dummy.env" "LOCAL" {param($context) Write-Output "$($context.TargetEnvironment) FarmInitialize"} {param($context) Write-Output "$($context.TargetEnvironment) ServerInitialize"} {param($context) Write-Output "$($context.TargetEnvironment) ServerCore"} {param($context) Write-Output "$($context.TargetEnvironment) ServerFinalize"} {param($context) Write-Output "$($context.TargetEnvironment) FarmFinalize"}
#RunSimpleDeployEngine "C:\temp\dummy.env" "LOCAL" {param($context) Write-Output "$($context.TargetEnvironment) DeployCore"}


#EOF#
