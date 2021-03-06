<#
#>

$script:deployRecords = @()
$script:installedProducts = @()


function OpenRecordDeploy([string]$statusDir)
{
	$filename = "$statusDir\DeployRecords-$env:COMPUTERNAME.csv"
	$rec = "Server,Package,Version,Status" #duration
    if (!$WhatIfPreference) {
		Out-File -InputObject $rec -FilePath $filename
    }
}
function RecordDeploy([string]$statusDir, [string]$package, [string]$version, [string]$status)
{
	$rec = "$env:COMPUTERNAME,$package,$version,$status" #duration
	$filename = "$statusDir\DeployRecords-$env:COMPUTERNAME.csv"
    if (!$WhatIfPreference) {
		Out-File -InputObject $rec -FilePath $filename -Append 
    }
    $script:deployRecords += @{ Package=$package; Version=$version; Status=$status }
}



# search highest version
function PickHighestVersionFile($availableBuilds)
{
    # transform string version in an hashtable
    $availableBuilds = $availableBuilds | %{ @{ Version=$_; Major=[int] ($_ -split '\.')[0]; Minor=[int] ($_ -split '\.')[1]; Build=[int] ($_ -split '\.')[2]; Release=[int] ($_ -split '\.')[3] } }
    # sort by numbers and pick highest
    $version = ($availableBuilds | Sort-Object -Property `
        @{ Expression={$_.Major}; Descending=$true }, `
        @{ Expression={$_.Minor}; Descending=$true }, `
        @{ Expression={$_.Build}; Descending=$true }, `
        @{ Expression={$_.Release}; Descending=$true } `
         | Select-Object -First 1)
    return $version
}



function GetPackageSource( $context, $package, $source )
{
    $dropDir = $source.drop
    
    #HACK move fo Fx
    if (!(Test-Path $dropDir)) {
        $dropDir = Join-Path $context.BaseDirectory -ChildPath $dropDir
        if (!(Test-Path $dropDir)) {
            Write-Error "Drop $($source.drop) not found"
        }
    }
    
    if ($package.version -ne $null) {
    
        if ($source.structure -ne $null) {
        
            $BuildDefinition = $source.structure

            # scan folders in drop
            $availableBuilds = Get-Item "$dropDir\$($BuildDefinition)_$($package.version)" | Split-Path -Leaf | %{ $parts=($_ -split "_"); $parts[1] }
            
            $version = PickHighestVersionFile $availableBuilds

            $packagePath = "$dropDir\$($BuildDefinition)_$($version.Version)\Release\$($package.file)-$($version.Version).msi"
            if (! (Test-Path -Path $packagePath)) {
                # fallback to three-part version
                $packagePath = "$dropDir\$($BuildDefinition)_$($version.Version)\Release\$($package.file)-$($version.Major).$($version.Minor).$($version.Build).msi"
            }
        } else {
        
            # scan files in folder
            $availableBuilds = Get-ChildItem -Path $dropDir -Name -Filter "$($package.file)-*.msi" | Split-Path -Leaf | %{ $parts=($_ -split "-"); $rem=$parts[$parts.Length-1]; $rem.Substring(0,$rem.IndexOf(".msi")) }
        
            $version = PickHighestVersionFile $availableBuilds

            $packagePath = "$dropDir\$($package.file)-$($version.Version).msi"
            if (! (Test-Path -Path $packagePath)) {
                # fallback to three-part version
                $packagePath = "$dropDir\$($package.file)-$($version.Major).$($version.Minor).$($version.Build).msi"
            }
        }#if

        if (! (Test-Path -Path $packagePath)) {
            Write-Error "Package '$packagePath' not found."
            return $null
        } else {
            $package = Add-Member -InputObject $package -MemberType NoteProperty -Name "effectiveVersion" -Value $version.Version -PassThru
            $package = Add-Member -InputObject $package -MemberType NoteProperty -Name "effectiveFile" -Value $packagePath -PassThru
        }
        
    } else {
    
        #unversioned file
        $packagePath = "$dropDir\$($package.file)"
        
        if (! (Test-Path -Path $packagePath)) {
            Write-Error "Package '$packagePath' not found."
            return $null
        } else {
            $package = Add-Member -InputObject $package -MemberType NoteProperty -Name "effectiveVersion" -Value "*unknown*" -PassThru
            $package = Add-Member -InputObject $package -MemberType NoteProperty -Name "effectiveFile" -Value $packagePath -PassThru
        }
        
    }#if

    # normalize package fields
    if ($package.fullName -eq $null) {
        $package = Add-Member -InputObject $package -MemberType NoteProperty -Name "fullName" -Value $package.file -PassThru
    }
    if ($package.productId -eq $null) {
        $package = Add-Member -InputObject $package -MemberType NoteProperty -Name "productId" -Value $package.file -PassThru
    }

    Write-Verbose "Package $($package.name) is $($package.file) v$($package.version) <$($package.fullName)> <$($package.productId)>"

    return $package
}



function GetProductVersionFromInstalledProduct($prod)
{
	return $prod.Version.Substring(0,3)
}
function GetProductVersionFromVersion($ver)
{
	return $ver.Substring(0,3)
}



function IsAlreadyInstalled($package)
{
	$productId = $package.productId
	
    $found = $script:installedProducts | where { $_.Name -like "$productId*" }
    if ($found -eq $null) {
        # not found
        return $false
    } else {
        # exact match?
        if ($package.effectiveVersion -eq $found.Version) {
            return $true
        }
        # partial match?
		Write-Verbose "Trying partial match for $($package.name) v$($package.effectiveVersion) with installed version $($found.Version)"
        if ($package.effectiveVersion -like ($found.Version + ".*")) {
            # HACK: pick the version from an executable
            #  also the x86 depends on many factors
            #  and it won't works for ESB.Portal as it uses different naming conventions
            $pickOne = Get-Item "C:\Program Files (x86)\$($package.fullName)\*\$($package.fullName).*.DLL"
            if ($pickOne.Count -gt 0) {
				Write-Verbose "Trying match with $pickOne"
                $versionFound = (Get-Command $pickOne[0]).FileVersionInfo.ProductVersion
                return $package.effectiveVersion -eq $versionFound
            } else {
				Write-Verbose "No executable to infer"
			}
        }
        return $false
    }
}



function GetDeployToDatabaseFlag($role)
{
    $deployToDB = [bool] $role.deployToDB
    if ($deployToDB -eq $null) {
        $deployToDB = $false
    }
    return $deployToDB
}



#EOF#