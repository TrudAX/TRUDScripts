cd C:\FinancialReporting\Server\MRDeploy\

Import-Module -Name C:\FinancialReporting\Server\MRDeploy\MRDeploy.psm1 -Verbose

Get-MRDefaultValues

Set-MRDefaultValues -SettingName AXDatabaseName -SettingValue AxDB
Set-MRDefaultValues -SettingName AosUserName -SettingValue AOSUser
Set-MRDefaultValues -SettingName AosUserPassword -SettingValue AOSWebSite@123
Set-MRDefaultValues -SettingName AosWebsiteName -SettingValue AOSService
Set-MRDefaultValues -SettingName MRSqlUserName -SettingValue AOSUser
Set-MRDefaultValues -SettingName MRSqlUserPassword -SettingValue AOSWebSite@123
Set-MRDefaultValues -SettingName MRSqlRuntimeUserName -SettingValue AOSUser
Set-MRDefaultValues -SettingName MRSqlRuntimeUserPassword -SettingValue AOSWebSite@123
Set-MRDefaultValues -SettingName DDMSqlUserName -SettingValue AOSUser
Set-MRDefaultValues -SettingName DDMSqlUserPassword -SettingValue AOSWebSite@123
Set-MRDefaultValues -SettingName DDMSqlRuntimeUserName -SettingValue AOSUser
Set-MRDefaultValues -SettingName DDMSqlRuntimeUserPassword -SettingValue AOSWebSite@123
Set-MRDefaultValues -SettingName AXSqlUserName -SettingValue AOSUser
Set-MRDefaultValues -SettingName AXSqlUserPassword -SettingValue AOSWebSite@123
Set-MRDefaultValues -SettingName AXSqlRuntimeUserName -SettingValue AOSUser
Set-MRDefaultValues -SettingName AXSqlRuntimeUserPassword -SettingValue AOSWebSite@123

New-MRSetup  -IntegrateDDM 
