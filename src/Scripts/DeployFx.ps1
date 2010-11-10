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
    public System.DateTime StartTime;
    public string ScriptName;
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
		$msg = "Script completed on $env:COMPUTERNAME with success."
		$msgColor = 'Green'
    } else {
		$msg = "Script completed on $env:COMPUTERNAME with ERROR(S)."
		$msgColor = 'Red'
    }
	Write-Output $msg
	Write-Host -ForegroundColor $msgColor $msg
}

############ MAIN BODY


function RunDistributedDeployEngine([string] $environmentFile, [string] $ENV_SETTINGS, [ScriptBlock] $FarmInitialize, [ScriptBlock] $ServerInitialize, [ScriptBlock] $ServerCore, [ScriptBlock] $ServerFinalize, [ScriptBlock] $FarmFinalize)
{
	Write-Progress -Activity "Sprinkler" -Status "Reading configuration" -Id 42
    $context = CreateAndLoadContext $environmentFile $ENV_SETTINGS
	Write-Progress -Activity $context.ScriptName -Status "Setting up" -Id 42 -PercentComplete 1
    OpenLog $context

    trap {
		Write-Progress -Activity $context.ScriptName -Status "Failed" -Id 42 -Completed
		#TODO revise failure handling
		SetMyStatus $context "FAILED"
		DisplaySummaryReport $context
        CloseLogOnError $context
		Write-Progress -Completed
        break #terminate script
    }
    # Now everything is logged
    LoadConfiguration $context
	Write-Progress -Activity $context.ScriptName -Status "Setting up" -Id 42 -PercentComplete 2
	ValidateConfiguration $context
	Write-Progress -Activity $context.ScriptName -Status "Initializing" -CurrentOperation "Waiting for all server to be ready" -Id 42 -PercentComplete 3
	# wait all servers are ready
    Transition-To-BetaState $context
    $context.Succeeded = $true
    if ($context.IAmTheMaster) {
		Write-Progress -Activity $context.ScriptName -Status "Initializing" -CurrentOperation "Generating data files" -Id 42 -PercentComplete 5
		PrepareSettingsFiles $context
		Write-Progress -Activity $context.ScriptName -Status "Initializing" -CurrentOperation "Initializing farm" -Id 42 -PercentComplete 7
		& $FarmInitialize $context
	} else {
		#HACK this works only if we have a Master...
		$context.SettingsFile = Join-Path $context.LogDirectory -ChildPath "$env:COMPUTERNAME\$($context.TargetEnvironment)_settings.xml"
	}
	Write-Progress -Activity $context.ScriptName -Status "Running" -CurrentOperation "Waiting for all server to be ready" -Id 42 -PercentComplete 10
	# wait Farm init finished
    Transition-To-GammaState $context
	Write-Progress -Activity $context.ScriptName -Status "Running" -CurrentOperation "Initializing server" -Id 42 -PercentComplete 15
	# parallel run
    & $ServerInitialize $context
	Write-Progress -Activity $context.ScriptName -Status "Running" -CurrentOperation "Acting on server" -Id 42 -PercentComplete 20
    & $ServerCore $context
	Write-Progress -Activity $context.ScriptName -Status "Finalizing" -CurrentOperation "Finalizing server" -Id 42 -PercentComplete 70
    & $ServerFinalize $context
	# wait all server completed the Core
	Write-Progress -Activity $context.ScriptName -Status "Finalizing" -CurrentOperation "Waiting for all server to complete" -Id 42 -PercentComplete 80
    Transition-To-DeltaState $context
	if ($context.IAmTheMaster) {
		Write-Progress -Activity $context.ScriptName -Status "Finalizing" -CurrentOperation "Finalizing farm" -Id 42 -PercentComplete 90
		& $FarmFinalize $context
		Write-Progress -Activity $context.ScriptName -Status "Finalizing" -CurrentOperation "Removing temporary files" -Id 42 -PercentComplete 95
		RemoveSettingsFiles $context
	}
	Write-Progress -Activity $context.ScriptName -Status "Finalizing" -CurrentOperation "Waiting for all server to complete" -Id 42 -PercentComplete 96
    Transition-To-EpsilonState $context
	Write-Progress -Activity $context.ScriptName -Status "Finalizing" -CurrentOperation "Generating final report" -Id 42 -PercentComplete 99
	DisplaySummaryReport $context
	
    CloseLog $context
	Write-Progress -Activity $context.ScriptName -Status "Done" -Id 42 -PercentComplete 100
	Write-Progress -Activity $context.ScriptName -Status "Done" -Id 42 -Completed
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
#RunDistributedDeployEngine "C:\Users\giuliov\Desktop\distributed\Config\dummy.env" "LOCAL" {param($context) Write-Output "$($context.TargetEnvironment) FarmInitialize"} {param($context) Write-Output "$($context.TargetEnvironment) ServerInitialize"} {param($context) Write-Output "$($context.TargetEnvironment) ServerCore"} {param($context) Write-Output "$($context.TargetEnvironment) ServerFinalize"} {param($context) Write-Output "$($context.TargetEnvironment) FarmFinalize"}
#RunSimpleDeployEngine "C:\Users\giuliov\Desktop\distributed\Config\dummy.env" "LOCAL" {param($context) Write-Output "$($context.TargetEnvironment) DeployCore"}


#EOF#
