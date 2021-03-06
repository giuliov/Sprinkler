<#
	Library of (Un)Deploy actions
#>

#HACK this should come from configuration
$MSBuild = "$env:windir\Microsoft.NET\Framework\v2.0.50727\MSBuild.exe"


function MsiInstall([string] $msiPath)
{
    Write-Output "      Installing $msiPath on $env:COMPUTERNAME"
    
    $prod = [wmiclass]"\\.\root\CIMV2:Win32_Product"
    if (!$WhatIfPreference) {
        $rc = $prod.Install($msiPath, $null, $True).ReturnValue
        if ($rc -ne 0) {
            Write-Error "      Install of $msiPath on $env:COMPUTERNAME failed with code $rc."
        } else {
            Write-Output "      Install of $msiPath on $env:COMPUTERNAME succeeded."
            $script:actionSucceeded = $true
        }
    }
}



function OtherDeploy($package, [string] $envSettings, [string] $settingsFile, [bool] $deployToDB)
{
	# HACK won't work on a 32bit server
    $scriptPath = "C:\Program Files (x86)\$($package.fullName)\Deploy\$($package.name).Deploy.ps1"

    Write-Output "      Executing deploy script for '$($package.name)' on $env:COMPUTERNAME"
    if (!$WhatIfPreference) {
        & $scriptPath $envSettings $settingsFile $deployToDB | Write-Output
        $script:actionSucceeded = $?
    }
    Write-Output "      Deploy script for '$($package.name)' on $env:COMPUTERNAME completed."
}


function OtherUndeployAndUninstall($package, [string] $envSettings, [string] $settingsFile, [bool] $deployToDB)
{
	# HACK won't work on a 32bit server
    $scriptPath = "C:\Program Files (x86)\$($package.fullName)\Deploy\$($package.name).Undeploy.ps1"

    Write-Output "      Undeploying $($package.name) from $env:COMPUTERNAME"
    
	$productId = $package.productId
	
    $prod = $script:installedProducts | where { $_.Name -like "$productId*" }
    if ($prod -eq $null) {
        # not found
        Write-Output "      Product '$productId' not found: undeploy and uninstall are not needed." 
        $script:actionSucceeded = $true
    } else {
        Write-Verbose "      $productId is installed, will run undeploy script"

        if (!$WhatIfPreference) {
            & $scriptPath $envSettings $settingsFile $deployToDB | Write-Output
            $script:actionSucceeded = $?
        }

        if ($prod -eq $null) {
            Write-Error "      Internal error: lost WMI object"
        } elseif (!$WhatIfPreference) {
			$uninstallRes = $prod.Uninstall()
			if ($uninstallRes -eq $null) {
				Write-Warning "      No Uninstall result"
			} else {
				$rc = $uninstallRes.ReturnCode
    			if ($rc -eq $null) {
    				Write-Warning "      No Uninstall return code"
				} elseif ($rc -eq 0) {
					Write-Output "      Uninstall succeeded."
				} else {
					Write-Error "      Uninstall failed with $rc"
                    $script:actionSucceeded = $false
				}
            }
        }
    }#if
    Write-Output "      Undeploy of $($package.name) from $env:COMPUTERNAME completed."
}



