we need to write an app that exctract some information from D365FO source code files(from the local K:\AosService\PackagesLocalDirectory\ directory)
we need an CSV file with the following columns
To get this info search all sub directories in K:\AosService\PackagesLocalDirectory\ on a local VM

Then do the following: 
# 1.Getting ShowParentModule property

## 1.1 process menus
Search subdirectories with AxMenu name and .xml files inside it
e.g. directory name may be K:\AosService\PackagesLocalDirectory\ApplicationSuite\Foundation\AxMenu with .xml files 
for each xml file check xml structure inside it and search for AxMenuElement tag. Example below 

<?xml version="1.0" encoding="utf-8"?>
<AxMenu xmlns:i="http://www.w3.org/2001/XMLSchema-instance" xmlns="Microsoft.Dynamics.AX.Metadata.V1">
	<Name>AccountsPayable</Name>
	<Label>@SYS333874</Label>
	<SetCompany>Yes</SetCompany>
	<Elements>
		<AxMenuElement xmlns=""
			i:type="AxMenuElementSubMenu">
			<Name>Vendors</Name>
			<Label>@SYS333876</Label>
			<Elements>
				<AxMenuElement xmlns=""
					i:type="AxMenuElementMenuItem">
					<Name>VendTableListPage</Name>
					<DisplayInContentArea>Yes</DisplayInContentArea>
					<MenuItemName>VendTableListPage</MenuItemName>
					<ShowParentModule>No</ShowParentModule>
				</AxMenuElement>
				<AxMenuElement xmlns=""
					i:type="AxMenuElementMenuItem">
					<Name>VendTableHoldListPage</Name>
					<DisplayInContentArea>Yes</DisplayInContentArea>
					<MenuItemName>VendTableHoldListPage</MenuItemName>
					<ShowParentModule>No</ShowParentModule>
					<MenuItemType>Action</MenuItemType>
				</AxMenuElement>
				....
				
From this file exctract the following info
AxMenu - from the first tag in a file <Name>AccountsPayable</Name>, so it should be AccountsPayable, for all records in file it will be the same
then analyse all <AxMenuElement> tags and exctract the following:
<MenuItemName>VendTableListPage</MenuItemName> e.g. VendTableListPage and 	
<ShowParentModule>No</ShowParentModule> - it can be either No or yes, if missing then <ShowParentModule> = Yes for this <MenuItemName><MenuItemType>Action</MenuItemType>  - in this case it will be Action, if the tag is missing it will be Display		

## 1.2 process menus extensions
Search subdirectories from K:\AosService\PackagesLocalDirectory\ with AxMenuExtension name and .xml files inside it
e.g. directory name may be K:\AosService\PackagesLocalDirectory\ApplicationSuite\Foundation\AxMenuExtension with .xml files 
for each xml file check xml structure inside it and search for AxMenuExtensionElement tag. Example below 

<?xml version="1.0" encoding="utf-8"?>
<AxMenuExtension xmlns:i="http://www.w3.org/2001/XMLSchema-instance" xmlns="Microsoft.Dynamics.AX.Metadata.V1">
	<Name>GeneralLedger.ApplicationSuite</Name>
	<Customizations />
	<Elements>
		<AxMenuExtensionElement xmlns="">
			<Parent>JournalEntries</Parent>
			<PositionType>Begin</PositionType>
			<MenuElement xmlns=""
				i:type="AxMenuElementMenuItem">
				<Name>GeneralJournals</Name>
				<MenuItemName>LedgerJournalTable3</MenuItemName>
				<ShowParentModule>No</ShowParentModule>
			</MenuElement>
		</AxMenuExtensionElement>
		<AxMenuExtensionElement xmlns="">
			<Parent>JournalEntries</Parent>
			<PositionType>Begin</PositionType>
			<MenuElement xmlns=""
				i:type="AxMenuElementMenuItem">
				<Name>GlobalGeneralJournals</Name>
				<MenuItemName>LedgerJournalTableDailyGlobal</MenuItemName>
			</MenuElement>
