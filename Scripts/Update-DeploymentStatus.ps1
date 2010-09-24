function Update-DeploymentStatus 
{
	param(
		[string] $dropURL,
		[string]$logShare,
		$cred = (Get-Credential)
	)
    
    $wc = New-Object System.Net.WebClient 
    $wc.Credentials = $cred
    
    Get-ChildItem (Join-Path $logShare "DeployRecords-*") | foreach {
    
        [string] $filename = $_.Name
        Write-Output "Loading $filename"
        
        Import-Csv $_.FullName | foreach {
            Write-Verbose $_
            $requestURL = "$($dropURL)DropService.svc/Register?Server=$($_.Server)&Package=$($_.Package)&Version=$($_.Version)&Status=$($_.Status)"
            Write-Debug $requestURL
            $confirm = $wc.DownloadString($requestURL)
        }
        if ($Error.Count -eq 0) {
            Write-Output "$filename imported"
            Remove-Item $_.FullName
            Write-Output "$filename deleted"
        } else {
            Write-Output "Upload failed: $Error"
            break
        }
    }
}

# test
#$cred = New-Object System.Net.NetworkCredential "password","users","domain"
#Update-DeploymentStatus "http://drops.example.com/" "\\build\Deploy\Logs" $cred

#EOF#