### Distributed synchronization


function WaitOnMasterStatus($context, [string[]] $possibleStatus, [int] $maxMinutes)
{
	LogMessage $context "Waiting for master to enter $($possibleStatus[0]) state"
    $maxRetries = ($maxMinutes * 60000) / $context.PollingInterval
    Write-Debug "WaitOnMasterStatus: $maxRetries Retries of $($context.PollingInterval) ms"
    $matches = $false
    for ($i = 0; $i -lt $maxRetries -and -not $matches; $i++) {
        $status = Get-Content -Path ($context.MasterStatusFilename) -ErrorAction:SilentlyContinue
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
                $status = Get-Content -Path $file -ErrorAction:SilentlyContinue
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
    Set-Content -Path ($context.MyStatusFilename) -Value $status
}




function Transition-To-BetaState($context)
{
	SetMyStatus $context "READY"
	if ($context.IAmTheMaster) {
		WaitOnAllStatuses $context @("READY") 10
    	SetMyStatus $context "INIT"
	} else {
		# INIT can be a quick transition, so RUN is ok also
		$reason = WaitOnMasterStatus $context @("INIT","RUN","FAILED") 10
		if ($reason -eq "FAILED") {
            throw "Deploy failed on Master server $(context.MasterServer)`: exiting."
        }
    }
}


function Transition-To-GammaState($context)
{
	if (! ($context.IAmTheMaster)) {
		$reason = WaitOnMasterStatus $context @("RUN","FAILED") 60
		if ($reason -eq "FAILED") {
            throw "Deploy failed on Master server $(context.MasterServer)`: exiting."
        }
    }
	SetMyStatus $context "RUN"
}


function Transition-To-DeltaState($context)
{
	SetMyStatus $context "COMPLETE"
	if ($context.IAmTheMaster) {
		$reasons = WaitOnAllStatuses $context @("COMPLETE","FAILED") 180
		if ($reasons -contains "FAILED") {
            throw "Deploy failed on other server(s): exiting."
        }
    	SetMyStatus $context "FINALIZE"
	} else {
		# FINALIZE can be a quick transition, so DONE is ok also
		$reason = WaitOnMasterStatus $context @("FINALIZE","DONE","FAILED") 190
		if ($reason -eq "FAILED") {
            throw "Deploy failed on Master server $(context.MasterServer)`: exiting."
        }
    }
}


function Transition-To-EpsilonState($context)
{
	if ($context.IAmTheMaster) {
    	SetMyStatus $context "DONE"
	} else {
		$reason = WaitOnMasterStatus $context @("DONE","FAILED") 60
		if ($reason -eq "FAILED") {
            throw "Deploy failed on Master server $(context.MasterServer)`: exiting."
        }
		SetMyStatus $context "DONE"
    }
}


#EOF#