function BiztalkDeploymentFrameworkDeploy([string] $applicationId, [string] $effectiveVersion, [string] $envSettings, [string] $settingsFile, [bool] $deployToDB)
{
    Write-Output "      Executing Biztalk deploy script for $applicationId on $env:COMPUTERNAME"
    
    if (!$WhatIfPreference) {

		$prodVer = GetProductVersionFromVersion($effectiveVersion)
		Write-Verbose "      script version is $prodVer"
	
        #HACK $prodVer depends on side-by-side flag and x64 OS
        Set-Location "C:\Program Files (x86)\$applicationId\$prodVer\Deployment"
        $env:BT_DEPLOY_MGMT_DB = $deployToDB
        if ($settingsFile -eq '') {
			Write-Output "      Warning: using local settings file"
            $env:ENV_SETTINGS = "EnvironmentSettings\$($envSettings)_settings.xml"
            Framework\DeployTools\EnvironmentSettingsExporter.exe EnvironmentSettings\SettingsFileGenerator.xml EnvironmentSettings | Write-Output
        } else {
            $env:ENV_SETTINGS = $settingsFile
        }
        # application and IIS management are done globally: we manage dependencies and is faster
        $MSBuild_Properties = "/p:DeployBizTalkMgmtDB=$deployToDB;Configuration=Server;SkipUndeploy=true;StartApplicationOnDeploy=false;SkipBounceBizTalk=true"
        $MSBuild_Properties += $CustomDeployParameters
        $MSBuild_Logging = "/l:FileLogger,Microsoft.Build.Engine;logfile=..\DeployResults\DeployResults.txt"
        $MSBuild_Script = "$applicationId.Deployment.btdfproj"
        Write-Output "$MSBuild $MSBuild_Properties $MSBuild_Logging $MSBuild_Script"
        & $MSBuild $MSBuild_Properties $MSBuild_Logging $MSBuild_Script | Write-Output
        $script:actionSucceeded = $?
        $now = Get-Date -f "yyyyMMdd-HHmm"
        Copy-Item "..\DeployResults\DeployResults.txt" "..\DeployResults\DeployResults_$env:COMPUTERNAME_$now.txt"
    }

    Write-Output "      Biztalk deploy script for $applicationId on $env:COMPUTERNAME completed."
}


function BiztalkDeploymentFrameworkUndeployAndUninstall([string] $applicationId, [string]$productId, [string] $envSettings, [string] $settingsFile, [bool] $deployToDB)
{
    Write-Output "      Undeploying $applicationId from $env:COMPUTERNAME"

    $prod = $script:installedProducts | where { $_.Name -like "$productId*" }
    if ($prod -eq $null) {
        # not found
        Write-Output "      Product $applicationId not found: undeploy and uninstall are not needed." 
        $script:actionSucceeded = $true
    } else {
		$prodVer = GetProductVersionFromInstalledProduct($prod)
		Write-Verbose "      $applicationId v$prodVer is installed."

        #HACK use of $prodVer depends on side-by-side flag and x64 OS
		Set-Location "C:\Program Files (x86)\$applicationId\$prodVer\Deployment"
		$env:BT_DEPLOY_MGMT_DB=$deployToDB
        if ($settingsFile -eq '') {
			Write-Output "      Warning: using local settings file"
            $env:ENV_SETTINGS = "EnvironmentSettings\$($envSettings)_settings.xml"
    		if (!$WhatIfPreference) {
                Framework\DeployTools\EnvironmentSettingsExporter.exe EnvironmentSettings\SettingsFileGenerator.xml EnvironmentSettings | Write-Output
            }
        } else {
            $env:ENV_SETTINGS = $settingsFile
        }
		if (!$WhatIfPreference) {
            $MSBuild_Properties = "/p:DeployBizTalkMgmtDB=$deployToDB;Configuration=Server;SkipBounceBizTalk=true"
            $MSBuild_Properties += $CustomUndeployParameters
            $MSBuild_Target = "/target:Undeploy"
            $MSBuild_Logging = "/l:FileLogger,Microsoft.Build.Engine;logfile=..\DeployResults\DeployResults.txt"
            $MSBuild_Script = "$applicationId.Deployment.btdfproj"
            Write-Output "$MSBuild $MSBuild_Properties $MSBuild_Target $MSBuild_Logging $MSBuild_Script"
            & $MSBuild $MSBuild_Properties $MSBuild_Target $MSBuild_Logging $MSBuild_Script | Write-Output
            $script:actionSucceeded = $?
            $now = Get-Date -f "yyyyMMdd-HHmm"
            Copy-Item "..\DeployResults\DeployResults.txt" "..\DeployResults\DeployResults_$env:COMPUTERNAME_$now.txt"
		}

		if ($prod -eq $null) {
			Write-Error "      Internal error: lost WMI object"
		} elseif (!$WhatIfPreference) {
			$uninstallRes = $prod.Uninstall()
			if ($uninstallRes -eq $null) {
                Write-Warning "      No Uninstall result"
			} else {
				$rc = $uninstallRes.ReturnCode
				if ($rc -eq $null) {
                    Write-Warning "      No Uninstall return code"
				} elseif ($rc -eq 0) {
                    Write-Output "      Uninstall succeeded."
				} else {
                    Write-Error "      Uninstall failed with $rc"
                    $script:actionSucceeded = $false
				}
			}
		}
	}

    Write-Output "      Undeploy of $applicationId from $env:COMPUTERNAME completed."
}


