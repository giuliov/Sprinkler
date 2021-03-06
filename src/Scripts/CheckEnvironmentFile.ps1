<#
#>
param(
		[Parameter(Mandatory=$true)]
		[string]
    $environmentFile
)
### Setup variables
#$DebugPreference = "Continue"
#$VerbosePreference = "Continue"
$thisScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Debug "ThisScriptDir = $thisScriptDir"

. "$thisScriptDir\DeployFx.ps1"

$context = CreateAndLoadContext $environmentFile
LoadConfiguration $context
ValidateConfiguration $context

#EOF#