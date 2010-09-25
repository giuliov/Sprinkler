# Get the path where powershell resides.  If the caller passes -use32 then  
# make sure we are returning back a 32 bit version of powershell regardless 
# of the current machine architecture 
function Get-PowerShellPath() { 
    param ( [switch]$use32=$false, 
            [string]$version="1.0" ) 
 
    if ( $use32 -and (test-win64machine) ) { 
        return (join-path $env:windir "syswow64\WindowsPowerShell\v$version\powershell.exe") 
    } 
 
    return (join-path $env:windir "System32\WindowsPowerShell\v$version\powershell.exe") 
} 
 
 
# Is this a Win64 machine regardless of whether or not we are currently  
# running in a 64 bit mode  
function Test-Win64Machine() { 
    return test-path (join-path $env:WinDir "SysWow64")  
} 
 
# Is this a Wow64 powershell host 
function Test-Wow64() { 
    return (Test-Win32) -and (test-path env:\PROCESSOR_ARCHITEW6432) 
} 
 
# Is this a 64 bit process 
function Test-Win64() { 
    return [IntPtr]::size -eq 8 
} 
 
# Is this a 32 bit process 
function Test-Win32() { 
    return [IntPtr]::size -eq 4 
} 
 
function Get-ProgramFiles32() { 
    if (Test-Win64 ) { 
        return ${env:ProgramFiles(x86)} 
    } 
 
    return $env:ProgramFiles 
} 

function Exec-Script32
{
	param(
		[string] $scriptPath
	)
	
	$scriptName = Split-Path -Leaf $scriptPath
	$innerLogFilename = Join-Path $env:TEMP $scriptName
    $innerLogFilename += ".log"
	$dataFilename = Join-Path $env:TEMP $scriptName
    $dataFilename += ".data"
	Export-Clixml -Path $dataFilename -InputObject $Args
	$ps32 = Get-PowershellPath -use32
	Write-Verbose "### Re-entering '$scriptPath' in 32-bit shell"
	Write-Verbose "### Logging to '$innerLogFilename'"
	# call this exact file
	& $ps32 -File $scriptPath $dataFilename 2>&1 > $innerLogFilename
    $succeeded = $?
	Write-Output (Get-Content $innerLogFilename)
	Remove-Item $innerLogFilename
    if (!$succeeded) {
        #forward
        throw "$scriptPath failed"
    }
}

#EOF#