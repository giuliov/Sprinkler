#$DebugPreference = "Continue"
#$VerbosePreference = "Continue"
#$WarningPreference = "Continue"
$thisScriptPath = $MyInvocation.MyCommand.Path
$thisScriptDir = Split-Path -Parent $thisScriptPath
Write-Debug "ThisScriptPath  = $thisScriptPath"
Write-Debug "ThisScriptDir = $thisScriptDir"


Write-Host "Sprinkler 0.9.2" -ForegroundColor Cyan
Write-Host ""


Add-Type -TypeDefinition "public class ExitScriptType {public bool Dummy; }"


<#
$prompt is the question to the user
$choices is an hash with
    key = single character that represent menu choice
    prompt = descriptive menu choice
    value = the value to return; a scriptblock is executed, ExitScriptType quits the script
#>
function Read-HostMenuChoice([string]$prompt, $choices)
{
    Write-Host $prompt
    $choices | foreach {
        Write-Host "  $($_.key)) $($_.prompt)"
    }
    do {
        $choice = Read-Host
        $result = $choices | where { $_.key -eq $choice } | foreach {
            if ($_.value -eq [ExitScriptType]) {
                throw "User exited the script."
            } elseif ($_.value -is [scriptblock]) {
                & $_.value
            } else {
                $_.value
            }
        }
        if ($result -eq $null) {
            Write-Host "Invalid choice: please, select again"
        }
    } while ($result -eq $null)
    return $result
}


function Read-EnvironmentTarget()
{
    $environmentMenu = @( @{ key=0; prompt="<exit this script>"; value=[ExitScriptType] } )
    Get-ChildItem (Join-Path $thisScriptDir "..\Config\*.env") | foreach {
        $environmentMenu += @{ key=$environmentMenu.Length; prompt=$_.Name; value=$_.FullName }
    }
    $environmentMenu += @{ key=9; prompt="<type path to file>"; value={Read-Host} }

    # loop on 9 when missing file
	do {
		$environmentFile = Read-HostMenuChoice "Select the environments file:" $environmentMenu
		Write-Debug "Chosen '$environmentFile' (Exists? $(Test-Path $environmentFile))"
	} until (Test-Path $environmentFile)

    #HACK DRY parse file to get possible TARGETs
    [xml]$environments = Get-Content $environmentFile
    $targetEnvironments = Select-Xml -Xml $environments -XPath "/environments/environment/@name" | foreach { $_.Node.Value }

	if ($targetEnvironments -is [string]) {
		# no choices
		$targetEnvironment = $targetEnvironments
	} else {
	    $targetMenu = @( @{ key=0; prompt="<exit this script>"; value=[ExitScriptType] } )
	    $targetEnvironments | foreach {
	        $targetMenu += @{ key=$targetMenu.Length; prompt=$_; value=$_ }
	    }
	    $targetEnvironment = Read-HostMenuChoice "Select the target environment:" $targetMenu
	}#if
    Write-Debug "Chosen '$targetEnvironment'"
		
	if ($targetEnvironment -ieq 'LOCAL' -and [string]::IsNullOrEmpty($env:DevSqlName)) {
		Write-Warning "Environment variable DevSqlName must be defined for deployment to work!"
	}

    
    return @{ File = $environmentFile; Target = $targetEnvironment }
}


