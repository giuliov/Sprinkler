<#
    This is the script that deploys the Packages on a single box
#>
param(
		[Parameter(Mandatory=$true)]
		[string]
    $environmentFile,
		[Parameter(Mandatory=$true)]
		[string]
    $ENV_SETTINGS,
		[ValidateSet("DEPLOY","UNDEPLOY","BOTH","UPGRADE","INITIALIZE","FINALIZE")]
		[string]
	$Mode = "BOTH",
		[string]
	$CustomDeployParameters = "",
		[string]
	$CustomUndeployParameters = "",
		[Switch]
	$Whatif
)
### Setup variables
#$DebugPreference = "Continue"
#$VerbosePreference = "Continue"
$WhatifPreference = $Whatif
$thisScriptPath = $MyInvocation.MyCommand.Path
$thisScriptDir = Split-Path -Parent $thisScriptPath
Write-Debug "ThisScriptPath  = $thisScriptPath"
Write-Debug "ThisScriptDir = $thisScriptDir"
Write-Verbose "Script Parameters: environmentFile='$environmentFile', ENV_SETTINGS=$ENV_SETTINGS, Mode=$Mode, CustomDeployParameters='$CustomDeployParameters', CustomUndeployParameters='$CustomUndeployParameters', Whatif=$Whatif"


. "$thisScriptDir\DeployFx.ps1"


switch ($Mode) {
    "DEPLOY"   {
        $UndeployFlag = $false
        $DeployFlag = $true
        $UpgradeFlag = $false
    }
    "UNDEPLOY" {
        $UndeployFlag = $true
        $DeployFlag = $false
        $UpgradeFlag = $false
    }
    "BOTH"     {
        $UndeployFlag = $true
        $DeployFlag = $true
        $UpgradeFlag = $false
    }
    "UPGRADE"  {
        $UndeployFlag = $true
        $DeployFlag = $true
        $UpgradeFlag = $true
    }
    "INITIALIZE"   {
        $UndeployFlag = $false
        $DeployFlag = $false
        $UpgradeFlag = $false
        $SkipFinalizeFlag = $true
    }
    "FINALIZE" {
        $UndeployFlag = $false
        $DeployFlag = $false
        $UpgradeFlag = $false
        $SkipInitializeFlag = $true
    }
}#switch

$script:actionSucceeded = $false


Write-Output "Environment file: $environmentFile"
Write-Output "Environment: $ENV_SETTINGS"
Write-Output "Mode: $Mode"
Write-Verbose "  Flags are Undeploy=$UndeployFlag, Deploy=$DeployFlag, Upgrade=$UpgradeFlag, SkipInitializeFlag=$SkipInitializeFlag, SkipFinalizeFlag=$SkipFinalizeFlag"
Write-Debug "***settingsFile is '$settingsFile' [Null:$($settingsFile -eq $null)]"


########################## FUNCTIONS #####################

Write-Verbose "Loading packages library"
. "$thisScriptDir\ServerDeploy-Packages.ps1"

# load the script with the actions
Write-Verbose "Loading server action library"
. "$thisScriptDir\ServerDeploy-Actions.ps1"

# load the script with the actions
Write-Verbose "Loading environment action library"
. "$thisScriptDir\BizTalk-Actions.ps1"

###################### MAIN ##########################



