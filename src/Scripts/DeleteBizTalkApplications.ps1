<#
    Remove all traces of your project from a server
#>
param(
		[Parameter(Mandatory=$true)]
		[string]
    $environmentFile,
		[Parameter(Mandatory=$true)]
		[string]
    $ENV_SETTINGS
)
### Setup variables
#$DebugPreference = "Continue"
#$VerbosePreference = "Continue"
$thisScript = $MyInvocation.MyCommand.Path
$ScriptDir = Split-Path -Parent $thisScript
Write-Debug "ScriptDir = $ScriptDir"
Write-Debug "ThisScript  = $thisScript"

. "$ScriptDir\DeployFx.ps1"
. "$ScriptDir\BizTalk-Actions.ps1"



function DoFarmInitialize($context)
{
    TerminateAllServiceInstances $context
    StopRunningApplications $context
    DeleteApplications $context
    DeleteRulesAndVocabularies $context
}
function DoServerInitialize($context)
{
}
function DoServerCore($context)
{
	RemoveAssembliesFromGAC $context
	UninstallPackages $context
}
function DoServerFinalize($context)
{
}
function DoFarmFinalize($context)
{
}

RunDistributedDeployEngine $environmentFile $ENV_SETTINGS {param($context) DoFarmInitialize $context } {param($context) DoServerInitialize $context } {param($context) DoServerCore $context } {param($context) DoServerFinalize $context } {param($context) DoFarmFinalize $context }

#EOF#