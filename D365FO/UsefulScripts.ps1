https://github.com/d365collaborative/d365fo.tools/wiki

#MaintenanceMode
Enable-D365MaintenanceMode
Disable-D365MaintenanceMode

#SYNC
Invoke-D365DbSync
Invoke-D365DbSyncModule -Module "MyModel1"
Invoke-D365DBSyncPartial -SyncList "DirPartyLocation" -Verbose

#INSTALL LICENCE 
Invoke-D365InstallLicense "C:\AAA\lic.txt"

#DOWNLOAD DB FROM LCS
#--------------------------------
#https://msdyn365fo.wordpress.com/2020/03/05/boosting-your-downloads-from-lcs-with-azcopy-supported-by-d365fo-tools/
Invoke-D365InstallAzCopy
Invoke-D365AzCopyTransfer -SourceUri "https://uswedpl1catalog.blob.core.windows.n" -DestinationUri "J:\LCS\TST20210827.bacpac"

Invoke-D365InstallSqlPackage
Import-D365Bacpac -BacpacFile "J:\LCS\TST20210827.bacpac" -ImportModeTier1 -NewDatabaseName TST1
#--------------------------------


#BACKUP TIER1
#--------------------------------
#Install-Module -Name SqlServer -AllowClobber
Backup-SqlDatabase -ServerInstance "." -Database "AxDB" -CompressionOption On -BackupFile "I:\MSSQL_BACKUP\testDB.bak"

#or with var
$fileDB   =  "AxDB_" + (Get-Date -Format "yyyy_MM_dd") 
$fileName = $fileDB + ".bak"
$filePath = "I:\MSSQL_BACKUP\"  + $fileName
$filePath
Backup-SqlDatabase -ServerInstance "." -Database "AxDB" -CompressionOption On -BackupFile $filePath
Invoke-D365AzureStorageUpload -AccountId "denisshare" -AccessToken "fKlyrQ==" -Container  "databaseap" -Filepath $filePath -DeleteOnUpload
Write-Host "Invoke-D365AzureStorageDownload -AccountId `"denisshare`" -AccessToken `"Q==`" -Container  `"databaseap`" -Path `"I:\MSSQL_BACKUP`"  -FileName `"$fileName`""

Invoke-D365AzureStorageDownload -AccountId "sharedwe" -AccessToken "iYMomVkAUrYXd63fMNzQ==" -Container  "trudtemp" -Path "I:\MSSQL_BACKUP"  -FileName "AxDB_20210925.bak"
#--------------------------------

#RESTORE TIER1 DB on TIER1
#----------------------------
Stop-D365Environment -All
Restore-SqlDatabase -ServerInstance "." -Database "testDB" -BackupFile "c:\sql\testDB.bak"
Switch-D365ActiveDatabase -NewDatabaseName "GOLDEN"
Invoke-D365DBSync -ShowOriginalProgress
Start-D365Environment -OnlyStartTypeAutomatic -ShowOriginalProgress
#----------------------------

# SQL update userinfo set enable= 1
CREATE USER [axdbadmin] FOR LOGIN [axdbadmin2] WITH DEFAULT_SCHEMA=[dbo]
ALTER DATABASE [GOLDEN] SET AUTO_CLOSE OFF WITH NO_WAIT

$RelocateData = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile("AXDBBuild_Data", "F:\MSSQL_DATA\AxDB_20230125.mdf")
$RelocateLog = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile("AXDBBuild_Log", "G:\MSSQL_LOGS\AxDB_20230125.ldf")
Restore-SqlDatabase -ServerInstance "." -Database "AxDB_20230125" -BackupFile "I:\MSSQL_BACKUP\AxDB_20230125.bak" -RelocateFile @($RelocateData,$RelocateLog)

Get-D365Url

#TRANSFER TO TIER2
#----------------------------
#https://docs.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/database/dbmovement-scenario-goldenconfig
New-D365Bacpac -ExportModeTier1 -BackupDirectory C:\AAA\PackagesBackpack\ -NewDatabaseName GOLD_220706 -BacpacFile "C:\AAA\PackagesBackpack\GOLD_220706.bacpac"  -MaxParallelism 32 -EnableException
#----------------------------

#DEPLOY REPORTS
#------------------------
Enable-D365Exception
Get-D365Model -CustomizableOnly -ExcludeMicrosoftModels -ExcludeBinaryModels | Invoke-D365ModuleCompile | Get-D365CompilerResult -OutputAsObjects
Get-D365Model -CustomizableOnly -ExcludeMicrosoftModels -ExcludeBinaryModels | Invoke-D365ProcessModule -ExecuteSync -ExecuteDeployReports
foreach ($model in Get-D365Model -CustomizableOnly -ExcludeMicrosoftModels -ExcludeBinaryModels)  #-Name "AAA"
{
    Invoke-D365ProcessModule -Module $model.Module  -ExecuteDeployReports 
}

#----------------------------------------------------------------------------------
#RESTORE TIER2 TO TIER1
#Invoke-D365InstallAzCopy
#Invoke-D365InstallSqlPackage

