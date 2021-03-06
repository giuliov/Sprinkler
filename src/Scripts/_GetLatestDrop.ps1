<#
#>
param(
		[Parameter(Mandatory=$true)]
		[string]
    $destinationFolder,
		[Parameter(Mandatory=$true)]
        [string]
    $shareName,
        [string]
    $shareFolder = "",
        [string]
    $dropURL = "http://drops.example.com/"
)


function Extract-Zip
{
	param([string]$zipfilename, [string] $destination)

	if (Test-Path $zipfilename)
	{
        # see http://msdn.microsoft.com/en-us/library/bb773938(v=VS.85).aspx
		$shellApplication = New-Object -Com Shell.Application
		$zipPackage = $shellApplication.NameSpace($zipfilename)
		$destinationFolder = $shellApplication.NameSpace($destination)
        # 16 = Respond with "Yes to All" for any dialog box that is displayed
		$destinationFolder.CopyHere($zipPackage.Items(), 16)
	}
}


function Download-File([string]$dropURL, [string]$destinationFolder, $fileDesc)
{
    [string] $filename = $fileDesc.Name
    $destFile = (Join-Path $destinationFolder $filename)
    $wc.DownloadFile($dropURL+$fileDesc.URL, $destFile)
    Write-Output "$filename downloaded"
    if ($filename.EndsWith(".zip",'InvariantCultureIgnoreCase')) {
        Extract-Zip $destFile $destinationFolder
        Write-Output "$filename unzipped"
    }
}


function Download-FromDrops
{
	param([string] $destinationFolder, [string]$dropURL, [string]$share = "DailyLatest", [string]$folder)
    
    trap { "Download failed: $_" }
    
    New-Item $destinationFolder -Type Directory

    $wc = New-Object System.Net.WebClient 
    $wc.Credentials = Get-Credential
    
    if ($folder -eq "") {
        $requestURL = $dropURL+"DropService.svc/$share"
    } else {
        $requestURL = $dropURL+"DropService.svc/$share/$folder"
    }
    
    $shareContent = [xml] $wc.DownloadString($requestURL)

    $files = $shareContent.ArrayOfFile.File | sort -Property Name
    
    #HACK order is luckily right
    
	# first the Zip that creates the layout
    Download-File $dropURL $destinationFolder $files[0]
    Download-File $dropURL (Join-Path $destinationFolder -ChildPath "Config") $files[-1]
    $files[1..($files.length-2)] | foreach {
        Download-File $dropURL (Join-Path $destinationFolder -ChildPath "Packages") $_
    }
}


Download-FromDrops $destinationFolder $dropURL $shareName $shareFolder

#EOF#