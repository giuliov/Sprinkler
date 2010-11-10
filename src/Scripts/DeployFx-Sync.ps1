### Distributed synchronization

function Get-ContentNoLock([string] $path)
{
	try {
		$f = New-Object System.IO.FileStream($path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite)
	} catch {
		return ""
	}
	$buf = New-Object byte[] 32
	$n = $f.Read($buf, 0, $buf.Length)
	$f.Close()
	return [System.Text.Encoding]::ASCII.GetString($buf, 0, $n)
}

function Set-ContentNoLock([string] $path, [string] $state)
{
	$f = New-Object System.IO.FileStream($path,[System.IO.FileMode]::OpenOrCreate,[System.IO.FileAccess]::Write,[System.IO.FileShare]::Read)
	$buf = [System.Text.Encoding]::ASCII.GetBytes($state)
	$f.Write($buf, 0, $buf.Length)
	$f.SetLength($buf.Length)
	$f.Close()
}

function WaitOnMasterStatus($context, [string[]] $possibleStatus, [int] $maxMinutes)
{
	LogMessage $context "Waiting for master to enter $($possibleStatus[0]) state"
    $maxRetries = ($maxMinutes * 60000) / $context.PollingInterval
    Write-Debug "WaitOnMasterStatus: $maxRetries Retries of $($context.PollingInterval) ms"
    $matches = $false
    for ($i = 0; $i -lt $maxRetries -and -not $matches; $i++) {
        $status = Get-ContentNoLock $context.MasterStatusFilename
        Write-Debug "'$($context.MasterStatusFilename)' is '$status'"
        $matches = $possibleStatus -contains $status
		Start-Sleep -Milliseconds $context.PollingInterval
    }#for
    return $status
}


function WaitOnAllStatuses($context, [string[]] $possibleStatus, [int] $maxMinutes)
{
	LogMessage $context "Waiting for all servers to enter $($possibleStatus[0]) state"
    $maxRetries = ($maxMinutes * 60000) / $context.PollingInterval
    Write-Debug "WaitOnAllStatuses: $maxRetries Retries of $($context.PollingInterval) ms"
    $matches = $false
    for ($i = 0; $i -lt $maxRetries -and -not $matches; $i++) {
        $matches = $true
        $statuses = @()
        $context.AllStatusFilenames | foreach {
            if ($matches) {
                $file = $_
                $status = Get-ContentNoLock $file
                $statuses += $status
                Write-Debug "'$file' is '$status'"
                $matches = $matches -and ($possibleStatus -contains $status)
            }
        }
		Start-Sleep -Milliseconds $context.PollingInterval
    }#for
    return $statuses
}


function SetMyStatus($context, [string] $status)
{
	LogMessage $context "Entering $status state"
	Set-ContentNoLock $context.MyStatusFilename $status
	LogMessage $context "State $status entered."
}


#-------------------------------------------------------------------------------


function Transition-To-BetaState($context)
{
    Write-Debug "Transition-To-BetaState: going READY"
	SetMyStatus $context "READY"
	if ($context.IAmTheMaster) {
	    Write-Debug "Transition-To-BetaState: waiting for READY"
		WaitOnAllStatuses $context @("READY") 10
	    Write-Debug "Transition-To-BetaState: going INIT"
    	SetMyStatus $context "INIT"
	} else {
	    Write-Debug "Transition-To-BetaState: waiting for INIT o RUN"
		# INIT can be a quick transition, so RUN is ok also
		$reason = WaitOnMasterStatus $context @("INIT","RUN","FAILED") 10
	    Write-Debug "Transition-To-BetaState: wait complete"
		if ($reason -eq "FAILED") {
            throw "Deploy failed on Master server $($context.MasterServer)`: exiting."
        }
    }
}


function Transition-To-GammaState($context)
{
	if (! ($context.IAmTheMaster)) {
	    Write-Debug "Transition-To-GammaState: waiting for RUN"
		$reason = WaitOnMasterStatus $context @("RUN","FAILED") 60
	    Write-Debug "Transition-To-GammaState: wait complete"
		if ($reason -eq "FAILED") {
            throw "Deploy failed on Master server $($context.MasterServer)`: exiting."
        }
    }
    Write-Debug "Transition-To-GammaState: going RUN"
	SetMyStatus $context "RUN"
}


function Transition-To-DeltaState($context)
{
    Write-Debug "Transition-To-DeltaState: going COMPLETE"
	SetMyStatus $context "COMPLETE"
	if ($context.IAmTheMaster) {
	    Write-Debug "Transition-To-DeltaState: waiting for COMPLETE"
		$reasons = WaitOnAllStatuses $context @("COMPLETE","FAILED") 180
	    Write-Debug "Transition-To-DeltaState: wait complete"
		if ($reasons -contains "FAILED") {
            throw "Deploy failed on other server(s): exiting."
        }
	    Write-Debug "Transition-To-DeltaState: going FINALIZE"
    	SetMyStatus $context "FINALIZE"
	} else {
	    Write-Debug "Transition-To-DeltaState: waiting for FINALIZE"
		# FINALIZE can be a quick transition, so DONE is ok also
		$reason = WaitOnMasterStatus $context @("FINALIZE","DONE","FAILED") 190
	    Write-Debug "Transition-To-DeltaState: wait complete"
		if ($reason -eq "FAILED") {
            throw "Deploy failed on Master server $($context.MasterServer)`: exiting."
        }
    }
}


function Transition-To-EpsilonState($context)
{
    Write-Debug "Transition-To-EpsilonState: going DONE"
	if ($context.IAmTheMaster) {
    	SetMyStatus $context "DONE"
	} else {
	    Write-Debug "Transition-To-EpsilonState: waiting for DONE"
		$reason = WaitOnMasterStatus $context @("DONE","FAILED") 60
	    Write-Debug "Transition-To-EpsilonState: wait complete"
		if ($reason -eq "FAILED") {
            throw "Deploy failed on Master server $($context.MasterServer)`: exiting."
        }
		SetMyStatus $context "DONE"
    }
}


#EOF#