AxMenu:  from the first tag in a file <Name>GeneralLedger.ApplicationSuite</Name>, so it should be GeneralLedger.ApplicationSuite, for all records in file it will be the same
then analyse all <AxMenuExtensionElement> tags and exctract the following:
MenuItemName:     <MenuItemName>LedgerJournalTable3</MenuItemName> e.g. VendTableListPage and 	
ShowParentModule:  <ShowParentModule>No</ShowParentModule> - it can be either No or yes, if missing then <ShowParentModule> = Yes for this <MenuItemName>
MenuItemType: <MenuItemType>Action</MenuItemType>  - in this case it will be Action, if the tag is missing it will be Display		
	
save the result to a file 
	
# 2. Getting menu item info

then you need to find the object linked to this menu items
You need to build the list of all menu items by processing xml files from the follwing sub directories from K:\AosService\PackagesLocalDirectory\
AxMenuItemAction, AxMenuItemDisplay, AxMenuItemOutput. (e.g. K:\AosService\PackagesLocalDirectory\ApplicationSuite\Foundation\AxMenuItemAction)

xml file example for AxMenuItemAction directory:

<?xml version="1.0" encoding="utf-8"?>
<AxMenuItemAction xmlns:i="http://www.w3.org/2001/XMLSchema-instance" xmlns="Microsoft.Dynamics.AX.Metadata.V1">
	<Name>AgreementSettleCustFreeInvoice_RU</Name>
	<ConfigurationKey>TradeBlanketOrder</ConfigurationKey>
	<CountryRegionCodes>RU</CountryRegionCodes>
	<DisabledImageLocation>Symbol</DisabledImageLocation>
	<DisabledResource>0</DisabledResource>
	<EnumParameter>Yes</EnumParameter>
	<EnumTypeParameter>NoYes</EnumTypeParameter>
	<Label>@GLS104719</Label>
	<LinkedPermissionObject>CustFreeInvoice</LinkedPermissionObject>
	<LinkedPermissionType>Form</LinkedPermissionType>
	<MaintainUserLicense>Enterprise</MaintainUserLicense>
	<NormalResource>0</NormalResource>
	<Object>AgreementSettle_RU</Object>
	<ObjectType>Class</ObjectType>
	<ViewUserLicense>Universal</ViewUserLicense>
</AxMenuItemAction>

from this exctract the following info
MenuItemName: <Name>AgreementSettleCustFreeInvoice_RU</Name>, result: AgreementSettleCustFreeInvoice_RU
MenuItemType: Action
Label: from <Label>@GLS104719</Label> result: @GLS104719
Object: from <Object>AgreementSettle_RU</Object> result: AgreementSettle_RU
ObjectType:  from <ObjectType>Class</ObjectType> result:Class. If <ObjectType> is missing, then Result is Form

xml file example for AxMenuItemDisplay directory:

<?xml version="1.0" encoding="utf-8"?>
<AxMenuItemDisplay xmlns:i="http://www.w3.org/2001/XMLSchema-instance" xmlns="Microsoft.Dynamics.AX.Metadata.V1">
	<Name>AccountingDistMarkupTransInv</Name>
	<ConfigurationKey>LedgerBasic</ConfigurationKey>
	<DisabledResource>0</DisabledResource>
	<Label>@SYS304290</Label>
	<LinkedPermissionObject>AccountingDistribution</LinkedPermissionObject>
	<LinkedPermissionType>Form</LinkedPermissionType>
	<MaintainUserLicense>Enterprise</MaintainUserLicense>
	<NormalResource>0</NormalResource>
	<Object>AccDistFormDisplay</Object>
	<ObjectType>Class</ObjectType>
	<ViewUserLicense>Universal</ViewUserLicense>
</AxMenuItemDisplay>

from this exctract the following info
MenuItemName: <Name>AccountingDistMarkupTransInv</Name>, result: AccountingDistMarkupTransInv
MenuItemType: Display
Label: from <Label>@SYS304290</Label> result: @SYS304290
Object: from <Object>AccDistFormDisplay</Object> result: AccDistFormDisplay
ObjectType:  from <ObjectType>Class</ObjectType> result:Class. If <ObjectType> is missing, then Result is Form