# keys here must be used in the XML configuration file
$PackageUninstallActions = @{
    SCRIPT_TEST = { param ($context, $package, $role)
        # dummy action
        $script:actionSucceeded = $true
        }
    BTDF = { param ($context, $package, $role)
            BiztalkUndeployAndUninstall $package.fullName $package.productId $context.TargetEnvironment $context.SettingsFile (GetDeployToDatabaseFlag $role)
        }
    MSI_PS = { param ($context, $package, $role)
            OtherUndeployAndUninstall $package $context.TargetEnvironment $context.SettingsFile (GetDeployToDatabaseFlag $role)
        }
    SQL = { param ($context, $package, $role)
        # dummy action
        $script:actionSucceeded = $true
        }
}
$PackageInstallActions = @{
    SCRIPT_TEST = { param ($context, $package, $role)
        Write-Debug $context.SettingsFile
        & "C:\Program Files (x86)\Deployment Framework for BizTalk\5.0\Framework\DeployTools\EnvironmentSettingsExporter.exe" $context.SettingsFile C:\TEMP\ | Write-Output
        $script:actionSucceeded = $?
        }
    BTDF = { param ($context, $package, $role)
            MsiInstall $package.effectiveFile
            BiztalkDeploy $package.fullName $package.effectiveVersion $context.TargetEnvironment $context.SettingsFile (GetDeployToDatabaseFlag $role)
        }
    MSI_PS = { param ($context, $package, $role)
            MsiInstall $package.effectiveFile
            OtherDeploy $package $context.TargetEnvironment $context.SettingsFile (GetDeployToDatabaseFlag $role)
        }
    SQL = { param ($context, $package, $role)
            ApplySQLScript $package.effectiveFile $server.Name $credentials
        }
}


function GetCategoryActions($context)
{
	$category = (Select-Xml -Xml $context.RawConfiguration -XPath "/environments/environmentCategories/category[@name = /environments/environment[@name = '$($context.TargetEnvironment)']/@category]").Node
	$thisServerRoles = Select-Xml -Xml $context.RawConfiguration -XPath "/environments/environment[@name = '$($context.TargetEnvironment)']/server[@name = '$env:COMPUTERNAME' or @name = '*']/role" | foreach { $_.Node.name }
	$categoryActions = Select-Xml -Xml $category -XPath "execute" | where {
		$thisServerRoles -contains $_.Node.roleRequired
	} | foreach {
		$_.Node
	}
	return $categoryActions
}