function LoadSQLSnapIn()
{
    #
    # Add the SQL Server provider.
    #
    $ErrorActionPreference = "Stop"
    $sqlpsreg="HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.SqlServer.Management.PowerShell.sqlps"
    if (Get-ChildItem $sqlpsreg -ErrorAction "SilentlyContinue")
    {
        throw "SQL Server Provider is not installed."
    }
    else
    {
        $item = Get-ItemProperty $sqlpsreg
        $sqlpsPath = [System.IO.Path]::GetDirectoryName($item.Path)
    }

    #
    # Set mandatory variables for the SQL Server rovider
    #
    Set-Variable -scope Global -name SqlServerMaximumChildItems -Value 0
    Set-Variable -scope Global -name SqlServerConnectionTimeout -Value 30
    Set-Variable -scope Global -name SqlServerIncludeSystemObjects -Value $false
    Set-Variable -scope Global -name SqlServerMaximumTabCompletion -Value 1000

    #
    # Load the snapins, type data, format data
    #
    Push-Location
    cd $sqlpsPath
    Add-PSSnapin SqlServerCmdletSnapin100
    Add-PSSnapin SqlServerProviderSnapin100
    Update-TypeData -PrependPath SQLProvider.Types.ps1xml 
    update-FormatData -prependpath SQLProvider.Format.ps1xml 
    Pop-Location
}



function ApplySQLScript([string] $scriptPath)
{
    LoadSQLSnapIn
    
    ### TODO
    if (Test-Path $scriptPath) {
        $sqlVariables = "MyVar1 = 'String1'", "MyVar2 = 'String2'"

        Write-Output "      Applying $scriptPath to $env:COMPUTERNAME"
        if (!$WhatIfPreference) {
            ## now for the real work
            $rc = Invoke-SqlCmd -InputFile $scriptPath -Variable $sqlVariables
            if ($rc -match "error") {
                Write-Error "      Script execution failed with code $rc"
            } else {
                Write-Output "      Script execution succeeded."
                $script:actionSucceeded = $true
            }#if
        }
    } else {
            Write-Error "      Script $scriptPath not found"
    }#if
}



function UninstallMsi([string] $applicationId, [string]$productId)
{
    Write-Output "      Uninstalling $applicationId from $env:COMPUTERNAME"

    $prod = $script:installedProducts | where { $_.Name -like "$productId*" }
    if ($prod -eq $null) {
        # not found
        Write-Output "      Product $applicationId not found: uninstall not needed." 
        $script:actionSucceeded = $true
    } else {
		$prodVer = GetProductVersionFromInstalledProduct($prod)
		Write-Verbose "      $applicationId v$prodVer is installed."

		if ($prod -eq $null) {
			Write-Error "      Internal error: lost WMI object"
		} elseif (!$WhatIfPreference) {
			$uninstallRes = $prod.Uninstall()
			if ($uninstallRes -eq $null) {
                Write-Warning "      No Uninstall result"
			} else {
				$rc = $uninstallRes.ReturnCode
				if ($rc -eq $null) {
                    Write-Warning "      No Uninstall return code"
				} elseif ($rc -eq 0) {
                    Write-Output "      Uninstall succeeded."
				} else {
                    Write-Error "      Uninstall failed with $rc"
                    $script:actionSucceeded = $false
				}
			}
		}
	}

    Write-Output "      $applicationId from $env:COMPUTERNAME uninstalled."
}


#EOF#