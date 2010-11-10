### Log handling


function OpenLog($context)
{
    if ($TranscriptHosts -contains $host.Name) {
        Start-Transcript $context.LogFile
    }
}
function CloseLog($context)
{
    if ($TranscriptHosts -contains $host.Name) {
        Stop-Transcript
    }
}
function LogMessage($context, $message)
{
    Write-Output "$(Get-Date -f 'HH:mm:ss'): $message"
}
function CloseLogOnError($context)
{
    Write-Output "*****  SCRIPT FAILED  *****"
	Write-Output "Last error(s):"
	Write-Output $Error
	Write-Host "Check $($context.LogFile) log content."
    if ($TranscriptHosts -contains $host.Name) {
        Stop-Transcript
    }
}


#EOF#
