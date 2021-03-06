function Update-DeploymentStatus 
{
	param(
		[string] $dropURL,
		[string]$logShare,
		$cred = (Get-Credential)
	)
    
    $wc = New-Object System.Net.WebClient 
    $wc.Credentials = $cred
    
    foreach ($file in (Get-ChildItem (Join-Path $logShare "DeployRecords-*"))) {
    
        [string] $filename = $file.Name
        Write-Output "Loading $filename"

		$ex = $null
        Import-Csv $file.FullName | foreach {
            Write-Verbose $_
            $requestURL = "$($dropURL)DropService.svc/Register?Server=$($_.Server)&Package=$($_.Package)&Version=$($_.Version)&Status=$($_.Status)"
            Write-Debug $requestURL
			try {
            	$confirm = $wc.DownloadString($requestURL)
	            Write-Output "$filename imported"
	            Remove-Item $_.FullName
	            Write-Output "$filename deleted"
			} catch {
				$ex = $_
	            Write-Output "Upload failed: $ex"
			}#try
        }#for
		if ($ex -ne $null) {
			break
		}
    }#for
}

# test
#$cred = New-Object System.Net.NetworkCredential "password","users","domain"
#Update-DeploymentStatus "http://drops.example.com/" "\\build\Deploy\Logs" $cred

#EOF#