function DoFarmInitialize($context)
{
	$categoryActions = GetCategoryActions $context

	if ($SkipInitializeFlag) {
		Write-Output "Initializing actions disabled by user."
	} else {
		Write-Output "Executing initializing actions for $($category.name) category."

		#initialize environment
		$categoryActions | foreach {
			$action = $_.name
			if ($_.order -eq 'FarmInitialize') {
				Write-Output "  Executing farm initialize action $action"
				& $action $context
			}
		}
	}
}
function DoServerInitialize($context)
{
	LogMessage $context "Retrieving installed products"
	$script:installedProducts = Get-WmiObject -Query "SELECT * FROM Win32_Product" -namespace "root\CIMV2"
	LogMessage $context "Found $($script:installedProducts.Count) products."
	
	$categoryActions = GetCategoryActions $context
	$categoryActions | foreach {
		$action = $_.name
		if ($_.order -eq 'ServerInitialize') {
			Write-Output "  Executing server initialize action $action"
			& $action $context
		}
	}#for
}
function DoServerCore($context)
{
	$context.Succeeded = $true

	#HACK move to Fx
    $source = (Select-Xml -Xml $context.RawConfiguration -XPath "/environments/environment[@name = '$($context.TargetEnvironment)']/source").Node
	OpenRecordDeploy $context.LogDirectory


	$rolesForThisServer = Select-Xml -Xml $context.RawConfiguration -XPath "/environments/environment[@name = '$($context.TargetEnvironment)']/server[@name='$env:COMPUTERNAME' or @name = '*']/role" | %{ $_.Node }
	foreach ($role in $rolesForThisServer) {

		LogMessage $context "Starting deploy round for role $($role.name) on $env:COMPUTERNAME"

		# whick packages?
		$packageColl = Select-Xml -Xml $context.RawConfiguration -XPath "/environments/roles/role[@name='$($role.name)']/package" | %{ $_.Node }
		$packageColl | %{ Write-Debug $_.OuterXml }
		
		$uninstallPackages = @()
		$installPackages = @()

		foreach ($package in $packageColl) {
			# determine filename for package
			$foundPackage = GetPackageSource $context $package $source
			if ($foundPackage -ne $null) {
				if ($UpgradeFlag -and (IsAlreadyInstalled $foundPackage)) {
					Write-Output "  Package $($foundPackage.name) is already installed on $env:COMPUTERNAME, no need upgrading to version $($foundPackage.effectiveVersion)"
				} else {
					if ($PackageUninstallActions.Keys -notcontains $package.type) {
						Write-Warning "Unsupported uninstall action $($package.type) for package $($package.name)"
					} else {
						#reverse order
						$uninstallPackages = @($foundPackage) + $uninstallPackages
					}
					if ($PackageInstallActions.Keys -notcontains $package.type) {
						Write-Warning "Unsupported install action $($package.type) for package $($package.name)"
					} else {
						$installPackages += $foundPackage
					}
				}
			} else {
				Write-Warning "Source not found for package $($package.name)"
				RecordDeploy $context.LogDirectory $package.name $package.version "Not found"
			}
		}#for
		

		Write-Output "================================================================="
		if ($UndeployFlag) {
			Write-Output "  Start undeploy"
			foreach ($package in $uninstallPackages) {
				LogMessage $context "  Undeploying package $($package.name) on $env:COMPUTERNAME via $($package.type)"
				# execute the script block associated with that role
				$script:actionSucceeded = $false
				Push-Location -StackName Sprinkle
				& $PackageUninstallActions[$package.type] $context $package $role
				Pop-Location -StackName Sprinkle
				if (!$script:actionSucceeded) {
					Write-Error "  Undeploy failed."
					$context.Succeeded = $false
				}
			}#for
		} else {
			LogMessage $context "  Undeploy disabled by user."
		}
		Write-Output "================================================================="
		
		Write-Output "================================================================="
		if ($DeployFlag) {
			Write-Output "  Starting deploy"
			foreach ($package in $installPackages) {
				LogMessage $context "  Deploying package $($package.name) v$($package.effectiveVersion) on $env:COMPUTERNAME via $($package.type) from $($package.effectiveFile)"
				# execute the script block associated with that role
				$script:actionSucceeded = $false
				Push-Location -StackName Sprinkle
				& $PackageInstallActions[$package.type] $context $package $role
				Pop-Location -StackName Sprinkle
				if (!$script:actionSucceeded) {
					Write-Error "  Deploy failed."
					$context.Succeeded = $false
					RecordDeploy $context.LogDirectory $package.name $package.effectiveVersion "Failed"
				} else {
					RecordDeploy $context.LogDirectory $package.name $package.effectiveVersion "Deployed"
				}
			}
		} else {
			LogMessage $context "  Deploy disabled by user."
		}
		Write-Output "================================================================="

		LogMessage $context "Deploy round for role $($role.name) on $env:COMPUTERNAME is completed."
		
	}#for
}
function DoServerFinalize($context)
{
	$script:deployRecords | foreach {
	    $context.ReportLines += "  Package $($_.Package) v$($_.Version) is $($_.Status)"
	}
	
	$categoryActions = GetCategoryActions $context
	$categoryActions | foreach {
		$action = $_.name
		if ($_.order -eq 'ServerFinalize') {
			Write-Output "  Executing server finalize action $action"
			& $action $context
		}
	}#for
}
function DoFarmFinalize($context)
{
	if (!$context.Succeeded) {
		Write-Output "Some packaged failed to (un)deploy: will not execute finalizing farm actions."
	} elseif ($SkipFinalizeFlag) {
			Write-Output "Finalizing actions disabled by user."
	} else {
		Write-Output "Executing finalizing farm actions for $($category.name) category."

		$categoryActions = GetCategoryActions $context
		#finalize environment
		$categoryActions | foreach {
			$action = $_.name
			if ($_.order -eq 'FarmFinalize') {
				#first server of the farm: execute farm initialize
				LogMessage $context "  Executing farm finalize action $action"
				& $action $context
			}
		}
	}
}

RunDistributedDeployEngine $environmentFile $ENV_SETTINGS {param($context) DoFarmInitialize $context } {param($context) DoServerInitialize $context } {param($context) DoServerCore $context } {param($context) DoServerFinalize $context } {param($context) DoFarmFinalize $context }
