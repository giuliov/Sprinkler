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


function DoCore($context)
{
    $dataDir = $context.DataDirectory
	$tempDir = Join-Path $context.LogDirectory -ChildPath "Cfgs"
	
	New-Item -Type Directory -Path $tempDir -Force | Out-Null
	& "$($context.ToolsDirectory)\XmlPreprocess.exe" /i:"$dataDir\BTSNTSvc.exe.config" /o:"$tempDir\BTSNTSvc.exe.config" /i:"$dataDir\BTSNTSvc64.exe.config" /o:"$tempDir\BTSNTSvc64.exe.config" /x:"$($context.MasterSettingsFile)" /er:4 /e:"$($context.TargetEnvironment)_settings.xml" | Write-Output
	
	$context.Servers | foreach {
		$serverName = $_	
		#HACK BTS 2009 only!
		$dst = "\\$serverName\c`$\Program Files (x86)\Microsoft BizTalk Server 2009\"
		$src = "$tempDir\BTSNTSvc.exe.config"
		Copy-Item $src $dst -Force
		$src = "$tempDir\BTSNTSvc64.exe.config"
		Copy-Item $src $dst -Force
	}
	
	Remove-Item $tempDir -Force -Recurse

    $context.Succeeded = $true
}


RunSimpleDeployEngine $environmentFile $ENV_SETTINGS {param($context) DoCore $context }

#EOF#