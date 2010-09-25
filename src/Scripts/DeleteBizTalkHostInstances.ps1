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
		[string]
    $NewHost = "BizTalkServerApplication"
)

#$DebugPreference = "Continue"
$thisScript = $MyInvocation.MyCommand.Path
$ScriptDir = Split-Path -Parent $thisScript
Write-Debug "ScriptDir = $ScriptDir"
Write-Debug "ThisScript  = $thisScript"

. "$ScriptDir\DeployFx.ps1"
. "$ScriptDir\BizTalk-Actions.ps1"

function DoCore($context)
{
	StopRunningApplications
	Stop-BizTalkHostInstances $context.Servers

	$hosts = Select-Xml -Xml $context.RawConfiguration -XPath "/environments/roles/role[@name = 'BIZTALK']/host" | foreach { $_.Node }
	$hosts | foreach {
		$hostName = $_.name
		
		$_.handles | foreach {
			$adapter = $_.adapter
			if ($_.receive) {
				Set-AdapterReceiveHost $adapter $NewHost
				Write-Output "Adapter $adapter now uses host $NewHost to receive."
			}
			if ($_.send) {
				Set-AdapterSendHost $adapter $NewHost
				Write-Output "Adapter $adapter now uses host $NewHost to send."
			}
		}
		
		Delete-BizTalkHost $hostName
	}

    $context.Succeeded = $true
}

RunSimpleDeployEngine $environmentFile $ENV_SETTINGS {param($context) DoCore $context }

#EOF#