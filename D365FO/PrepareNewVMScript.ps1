Set-MpPreference -DisableRealtimeMonitoring $true 
 #region Install tools
Install-Module -Name d365fo.tools -AllowClobber
Add-D365WindowsDefenderRules
Invoke-D365InstallAzCopy
Invoke-D365InstallSqlPackage
#endregion

#region Install additional apps using Chocolatey

If(Test-Path -Path "$env:ProgramData\Chocolatey") {
    choco upgrade chocolatey -y -r
    choco upgrade all --ignore-checksums -y -r
}
Else {

    Write-Host “Installing Chocolatey”
 
    [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
    iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

    #Determine choco executable location
    #   This is needed because the path variable is not updated
    #   This part is copied from https://chocolatey.org/install.ps1
    $chocoPath = [Environment]::GetEnvironmentVariable("ChocolateyInstall")
    if ($chocoPath -eq $null -or $chocoPath -eq '') {
      $chocoPath = "$env:ALLUSERSPROFILE\Chocolatey"
    }
    if (!(Test-Path ($chocoPath))) {
      $chocoPath = "$env:SYSTEMDRIVE\ProgramData\Chocolatey"
    }
    $chocoExePath = Join-Path $chocoPath 'bin\choco.exe'


    $packages = @(
		"googlechrome"
        "adobereader" 
		# "foxitreader"
        #"microsoftazurestorageexplorer"  
		#"servicebusexplorer"
        "winmerge"
        #"vscode"
        "7zip.install"
		#"winrar"     
        "notepadplusplus.install"
        "sysinternals"
		#"powerbi"
		#"git.install"
		#"github-desktop"
	    #"postman"  # or insomnia-rest-api-client
        #"fiddler"
    )

    # Install each program
    foreach ($packageToInstall in $packages) {

        Write-Host “Installing $packageToInstall” -ForegroundColor Green
        & $chocoExePath "install" $packageToInstall "-y" "-r"
    }
}
 
#endregion

#region Truncate batch
Function Execute-Sql {
    Param(
        [Parameter(Mandatory=$true)][string]$server,
        [Parameter(Mandatory=$true)][string]$database,
        [Parameter(Mandatory=$true)][string]$command
    )
    Process
    {
        $scon = New-Object System.Data.SqlClient.SqlConnection
        $scon.ConnectionString = "Data Source=$server;Initial Catalog=$database;Integrated Security=true"
        
        $cmd = New-Object System.Data.SqlClient.SqlCommand
        $cmd.Connection = $scon
        $cmd.CommandTimeout = 0
        $cmd.CommandText = $command

        try
        {
            $scon.Open()
            $cmd.ExecuteNonQuery()
        }
        catch [Exception]
        {
            Write-Warning $_.Exception.Message
        }
        finally
        {
            $scon.Dispose()
            $cmd.Dispose()
        }
    }
}

    
    $sql = "truncate table BATCH
truncate table BATCHCONSTRAINTS
truncate table BATCHCONSTRAINTSHISTORY
truncate table BATCHHISTORY
truncate table BATCHJOB
truncate table BATCHJOBALERTS
truncate table BATCHJOBHISTORY
truncate table sysserversessions "

    Execute-Sql -server "." -database "AxDB" -command $sql
#endregion	



#Disable Automatic Windows Updates
Set-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU -Name AUOptions -Value 1

#region Install dnspy
#choco install dnspy -y
#endregion

Write-Host "Setting web browser homepage to the local environment"
Get-D365Url | Set-D365StartPage
Write-Host "Setting Management Reporter to manual startup to reduce churn and Event Log messages"
Get-D365Environment -FinancialReporter | Set-Service -StartupType Manual
Stop-Service -Name MR2012ProcessService -Force
Set-Service -Name MR2012ProcessService -StartupType Disabled
Write-Host "Setting Windows Defender rules to speed up compilation time"
Add-D365WindowsDefenderRules -Silent

#region Install TRUDUtil
$repo = "TrudAX/TRUDUtilsD365"
$releases = "https://api.github.com/repos/$repo/releases"
$path = "C:\AAA"

If(!(test-path $path))
{
    New-Item -ItemType Directory -Force -Path $path
}
cd $path

Write-Host Determining latest release
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$tag = (Invoke-WebRequest -Uri $releases -UseBasicParsing | ConvertFrom-Json)[0].tag_name

$files = @("InstallToVS.exe",  "TRUDUtilsD365.dll",  "TRUDUtilsD365.pdb")

Write-Host Downloading files
foreach ($file in $files) 
{
    $download = "https://github.com/$repo/releases/download/$tag/$file"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest $download -Out $file
    Unblock-File $file
}
Start-Process "InstallToVS.exe" -Verb runAs
#endregion

#region ChangeIIS
if (test-path "$env:servicedrive\AOSService\PackagesLocalDirectory\bin\DynamicsDevConfig.xml"){
[xml]$xmlDoc = Get-Content "$env:servicedrive\AOSService\PackagesLocalDirectory\bin\DynamicsDevConfig.xml"
if ($xmlDoc.DynamicsDevConfig.RuntimeHostType -ne "IIS"){
write-host 'Setting RuntimeHostType to "IIS" in DynamicsDevConfig.xml' -ForegroundColor yellow
$xmlDoc.DynamicsDevConfig.RuntimeHostType = "IIS"
$xmlDoc.Save("$env:servicedrive\AOSService\PackagesLocalDirectory\bin\DynamicsDevConfig.xml")
write-host 'RuntimeHostType set "IIS" in DynamicsDevConfig.xml' -ForegroundColor Green
}#end if IIS check
}#end if test-path xml file
else {write-host 'AOSService drive not found! Could not set RuntimeHostType to "IIS"' -ForegroundColor red}
#endregion

#region VHDSetup
#Run Generate Self-Signed Certificates script with application 00000015-0000-0000-c000-000000000000
#To delete certificates copy C:\DynamicsTools\CleanVHD folder from clean VHD and run the script again (Admin provisioning tool afterwards).
#https://ax.docentric.com/configure-sharepoint-online-integration-in-d365fo-onebox/
#endregion

#region usefull tools
#https://marketplace.visualstudio.com/items?itemName=ViktarKarpach.DebugAttachManager
#endregion
