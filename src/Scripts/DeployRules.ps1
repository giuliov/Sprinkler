<#
#>
param(
		[Parameter(Mandatory=$true)]
		[string]
    $environmentFile,
		[Parameter(Mandatory=$true)]
        [alias("Target")]
		[string]
    $ENV_SETTINGS
)
### Setup variables
#$DebugPreference = "Continue"
#$VerbosePreference = "Continue"
$thisScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Debug "ThisScriptDir = $thisScriptDir"

. "$thisScriptDir\DeployFx.ps1"
. "$thisScriptDir\BizTalk-Actions.ps1"


function DoCore($context)
{
	$context.Succeeded = $true

	#CheckBREDeploy $context
	#DeleteRulesAndVocabularies $context

	$BREDir = Join-Path $context.DataDirectory -ChildPath "BRE"

	# deploy updates
	Get-ChildItem $BREDir | foreach {
		$ruleFile = Join-Path $BREDir -ChildPath $_.Name
		& "$($context.ToolsDirectory)\DeployRules.exe" /i "$ruleFile" /d
	    if (! $?) {
			Write-Error "Failed to deploy ruleset $($_.Name)"
			$context.Succeeded = $false
		}
	}
}


RunSimpleDeployEngine $environmentFile $ENV_SETTINGS {param($context) DoCore $context }

#EOF#