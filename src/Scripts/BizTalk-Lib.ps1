<#
	BizTalk function library
#>

if((test-path "HKLM:\SOFTWARE\Wow6432Node\Microsoft\MSBuild") -eq $True)
{
	 Write-Debug "64 bit Machine"
 
	$BizTalkPath = (Get-ItemProperty  "hklm:SOFTWARE\Wow6432Node\Microsoft\Biztalk Server\3.0\").InstallPath
	$BizTalkPathTracking = $BizTalkPath+"Tracking"
	[System.Reflection.Assembly]::LoadFrom($BizTalkPath +"Developer Tools\Microsoft.BizTalk.ExplorerOM.dll") | Out-Null
	$FrameworkPath=(Get-ItemProperty  "hklm:SOFTWARE\Wow6432Node\Microsoft\.NETFramework\").InstallRoot

    [System.Reflection.Assembly]::LoadFrom( (Join-Path ${env:CommonProgramFiles(x86)} "Microsoft BizTalk\Microsoft.RuleEngine.dll") ) | Out-Null
    [System.Reflection.Assembly]::LoadFrom( (Join-Path ${env:CommonProgramFiles(x86)} "Microsoft BizTalk\Microsoft.Biztalk.RuleEngineExtensions.dll") ) | Out-Null
}
else
{
	Write-Debug "32 bit Machine"
	$BizTalkPath = (Get-ItemProperty  "hklm:SOFTWARE\Microsoft\Biztalk Server\3.0\").InstallPath
	$BizTalkPathTracking = $BizTalkPath+"Tracking"
	[System.Reflection.Assembly]::LoadFrom($BizTalkPath +"Developer Tools\Microsoft.BizTalk.ExplorerOM.dll") | Out-Null
	$FrameworkPath=(Get-ItemProperty  "hklm:SOFTWARE\Microsoft\.NETFramework\").InstallRoot

    [System.Reflection.Assembly]::LoadFrom( (Join-Path $env:CommonProgramFiles "Microsoft BizTalk\Microsoft.RuleEngine.dll") ) | Out-Null
    [System.Reflection.Assembly]::LoadFrom( (Join-Path $env:CommonProgramFiles "Microsoft BizTalk\Microsoft.Biztalk.RuleEngineExtensions.dll") ) | Out-Null
}


$btsConnectionString = "server=.;database=BizTalkMgmtDb;Integrated Security=SSPI";
if ((Test-Path "hklm:SOFTWARE\Microsoft\Biztalk Server\3.0\Administration") -eq $true)
{
	Write-Debug "Found registry entry for BizTalk Management DB."
	$btsDBServer =  (Get-ItemProperty "hklm:SOFTWARE\Microsoft\Biztalk Server\3.0\Administration").MgmtDBServer
	$btsMgmtDB =  (Get-ItemProperty "hklm:SOFTWARE\Microsoft\Biztalk Server\3.0\Administration").MgmtDBName
	$btsConnectionString = "server="+$btsDBServer+";database="+$btsMgmtDB+";Integrated Security=SSPI"
}

Write-Debug "BizTalk connection string is $btsConnectionString"



##########################



function Stop-BizTalkServices
{
	Write-Output "Stopping BizTalk Services"
	Stop-Service -DisplayName "BizTalk Service*"	
}


function Start-BizTalkServices
{
	Write-Output "Starting BizTalk Services"
	Start-Service -DisplayName "BizTalk Service*"	
}


function Start-BizTalkApplication
{ 
	param([string]$appName)
	trap { Write-Output "Error" }

	$exp = New-Object Microsoft.BizTalk.ExplorerOM.BtsCatalogExplorer
	$exp.ConnectionString = $btsConnectionString
	$app = $exp.Applications[$appName]
	
	if($app -eq $null)
	{
		Write-Output "Application " $appName " not found" -fore Red
	}
	else
	{
		
		if($app.Status -ne 1)
		{		
			#full start of application
			$null = $app.Start(63)
			$null = $exp.SaveChanges()
			Write-Output "Started application: " $appName
		}
	}
}


function Stop-BizTalkApplication
{ 
	param([string]$appName)

	$exp = New-Object Microsoft.BizTalk.ExplorerOM.BtsCatalogExplorer
	$exp.ConnectionString = $btsConnectionString
	$app = $exp.Applications[$appName]
	if($app -eq $null)
	{
		Write-Output "Application " $appName " not found"
	}
	else
	{
		if($app.Status -ne 2)
		{
			#full stop of application
			$null = $app.Stop(63)
			$null = $exp.SaveChanges()
			Write-Output "Stopped application: " $appName
		}
	}
}


#depth-first search, as we are guaranteed that it is a graph
function depth-first-visit($n, $L = @())
{
    if (!$n) {
        return $L
    }
        
    Write-Debug "$($n.Name) entered"
    if (! $n.Visited) {
        $n.Visited = $true
        $n.Node.BackReferences | %{
            $ref = $_
            $m = $graph | ?{ $_.Name -eq $ref.Name }
            # could be null: we have reference like BizTalk.System we don't care
            if ($m) {
                Write-Debug "$($m.Name) found"
                depth-first-visit $m $L
            }
        }
        # Write-Debug "Adding $($n.Name)"
        $L += $n
    }
    return $L
}


<#
	Change the application status in correct order
	using depth-first search of application dependency graph
#>
function Set-BizTalkApplicationsStatus
{
    param(
        [string] $namePattern,
        [string[]] $rootApps,
        [switch] $start,
        [switch] $stop
    )
    
    $exp = New-Object Microsoft.BizTalk.ExplorerOM.BtsCatalogExplorer
    $exp.ConnectionString = $btsConnectionString

    $graph = $exp.Applications | where {
        $_.Name -like "$namePattern*"
    } | foreach {
        @{ Name=$_.Name; Node=$_; Visited=$false }
    }

    $startNodes = $graph | where {
        $name = $_.Name
        $rootApps | foreach {
            $name -like "$_*"
        }
    }

    $sortedNodes = $startNodes | %{ depth-first-visit $_ }
    
    if ($sortedNodes -eq $null) {
        Write-Output "No application to change status."
        return $null
    }

    if ($stop) {
        $sortedNodes | foreach {
            Write-Output "Stopping application $($_.Name)"
            $_.Node.Stop(15)
            $exp.SaveChanges()
            Write-Output "$($_.Name) stopped."
        }
    }#if
    if ($start) {
        [Array]::Reverse($sortedNodes)
        $sortedNodes | foreach {
            Write-Output "Starting application $($_.Name)"
            $startFlags = [Microsoft.BizTalk.ExplorerOM.ApplicationStartOption]::StartAll
            $_.Node.Start($startFlags)
            $exp.SaveChanges()
            Write-Output "$($_.Name) started."
        }
    }#if

}#function


function Enlist-Orchestrations([string] $namePattern)
{
    Get-WmiObject MSBTS_Orchestration -Namespace 'root\MicrosoftBizTalkServer' | where {
        $_.Name -like "$namePattern*"
    } | where {
        $_.OrchestrationStatus -eq 2#[Microsoft.BizTalk.ExplorerOM.OrchestrationStatus]::Unenlisted
    } | foreach {
        Write-Output "Enlisting $($_.Name)"
        $_.Enlist() | Out-Null
    }
}


function Start-BizTalkHostInstances([string[]]$servers)
{
    Get-WmiObject MSBTS_HostInstance -Namespace 'root\MicrosoftBizTalkServer' -Filter HostType=1 | where {
        $servers -contains $_.RunningServer } | foreach {
        $_.Start() | Out-Null
        Write-Output "$($_.Name) started"
    }
}


function Stop-BizTalkHostInstances([string[]]$servers)
{
    Get-WmiObject MSBTS_HostInstance -Namespace 'root\MicrosoftBizTalkServer' -Filter HostType=1 | where {
        $servers -contains $_.RunningServer } | foreach {
        $_.Stop() | Out-Null
        Write-Output "$($_.Name) stopped"
    }
}


<#
$hostType = 1  -->  In-process
$hostType = 2  -->  Isolated
#>
function Create-BizTalkHost([string]$hostName, [int]$hostType, [string]$NTGroupName, [bool]$authTrusted, [bool]$isHost32BitOnly = $false, [bool]$isTracking = $false)
{
	[System.Management.ManagementClass]$objHostSettingClass = New-Object System.Management.ManagementClass("root\MicrosoftBizTalkServer","MSBTS_HostSetting",$null)
	[System.Management.ManagementObject]$objHostSetting = New-Object System.Management.ManagementObject
	$objHostSetting = $objHostSettingClass.CreateInstance()
	$objHostSetting["Name"] = $hostName
	$objHostSetting["HostType"] = $hostType
	$objHostSetting["NTGroupName"] = $NTGroupName
	$objHostSetting["AuthTrusted"] = $authTrusted
    $objHostSetting["IsHost32BitOnly"] = $isHost32BitOnly
    $objHostSetting["HostTracking"] = $isTracking
	$putOptions = New-Object System.Management.PutOptions
	$putOptions.Type = [System.Management.PutType]::CreateOnly;
	[Type[]] $targetTypes = New-Object System.Type[] 1
	$targetTypes[0] = $putOptions.GetType()
	$sysMgmtAssemblyName = "System.Management"
	$sysMgmtAssembly = [System.Reflection.Assembly]::LoadWithPartialName($sysMgmtAssemblyName)
	$objHostSettingType = $sysMgmtAssembly.GetType("System.Management.ManagementObject")
	[Reflection.MethodInfo] $methodInfo = $objHostSettingType.GetMethod("Put",$targetTypes)
	$methodInfo.Invoke($objHostSetting,$putOptions) | Out-Null
	Write-Output "Successfully created host named:  $hostName"
}


function Map-BizTalkHostInstance([string]$hostName, [string]$uid, [string]$pwd, [string]$svrName = $env:COMPUTERNAME)
{
    #Build the name of the HostInstance - name has to be in the below format
    #  Name of product + Name of Host of which instance is to be created + Name of Server on which instance is to be created
    [string] $hostInstanceName = "Microsoft BizTalk Server" + " " + $hostName + " " + $svrName
                         
    #Create an instance of the ServerHost class using the System.Management namespace
    [System.Management.ObjectGetOptions] $svrHostOptions = New-Object System.Management.ObjectGetOptions
    [System.Management.ManagementClass]$svrHostClass = New-Object System.Management.ManagementClass("root\MicrosoftBizTalkServer","MSBTS_ServerHost",$null)
    [System.Management.ManagementObject]$svrHostObject = $svrHostClass.CreateInstance()

    #Set the properties of the ServerHost instance
    $svrHostObject["ServerName"] = $svrName
    $svrHostObject["HostName"] = $hostName
                
    #Invoke the Map method of the ServerHost instance
    $svrHostObject.InvokeMethod("Map",$null)

    #Create an instance of the HostInstance class using the System.Management namespace
    [System.Management.ObjectGetOptions] $svrHostOptions = New-Object System.Management.ObjectGetOptions
    [System.Management.ManagementClass]$hostInstClass = New-Object System.Management.ManagementClass("root\MicrosoftBizTalkServer","MSBTS_HostInstance",$hostInstOptions)
    [System.Management.ManagementObject]$hostInstObject = $hostInstClass.CreateInstance()

    #Set the properties of the HostInstance class
    $hostInstObject["Name"] = $hostInstanceName

    #Build a parameter array
    $args = $uid,$pwd
                
    #Invoke the Install method of the HostInstance
    $hostInstObject.InvokeMethod("Install",$args)
	Write-Output "Successfully created host instance named:  $hostInstanceName"
}


function Delete-BizTalkHost([string]$hostName)
{
	[System.Management.ManagementObject]$objHostSetting = New-Object System.Management.ManagementObject
    $objHostSetting.Scope = New-Object System.Management.ManagementScope("root\MicrosoftBizTalkServer")
    $objHostSetting.Path = New-Object System.Management.ManagementPath("MSBTS_HostSetting.Name='$hostName'")
    $objHostSetting.Delete()
	Write-Output "Host $hostName has been deleted successfully."
}


function Set-AdapterReceiveHost([string]$adapter, [string]$hostName)
{
	$putOptions = New-Object System.Management.PutOptions
	$putOptions.Type = [System.Management.PutType]::UpdateOnly;

    # AND is not supported: filter with where
    Get-WmiObject -Namespace "root\MicrosoftBizTalkServer" -query "SELECT * FROM MSBTS_ReceiveHandler WHERE AdapterName='$adapter'" | where {
        $_.HostName -ne $hostName
    } | foreach {
        $_.HostNameToSwitchTo = $hostName
        $_.Put($putOptions) | Out-Null
    }
}


function Set-AdapterSendHost([string]$adapter, [string]$hostName)
{
	$putOptions = New-Object System.Management.PutOptions
	$putOptions.Type = [System.Management.PutType]::UpdateOnly;

    # AND is not supported: filter with where
    Get-WmiObject -Namespace "root\MicrosoftBizTalkServer" -query "SELECT * FROM MSBTS_SendHandler2 WHERE AdapterName='$adapter'" | where {
        $_.HostName -ne $hostName
    } | foreach {
        $_.HostNameToSwitchTo = $hostName
        $_.Put($putOptions) | Out-Null
    }
}


function Set-AdapterHost([string]$adapter, [string]$hostName)
{
    Set-AdapterReceiveHost $adapter $hostName
    Set-AdapterSendHost $adapter $hostName
}


<#
	Delete the applications in correct order
	using depth-first search of application dependency graph
#>
function Delete-BizTalkApplications
{
    param(
        [string] $namePattern,
        [string[]] $rootApps
    )
    
    $exp = New-Object Microsoft.BizTalk.ExplorerOM.BtsCatalogExplorer
    $exp.ConnectionString = $btsConnectionString

    $graph = $exp.Applications | where {
        $_.Name -like "$namePattern*"
    } | foreach {
        @{ Name=$_.Name; Node=$_; Visited=$false }
    }

    $startNodes = $graph | where {
        $name = $_.Name
        $rootApps | foreach {
            $name -like "$_*"
        }
    }

    $sortedNodes = $startNodes | %{ depth-first-visit $_ }
    
    if ($sortedNodes -eq $null) {
        Write-Output "No applications to delete."
        return $null
    }

    $sortedNodes | foreach {
        $BizTalkAppName = $_.Name
        Write-Output "Deleting application $BizTalkAppName"
        
        BTSTask.exe RemoveApp -ApplicationName:$BizTalkAppName

        Write-Output "$BizTalkAppName deleted."
    }

}#function


#EOF#