xml file example for AxMenuItemOutput directory:

<?xml version="1.0" encoding="utf-8"?>
<AxMenuItemOutput xmlns:i="http://www.w3.org/2001/XMLSchema-instance" xmlns="Microsoft.Dynamics.AX.Metadata.V1">
	<Name>AssetAcquisition</Name>
	<ConfigurationKey>Asset</ConfigurationKey>
	<DisabledResource>0</DisabledResource>
	<Label>@SYS67638</Label>
	<LinkedPermissionObject>AssetAcquisition</LinkedPermissionObject>
	<LinkedPermissionObjectChild>Report</LinkedPermissionObjectChild>
	<LinkedPermissionType>SSRSReport</LinkedPermissionType>
	<MaintainUserLicense>Enterprise</MaintainUserLicense>
	<NormalResource>0</NormalResource>
	<Object>AssetAcquisitionController</Object>
	<ObjectType>Class</ObjectType>
	<ViewUserLicense>Universal</ViewUserLicense>
</AxMenuItemOutput>

from this exctract the following info
MenuItemName: <Name>AssetAcquisition</Name>, result: AssetAcquisition
MenuItemType: Output
Label: from <Label>@SYS67638</Label> result: @SYS67638
Object: from <Object>AssetAcquisitionController</Object> result: AssetAcquisitionController
ObjectType:  from <ObjectType>Class</ObjectType> result:Class. If <ObjectType> is missing, then Result is Form


# 3. Getting the label text
Labels values may be the following "@ApplicationFoundation:FieldDescriptionsCaption" OR "@SYS25739" or just some text(without @).
To extract the text, you need the following (if no @ at the start - return label text)

analyse all labels files that are .txt files located in the following subfolders "\AxLabelFile\LabelResources\en-AU\" for K:\AosService\PackagesLocalDirectory\ e.g. 
K:\AosService\PackagesLocalDirectory\ApplicationSuite\Foundation\AxLabelFile\LabelResources\en-AU

label file structure may be different 

One example:

@DMF0=Label files created on 26/5/2012
 ;By user Admin
@DMF1=Function that generates asset activity code
@DMF10=This table contains code page values
@DMF100=Entity attributes

line starts with " ;" can be just skipped, it is a comment
for all other @DMF1 is a label, "Function that generates asset activity code" is a label text

another label file example, file name is ApplicationFoundation.en-AU.label.txt

ActiveDirectoryUsers=Microsoft Entra ID Users
 ;SysUserMSODSUserImport.MSODSUsersTabPage AD caption
AdjustSystemJobParameters=Adjust system job parameters
 ;Title for SystemJobParameters form
AdminAccountEditNotSupported=Modifications to 'Admin' account fields Email, Provider, Enabled, SID and Object ID must be performed by customer service or through the Admin User Provisioning tool.
 ;Error displayed when admin account edit is attempted.
 
 in this case 
 line starts with " ;" can be just skipped, it is a comment
 for this line ActiveDirectoryUsers=Microsoft Entra ID Users, label id will be "ApplicationFoundation:ActiveDirectoryUsers" with the text "Microsoft Entra ID Users", so if no @symbol in the label file the label id is defined as a "first file name before the first dot" + value from the file before =
 
 # 4. combining results of 1. and 2.

when you execute p.1 you will get the following list:
AxMenu
MenuItemName
ShowParentModule
MenuItemType (it can be either Action, Display, Output)

When you execute p.2
MenuItemName
MenuItemType
Label
Object
ObjectType
if MenuItemName + MenuItemType are the same use the first values

add to every record from 1 the info from 2 using MenuItemName + MenuItemType link. if MenuItemName + MenuItemType are the same in the second list, use the first values

and procude the following csv file:
AxMenu
MenuItemName
ShowParentModule
MenuItemType
Object
ObjectType
Label
LabelText (the logic in defined in  p."3. Getting the label text")