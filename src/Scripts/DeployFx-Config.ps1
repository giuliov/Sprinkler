### Context handling


function DumpContext($context, [string] $message)
{
    Write-Verbose $message
    $context | Get-Member -MemberType Property | %{
        Write-Verbose "$($_.Name) = $( $context.($_.Name) )"
    }
}


# Xml Schema validation
function Test-Xml { 
    param( 
        $InputObject = $null, 
        $Namespace = $null, 
        $SchemaFile = $null 
    ) 
 
    BEGIN { 
        $failCount = 0 
        $failureMessages = @() 
        $fileName = "" 
    } 
     
    PROCESS { 
        if ($InputObject -and $_) { 
            throw 'ParameterBinderStrings\AmbiguousParameterSet' 
            break 
        } elseif ($InputObject) { 
            $source = $InputObject 
            $fileName = $InputObject
        } elseif ($_) { 
            $source = $_
            $fileName = $_.FullName 
        } else { 
            throw 'ParameterBinderStrings\InputObjectNotBound' 
        } 

        $readerSettings = New-Object -TypeName System.Xml.XmlReaderSettings 
        $readerSettings.ValidationType = [System.Xml.ValidationType]::Schema 
        $readerSettings.ValidationFlags = [System.Xml.Schema.XmlSchemaValidationFlags]::ProcessInlineSchema -bor 
            [System.Xml.Schema.XmlSchemaValidationFlags]::ProcessSchemaLocation -bor  
            [System.Xml.Schema.XmlSchemaValidationFlags]::ReportValidationWarnings -bor
            [System.Xml.Schema.XmlSchemaValidationFlags]::ProcessIdentityConstraints
        $schemaSet = New-Object -TypeName System.Xml.Schema.XmlSchemaSet
        $schemaSet.Add($Namespace, $SchemaFile) | Out-Null
        $readerSettings.Schemas = $schemaSet
        $readerSettings.add_ValidationEventHandler( 
        { 
            $failureMessages += $fileName + " - " + $_.Message 
            $failCount = $failCount + 1 
        }); 
        $reader = [System.Xml.XmlReader]::Create($source, $readerSettings) 
        while ($reader.Read()) { } 
    } 
     
    END {
        if ($failCount -gt 0) {
            $failureMessages 
            "$failCount validation errors were found"
        }
    } 

}


function ValidateConfiguration($context)
{
    Write-Output "Validating SPRINKLER configuration"
	
    # you may put here the content of environment.xsd, so this script (ServerDeploy) has no dependencies (and may be run remotely)
    $validationSchemaContent = $null

    if ($validationSchemaContent) {
    	$validationSchema = [xml]$validationSchemaContent
    } else {
    	$validationSchema = [xml](Get-Content (Join-Path $context.ScriptDirectory -ChildPath "environments.xsd"))
    }
    $validationSchemaReader = New-Object -TypeName System.Xml.XmlNodeReader $validationSchema.DocumentElement
    $failures = Test-Xml $environmentFile -SchemaFile $validationSchemaReader
    if ($failures) {
        Write-Error "Invalid environment file (schema validation failed)."
        Write-Output $failures
        throw "Invalid environment file"
    }
	#TODO the requested $context.TargetEnvironment is listed in the environment file (i.e. Fx Xml config)?
}


function CreateAndLoadContext([string] $environmentFile, [string] $ENV_SETTINGS)
{
    $context = New-Object $DeployContextClassName
	[xml]$environments = Get-Content $environmentFile
    $context.RawConfiguration = $environments
    $context.TargetEnvironment = $ENV_SETTINGS
	$source = (Select-Xml -Xml $context.RawConfiguration -XPath "/environments/environment[@name = '$ENV_SETTINGS']/source").Node
    $context.LogDirectory = $source.log
    
	# which is the script invoked by SPRINKLE? inspect the call stack to find it
    $whichScript = Get-PSCallStack | foreach {
        [string] $cmd = $_.Command
        if ($cmd.EndsWith('.ps1')) {
            return $cmd.Substring(0,$cmd.Length-4)
        }
    }#for
    
    $context.LogFile = "$($source.log)\$($whichScript[0])-$env:COMPUTERNAME-$(Get-Date -f 'yyyyMMdd-HHmm').txt"
    # HACK this won't work if run remotely!
    $context.ScriptDirectory = Split-Path -Parent $script:MyInvocation.MyCommand.Path
    DumpContext $context "Initial Context contains:"
	return $context
}


function LoadConfiguration($context)
{
    Write-Output "Loading SPRINKLER configuration"
	
    #HACK the farm is composed by BIZTALK servers only
    $serversInOrder = @( Select-Xml -Xml $context.RawConfiguration -XPath "/environments/environment[@name = '$($context.TargetEnvironment)']/server[role/@name='BIZTALK']/@name" | foreach{ $_.Node.Value } )
    # wildcard server name => LOCAL
    $serversInOrder = @($serversInOrder | foreach { if ($_ -eq '*') { $env:COMPUTERNAME } else { $_ } })
    $context.Servers = $serversInOrder

    $masterServer = $serversInOrder[0]
    $context.MasterServer = $masterServer
	$context.IAmTheMaster = $masterServer -eq $env:COMPUTERNAME
    $context.MyStatusFilename = "$($context.LogDirectory)\$env:COMPUTERNAME.status"
    $context.AllStatusFilenames = @($serversInOrder | foreach { "$($context.LogDirectory)\$_.status" })
    $context.MasterStatusFilename = "$($context.LogDirectory)\$masterServer.status"

    #HACK BIZTALK servers only
    $deployToDB = [bool] (Select-Xml -Xml $context.RawConfiguration -XPath "/environments/environment[@name = '$($context.TargetEnvironment)']/server[@name = '$env:COMPUTERNAME' or @name = '*']/role[@name='BIZTALK']").Node.deployToDB
    if ($deployToDB -eq $null) {
        $deployToDB = $false
    }
    $context.DeployToDB = $deployToDB
    $context.PollingInterval = 500 #0.5sec

    $context.BaseDirectory = Split-Path -Parent $context.ScriptDirectory
    $context.ConfigDirectory = Join-Path $context.BaseDirectory -ChildPath "Config"
    $context.ToolsDirectory = Join-Path $context.BaseDirectory -ChildPath "Tools"
    $context.DataDirectory = Join-Path $context.BaseDirectory -ChildPath "Data"

	Write-Output "Looking for Master Settings file"
    $source = (Select-Xml -Xml $context.RawConfiguration -XPath "/environments/environment[@name = '$($context.TargetEnvironment)']/source").Node
    if ($source.settingsFile -ne $null) {

        $masterSettingsFile = $source.settingsFile
        # hope for full path spec
        if (! (Test-Path -Path $masterSettingsFile)) {
			# try config dir
			$masterSettingsFile = Join-Path $context.ConfigDirectory -ChildPath $source.settingsFile
            if (! (Test-Path -Path $masterSettingsFile)) {
				# not found, check drop dir
				$masterSettingsFile = Join-Path $source.drop -ChildPath $source.settingsFile
            }
        }
        if (Test-Path $masterSettingsFile) {
            Write-Output "Using global settings file"
            $context.MasterSettingsFile = $masterSettingsFile
        } else {
            Write-Error "Master Settings file $masterSettingsFile not found."
        }
            
    } else {
        Write-Output "Using per-application settings files"
        $context.MasterSettingsFile = ""
    }
    DumpContext $context "Configured Context contains:"
}


#EOF#
