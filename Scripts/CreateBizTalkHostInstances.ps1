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
        [alias("Group")]
		[string]
    $HostWindowsGroup,
		[Parameter(Mandatory=$true)]
        [alias("User")]
		[string]
    $HostInstanceLogonUsername,
		[Parameter(Mandatory=$true)]
        [alias("Password")]
		[string]
    $HostInstanceLogonPassword
)

#$DebugPreference = "Continue"
$thisScript = $MyInvocation.MyCommand.Path
$ScriptDir = Split-Path -Parent $thisScript
Write-Debug "ScriptDir = $ScriptDir"
Write-Debug "ThisScript  = $thisScript"

. "$ScriptDir\BizTalk-Lib.ps1"
. "$ScriptDir\DeployFx.ps1"

function DoCore($context)
{
	$hosts = Select-Xml -Xml $context.RawConfiguration -XPath "/environments/roles/role[@name = 'BIZTALK']/host" | foreach { $_.Node }
	#normalize data
	$hosts | foreach {
		$hostName = $_.name
		if ([string]::IsNullOrEmpty($_.is32bit)) {
			$is32bit = $false
		} else {
			$is32bit = [Convert]::ToBoolean($_.is32bit)
		}
		if ([string]::IsNullOrEmpty($_.isTracking)) {
			$isTracking = $false
		} else {
			$isTracking = [Convert]::ToBoolean($_.isTracking)
		}
		
		Create-BizTalkHost $hostName 1 $HostWindowsGroup $false $is32bit $isTracking
		$context.Servers | foreach {
			Map-BizTalkHostInstance $hostName $HostInstanceLogonUsername $HostInstanceLogonPassword $_
		}
		
		$_.handles | foreach {
			$adapter = $_.adapter
			if ([Convert]::ToBoolean($_.receive)) {
				Set-AdapterReceiveHost $adapter $hostName
				Write-Output "Adapter $adapter now uses host $hostName to receive."
			}
			if ([Convert]::ToBoolean($_.send)) {
				Set-AdapterSendHost $adapter $hostName
				Write-Output "Adapter $adapter now uses host $hostName to send."
			}
		}
	}

    $context.Succeeded = $true
}

RunSimpleDeployEngine $environmentFile $ENV_SETTINGS {param($context) DoCore $context }

#EOF#