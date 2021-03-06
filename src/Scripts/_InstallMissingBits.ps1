$DebugPreference = "Continue"
$thisScript = $MyInvocation.MyCommand.Path
$ScriptDir = Split-Path -Parent $thisScript
Write-Debug "ScriptDir = $ScriptDir"
Write-Debug "ThisScript  = $thisScript"

$gacutil = Join-Path $ScriptDir "..\Tools\gacutil.exe"
Join-Path $ScriptDir "..\Data\Missing-bits" | Get-ChildItem | foreach {
    & $gacutil -i $_.FullName
}
Write-Output "Missing bits installed"


$ESBFolder = "${env:ProgramFiles(x86)}\Microsoft BizTalk ESB Toolkit 2.0\Bin"
$BTSPipelineComponentsFolder = "${env:ProgramFiles(x86)}\Microsoft BizTalk Server 2009\Pipeline Components"

Copy-Item -Path "$ESBFolder\Microsoft.Practices.ESB.*PipelineComponents.dll" -Destination $BTSPipelineComponentsFolder
Write-Output "ESB.PipelineComponents installed"

#EOF#