$fileDB = "UAT_" + (Get-Date -Format "yyyy_MM_dd")
$filePath = "I:\MSSQL_BACKUP\" + $fileDB
$filePath

$filePathpac = $filePath +  ".bacpac"
$filePathpac

#prepare the database
Enable-D365Exception
Invoke-D365AzCopyTransfer -SourceUri "SAS link from LCS Here" -DestinationUri $filePathpac

$StartTime = get-date 
WRITE-HOST $StartTime
WRITE-HOST "Execute to speed up: ALTER DATABASE [$($fileDB)] SET DELAYED_DURABILITY = FORCED WITH NO_WAIT"
WRITE-HOST "ALTER DATABASE [$($fileDB)] SET RECOVERY SIMPLE WITH NO_WAIT"
Import-D365Bacpac  -BacpacFile $filePathpac -ImportModeTier1 -NewDatabaseName $fileDB 
$RunTime = New-TimeSpan -Start $StartTime -End (get-date) 
WRITE-HOST "Execution time was $($RunTime.Hours) hours, $($RunTime.Minutes) minutes, $($RunTime.Seconds) seconds" 

Invoke-Sqlcmd -ServerInstance "." -Database $fileDB -Query "update userinfo set enable= 1"  -Verbose
Invoke-Sqlcmd -ServerInstance "." -Database "master" -Query ("ALTER DATABASE [" + $fileDB+ "] SET RECOVERY SIMPLE WITH NO_WAIT")  -Verbose

Stop-D365Environment -All

Backup-SqlDatabase -ServerInstance "." -Database "AxDB" -BackupFile ("I:\MSSQL_BACKUP\AxDBOld" + (Get-Date -Format "yyyyMMdd") + ".bak")  -CopyOnly -CompressionOption On -Initialize -NoRewind 
#invoke-sqlcmd -ServerInstance "."  -Query "alter database AxDB set single_user with rollback immediate; Drop database AxDB;"
invoke-sqlcmd -ServerInstance "."  -Query "IF DB_ID('AxDB_original') IS NOT NULL BEGIN ALTER DATABASE AxDB_original set single_user with rollback immediate; DROP DATABASE AxDB_original; END;"

Switch-D365ActiveDatabase -NewDatabaseName $fileDB
Invoke-D365DBSync -ShowOriginalProgress
Start-D365Environment -OnlyStartTypeAutomatic -ShowOriginalProgress
Invoke-D365DataFlush -Class SysFlushData
#-------------------------------------------------------------------------------------

#IMPORT USERS
#---------------------------------
Import-D365ExternalUser -Id "John" -Name "John Doe" -Email "John@contoso.com" -Company "DAT"
Import-D365AadUser -Users test@e-s.dk
#---------------------------------

#RUN JOB
#---------------------------------
https://dev01f5f85473588b3ae9devaos.axcloud.dynamics.com/?mi=SysClassRunner&prt=initial&cls=DEVPopulateReports

#INSTALL SOFTWARE PACKAGE
#---------------------------------
Invoke-D365SDPInstall -Path C:\AAA\Finance_10_28 -Command RunAll -Verbose
#Invoke-D365SDPInstall -Path C:\AAA\Finance_10_28 -Command ReRunStep -Step 25 -Verbose
#---------------------------------

#SQL SNAPSHOT CREATE AND RESTORE
#---------------------------------
--Create snapshot
CREATE DATABASE AxDB_MyReserveCase ON  
( NAME = UAT2022_1124, FILENAME =   
'J:\MSSQL_BACKUP\AxDB_MyReserveCase.ss' )  
AS SNAPSHOT OF AxDB;  
 
--Restore from snapshot
ALTER DATABASE AxDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
RESTORE DATABASE AxDB from   
DATABASE_SNAPSHOT = 'AxDB_MyReserveCase';  
ALTER DATABASE AxDB SET MULTI_USER;

#----------------------------------------
#RESTORE REPLY URL
# Using tenant admin account under this tenant login to via AzureAD PowerShell cmdlet. 
Install-Module AzureAD
Connect-AzureAD 
# Get Service Principal details 
$SP = Get-AzureADServicePrincipal -Filter "AppId eq '00000015-0000-0000-c000-000000000000'" ##REPLACE AAD REALM VALUE WITH VALUE IN AOS SERVICE UNDER WEB CONFIG
#Add Reply URLs 
$SP.ReplyUrls.Add("https://xxxc099devaos.axcloud.dynamics.com") #REPLACE ENV URL WITH ENV URL UNDER INFRA URL IN AOS SERVICE
$SP.ReplyUrls.Add("https://xxxc099devaos.axcloud.dynamics.com/oauth") ##DO NOT REMOVE THE /OAUTH JUST REPLACE THE ENV URL
#Set/Update Reply URL 
Set-AzureADServicePrincipal -ObjectId $SP.ObjectId -ReplyUrls $SP.ReplyUrls

#------------------------------------
#DELETE WORKSPACE
cd C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer
tf workspaces /owner:* /computer:devb5add42
tf workspace /delete /collection:https://dev.azure.com/allclient "devb5add-1;Denis"
