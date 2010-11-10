#$DebugPreference = "Continue"
$thisScript = $MyInvocation.MyCommand.Path
$ScriptDir = Split-Path -Parent $thisScript
Write-Debug "ScriptDir = $ScriptDir"
Write-Debug "ThisScript  = $thisScript"

. "$ScriptDir\Powershell3264.ps1"
. "$ScriptDir\BizTalk-Lib.ps1"
. "$ScriptDir\Update-DeploymentStatus.ps1"


function TerminateAllServiceInstances($context)
{
	Write-Output "Terminating service instances"
    
    # get data from environment file (DRY)
    $hosts = Select-Xml -Xml $context.RawConfiguration -XPath "/environments/roles/role[@name = 'BIZTALK']/host" | foreach { $_.Node }
    $ourHostNames = $hosts | foreach {
        if ($_.also32bit) {
            $_.name, ($_.name + "32")
        } else {
            $_.name
        }
    }
    $servers = $context.Servers

    $serviceInstances = [WMISEARCHER] "SELECT * FROM MSBTS_ServiceInstance"
    $serviceInstances.scope = "root\MicrosoftBizTalkServer"
    $serviceInstances.Get() | where {
        $ourHostNames -contains $_.HostName } | where {
        $servers -contains $_.__SERVER } | where {
        $_.ServiceClass -ne 16 } | foreach {
        Write-Output "Terminating instance $($_.InstanceID) on $($_.HostName) / $($_.__SERVER)"
        $_.Terminate() | Out-Null
    }

	Write-Output "Service instances terminated."
}

function StopRunningApplications($context)
{
	Write-Output "Stopping running applications"
    if (Test-Win32) {
        StopRunningApplications_Core $context
    } else {
        # Trick: REENTER powershell forcing 32 bit instance
    	Exec-Script32 $thisScript StopRunningApplications_Core $context
    }
	Write-Output "Applications stopped."
}

function StopRunningApplications_Core($context)
{
	$pattern = $context.RawConfiguration.environments.configuration.BizTalk.ApplicationsPattern
	$rootApps = $context.RawConfiguration.environments.configuration.BizTalk.ApplicationsRoot
	Set-BizTalkApplicationsStatus $pattern @($rootApps) -stop
}

function StartRunningApplications($context)
{
	Write-Output "Starting running applications"
    if (Test-Win32) {
        StartRunningApplications_Core $context
    } else {
        # Trick: REENTER powershell forcing 32 bit instance
    	Exec-Script32 $thisScript StartRunningApplications_Core $context
    }
	Write-Output "Applications started."
}

function StartRunningApplications_Core($context)
{
	$pattern = $context.RawConfiguration.environments.configuration.BizTalk.ApplicationsPattern
	$rootApps = $context.RawConfiguration.environments.configuration.BizTalk.ApplicationsRoot
    Enlist-Orchestrations $pattern
	Set-BizTalkApplicationsStatus $pattern @($rootApps) -start
}



function BounceServices()
{
	Stop-BizTalkServices
	Start-BizTalkServices
	Write-Output "BTS Services bounced."
}



function LimitHostInstances($context)
{
	Write-Output "Limiting HostInstances"

	$servers = $context.Servers | Select-Object -Skip 1
	Stop-BizTalkHostInstances $servers
	
	Write-Output "HostInstances done."
}



function LimitHostInstancesAndRestartServices($context)
{
	Write-Output "Stopping HostInstances on all servers"
	$servers = $context.Servers
	Stop-BizTalkHostInstances $servers
	Write-Output "HostInstances stopped."
	Write-Output "Starting HostInstances on first servers"
	Start-BizTalkHostInstances $servers[0]
	Write-Output "HostInstances started."
}


function UpdateDeploymentStatus($context)
{
	$dropURL = $context.RawConfiguration.environments.configuration.CentralMonitor.Url
    $domain = $context.RawConfiguration.environments.configuration.CentralMonitor.Credentials.Domain
    $user = $context.RawConfiguration.environments.configuration.CentralMonitor.Credentials.User
    $password = $context.RawConfiguration.environments.configuration.CentralMonitor.Credentials.Password
    $cred = New-Object System.Net.NetworkCredential $user,$password,$domain
    # call web service
	Update-DeploymentStatus $dropURL $context.LogDirectory $cred
}



function CheckBREDeploy($context)
{
	Write-Output "Checking BRE deployment"
    if (Test-Win32) {
        CheckBREDeploy_Core $context
    } else {
        # Trick: REENTER powershell forcing 32 bit instance
    	Exec-Script32 $thisScript CheckBREDeploy_Core $context
    }
	Write-Output "BRE passed."
}