$task = Read-HostMenuChoice "Select the task:" @(
     @{ key=0; prompt="<exit this script>"; value=[ExitScriptType] }
    ,@{ key=1; prompt="Add missing bits"; value={
        Join-Path $thisScriptDir -ChildPath "_InstallMissingBits.ps1"
        }}
    ,@{ key=2; prompt="Create the BizTalk host instances"; value={
        $scriptToLaunch = Join-Path $thisScriptDir -ChildPath "CreateBizTalkHostInstances.ps1" 
        $environment = Read-EnvironmentTarget
        $HostWindowsGroup = Read-Host "Host Windows Group"
        $HostInstanceLogonUsername = Read-Host "Username"
        $HostInstanceLogonPassword = Read-Host "Password"
        return "$scriptToLaunch '$($environment.File)' $($environment.Target) '$HostWindowsGroup' '$HostInstanceLogonUsername' '$HostInstanceLogonPassword'"
        }}
    ,@{ key=3; prompt="Download the most recent build"; value={
        $scriptToLaunch = Join-Path $thisScriptDir -ChildPath "_GetLatestDrop.ps1"
        $destinationFolder = Read-Host "Destination folder"
        $shareName = Read-HostMenuChoice "Select the share:" @(
             @{ key=0; prompt="<exit this script>"; value=[ExitScriptType] }
            ,@{ key=1; prompt="Latest Main build"; value="DailyLatest" }
            ,@{ key=2; prompt="Latest build from Core Team"; value="CoreTeamLatest" }
            ,@{ key=3; prompt="Latest build from Avanade Team"; value="AvanadeLatest" }
            ,@{ key=4; prompt="Other Main build"; value="OtherMain" }			
            ,@{ key=9; prompt="<other>"; value={Read-Host} }
        )
		#HACK
        if ($shareName -eq "OtherMain") {
            $shareFolder = Read-Host "Share folder"
        } else {
            $shareFolder = ""
        }
		#HACK change the script to read configuration!
        $dropURL = "http://drops.dnbshas.com/"
        return "$scriptToLaunch '$destinationFolder' $dropURL $shareName $shareFolder"
        }}
    ,@{ key=4; prompt="Scratch all Applications and BRE"; value={
        $scriptToLaunch = Join-Path $thisScriptDir -ChildPath "DeleteBizTalkApplications.ps1"
        $environment = Read-EnvironmentTarget
        return "$scriptToLaunch '$($environment.File)' $($environment.Target)"
        }}
    ,@{ key=5; prompt="Quick Deploy/Upgrade to the most recent build (BAM included)"; value={
        $scriptToLaunch = Join-Path $thisScriptDir -ChildPath "ServerDeploy.ps1"
        $environment = Read-EnvironmentTarget
        return "$scriptToLaunch '$($environment.File)' $($environment.Target) -Mode UPGRADE"
        }}
    ,@{ key=6; prompt="Quick Deploy/Upgrade to the most recent build (BAM excluded)"; value={
        $scriptToLaunch = Join-Path $thisScriptDir -ChildPath "ServerDeploy.ps1"
        $environment = Read-EnvironmentTarget
        return "$scriptToLaunch '$($environment.File)' $($environment.Target) -Mode UPGRADE -CustomDeployParameters ';IncludeBAM=false' -CustomUndeployParameters ';SkipBamUndeploy=true'"
        }}
    ,@{ key=7; prompt="Undeploy followed by Full Deploy to the most recent build (BAM included)"; value={
        $scriptToLaunch = Join-Path $thisScriptDir -ChildPath "ServerDeploy.ps1"
        $environment = Read-EnvironmentTarget
        return "$scriptToLaunch '$($environment.File)' $($environment.Target) -Mode BOTH"
        }}
    ,@{ key=8; prompt="Finalize the deploy only (after some failure)"; value={
        $scriptToLaunch = Join-Path $thisScriptDir -ChildPath "ServerDeploy.ps1"
        $environment = Read-EnvironmentTarget
        return "$scriptToLaunch '$($environment.File)' $($environment.Target) -Mode FINALIZE"
        }}
    ,@{ key='C'; prompt="Deploy BizTalk Server's configuration file"; value={
        $scriptToLaunch = Join-Path $thisScriptDir -ChildPath "ApplyBizTalkConfig.ps1" 
        $environment = Read-EnvironmentTarget
        return "$scriptToLaunch '$($environment.File)' $($environment.Target)"
        } }
    ,@{ key='D'; prompt="Delete the BizTalk host instances"; value={
        $scriptToLaunch = Join-Path $thisScriptDir -ChildPath "DeleteBizTalkHostInstances.ps1"
        $environment = Read-EnvironmentTarget
        return "$scriptToLaunch '$($environment.File)' $($environment.Target)"
        }}
    ,@{ key='E'; prompt="Check an environment file"; value={
        $scriptToLaunch = Join-Path $thisScriptDir -ChildPath "CheckEnvironmentFile.ps1" 
        $environment = Read-EnvironmentTarget
        return "$scriptToLaunch '$($environment.File)'"
        } }
    ,@{ key='P'; prompt="Edit the settings file's password"; value={
        $scriptToLaunch = Join-Path $thisScriptDir -ChildPath "_SetPasswordsInSettingsFile.ps1" 
        $environment = Read-EnvironmentTarget
        $cleanSettingsFile = Read-Host "Clean environment settings file"
        $passwordFile = Read-Host "Password file (*.CSV)"
        return "$scriptToLaunch '$($environment.File)' $($environment.Target) $($cleanSettingsFile) $($passwordFile)"
        } }
    ,@{ key='R'; prompt="(Re-)deploy all the rules in the ./Data/BRE folder"; value={
        $scriptToLaunch = Join-Path $thisScriptDir -ChildPath "DeployRules.ps1" 
        $environment = Read-EnvironmentTarget
        return "$scriptToLaunch '$($environment.File)' $($environment.Target)"
        } }
)

Write-Host "About to execute"
Write-Host "  ==> $task <=="
$yesNo = Read-Host "Run it? [Y]es,[N]o"
if ("Y","y" -contains $yesNo) {
    Write-Host ""
    Invoke-Expression $task
}

#EOF#