# this code runs only at 32 bits
function CheckBREDeploy_Core($context)
{
    $dd = New-Object Microsoft.BizTalk.RuleEngineExtensions.RuleSetDeploymentDriver
    $rs = $dd.GetRuleStore()
	
	$nonCustomRuleVersion = $context.RawConfiguration.environments.configuration.BizTalk.Rules.Version
    #HACK: hardcoded values
    $stdRules = "ESB.*"
    $stdVocab = "ESB.*","Common Sets","Common Values","Functions","Predicates"
    
    # 0 = Filter.All
    $rs.GetRuleSets(0) | where {
        $name = $_.Name
        $all = $true
        $stdRules | %{ $all = $all -and $name -notlike $_ }
        $all
    } | where {
        "$($_.MajorRevision).$($_.MinorRevision)" -ne $nonCustomRuleVersion
    } | foreach {
        Write-Error "RuleSet $($_.Name) $($_.MajorRevision).$($_.MinorRevision) has been changed: deploy will stop."
    }
    
    $rs.GetVocabularies(0) | where {
        $name = $_.Name
        $all = $true
        $stdVocab | %{ $all = $all -and $name -notlike $_ }
        $all
    } | where {
        "$($_.MajorRevision).$($_.MinorRevision)" -ne $nonCustomRuleVersion
    } | foreach {
        Write-Error "Vocabulary $($_.Name) $($_.MajorRevision).$($_.MinorRevision) has been changed: deploy will stop."
    }
}



function DeleteApplications($context)
{
	Write-Output "Deleting Applications"
    if (Test-Win32) {
        DeleteApplications_Core $context
    } else {
        # Trick: REENTER powershell forcing 32 bit instance
    	Exec-Script32 $thisScript DeleteApplications_Core $context
    }
	Write-Output "Applications deleted."
}

function DeleteApplications_Core($context)
{
	$pattern = $context.RawConfiguration.environments.configuration.BizTalk.ApplicationsPattern
	$rootApps = $context.RawConfiguration.environments.configuration.BizTalk.ApplicationsRoot
    Delete-BizTalkApplications $pattern @($rootApps)
}



function DeleteRulesAndVocabularies($context)
{
	Write-Output "Deleting Rules and Vocabularies"
    if (Test-Win32) {
        DeleteRulesAndVocabularies_Core $context
    } else {
        # Trick: REENTER powershell forcing 32 bit instance
    	Exec-Script32 $thisScript DeleteRulesAndVocabularies_Core $context
    }
	Write-Output "Rules and Vocabularies deleted."
}

function DeleteRulesAndVocabularies_Core($context)
{
    $dd = New-Object Microsoft.BizTalk.RuleEngineExtensions.RuleSetDeploymentDriver
    $rs = $dd.GetRuleStore()
        
    #HACK: hardcoded values
    $stdRules = "ESB.*"
    $stdVocab = "ESB.*","Common Sets","Common Values","Functions","Predicates"
    
    # 0 = Filter.All
    $rs.GetRuleSets(0) | where {
        $name = $_.Name
        $all = $true
        $stdRules | %{ $all = $all -and $name -notlike $_ }
        $all
    } | foreach {
        $dd.Undeploy($_)
        Write-Output "Rule $name undeployed"
        $rs.Remove($_)
        Write-Output "Rule $name deleted"
    }
    
    $rs.GetVocabularies(0) | where {
        $name = $_.Name
        $all = $true
        $stdVocab | %{ $all = $all -and $name -notlike $_ }
        $all
    } | foreach {
        $rs.Remove($_)
        Write-Output "Vocabulary $name deleted"
    }
}



function RemoveAssembliesFromGAC($context)
{
	Write-Output "Removing assemblies from GAC"
    
    $toolDirectory = $context.ToolsDirectory
	$patterns = @($context.RawConfiguration.environments.configuration.GAC.Pattern)

	# get list of all GAC'ed assemblies
    $gac = (& "$toolDirectory\gacutil.exe" /l /nologo | foreach { $_.Trim() })
	# select matching
	$gac = $patterns | foreach {
		$pattern = $_
		$gac | where { $_ -like $pattern }
	}#for
    Set-Content "$env:TEMP\GACassemblies.txt" $gac
	# un-GAC assemblies in list
    & "$toolDirectory\gacutil.exe" /ul "$env:TEMP\GACassemblies.txt" /nologo | Write-Output

	Write-Output "GAC cleaned."
}



function UninstallPackages($context)
{
    Write-Output "Retrieving installed products"
    $installedProducts = Get-WmiObject -Query "SELECT * FROM Win32_Product" -namespace "root\CIMV2"
    Write-Output "  Found $($installedProducts.Count) products."
	
    $patterns = @($context.RawConfiguration.environments.configuration.Installer.Pattern)
	
	# select matching
	$installedProducts = $patterns | foreach {
		$pattern = $_
		$installedProducts | where { $_.Name -like $pattern }
	}#for


    if ($installedProducts -eq $null) {
        Write-Output "No packages to uninstall."
    } else {
		$installedProducts | foreach {
			Write-Output "Uninstalling $($_.Name)"
			$_.Uninstall() | Out-Null        
		}
		Write-Output "All packages uninstalled."
	}
}



#this allow re-entrance to 32bit from a 64bit
if ($Args.Count -gt 0)
{
	Write-Verbose "### Called from 64-bit shell"
	$dataFilename = $Args[0]
	Write-Verbose "### dataFilename is '$dataFilename'"
	$scriptArgs = Import-Clixml -Path $dataFilename
	Write-Verbose "### $($scriptArgs.Count) scriptArg(s):"
	$scriptArgs | foreach { Write-Verbose $_ }
	Write-Verbose "### scriptArgs ended."
	$functionToInvoke = $scriptArgs[0]
	$context = $scriptArgs[1]
	Write-Verbose "### Invoking $functionToInvoke"
    & $functionToInvoke $context
	Write-Verbose "### Returning from 32-bit"
}

#EOF#