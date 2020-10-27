<# This script uses Graph API to connect to Azure, and upload MSI file of
your chosing, it will repeat this task for all tenants that you set in the $accounts variable,
it will take your password, store it as a secured file, and for each loop, it will convert that file
to a file called Credential.txt as a plain text, as the login procedure requires it, as soon as it is
used to create a token, the unsecure file is deleted, at at the end of the script, the secured file "credentials.txt" is also deleted
#>
[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic') | Out-Null
#$output = [Microsoft.VisualBasic.Interaction]::InputBox("Enter Full application path", "Application Upload")
#$output = 'F:\MDT\Test-Environment\Applications\7 Zip\7z1602-x64.msi'

Function Get-FileName($initialDirectory)
{   
 [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") |
 Out-Null

 $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
 $OpenFileDialog.initialDirectory = $initialDirectory
 $OpenFileDialog.filter = "MSI (*.*)| *.MSI*"
 $OpenFileDialog.ShowDialog() | Out-Null
 $OpenFileDialog.filename
} #end function Get-FileName

# *** Entry Point to Script ***

$output = Get-FileName -initialDirectory "c:fso"





if (!(Test-Path c:\credentials\)){
New-Item -path c:\credentials -type directory -Force
}

$files = Get-ChildItem -Path "c:\credentials\*.xml" | Import-Clixml
foreach ($file in $files) {

$Useremail = $file.username
$passwords = $file.Password

<#

.COPYRIGHT
Copyright (c) Microsoft Corporation. All rights reserved. Licensed under the MIT license.
See LICENSE in the project root for license information.

#>

####################################################

function Get-AuthToken {

<#
.SYNOPSIS
This function is used to authenticate with the Graph API REST interface
.DESCRIPTION
The function authenticate with the Graph API Interface with the tenant name
.EXAMPLE
Get-AuthToken
Authenticates you with the Graph API interface
.NOTES
NAME: Get-AuthToken
#>

[cmdletbinding()]

param
(
    [Parameter(Mandatory=$true)]
    $User,
    $Password
)

$userUpn = New-Object "System.Net.Mail.MailAddress" -ArgumentList $User

$tenant = $userUpn.Host

Write-Host "Checking for AzureAD module..."

    $AadModule = Get-Module -Name "AzureAD" -ListAvailable

    if ($AadModule -eq $null) {

        Write-Host "AzureAD PowerShell module not found, looking for AzureADPreview"
        $AadModule = Get-Module -Name "AzureADPreview" -ListAvailable

    }

    if ($AadModule -eq $null) {
        write-host
        write-host "AzureAD Powershell module not installed..." -f Red
        write-host "Install by running 'Install-Module AzureAD' or 'Install-Module AzureADPreview' from an elevated PowerShell prompt" -f Yellow
        write-host "Script can't continue..." -f Red
        write-host
        exit
    }

# Getting path to ActiveDirectory Assemblies
# If the module count is greater than 1 find the latest version

    if($AadModule.count -gt 1){

        $Latest_Version = ($AadModule | select version | Sort-Object)[-1]

        $aadModule = $AadModule | ? { $_.version -eq $Latest_Version.version }

            # Checking if there are multiple versions of the same module found

            if($AadModule.count -gt 1){

            $aadModule = $AadModule | select -Unique

            }

        $adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
        $adalforms = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"

    }

    else {

        $adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
        $adalforms = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"

    }

[System.Reflection.Assembly]::LoadFrom($adal) | Out-Null

[System.Reflection.Assembly]::LoadFrom($adalforms) | Out-Null

$clientId = "d1ddf0e4-d672-4dae-b554-9d5bdfd93547"

$redirectUri = "urn:ietf:wg:oauth:2.0:oob"

$resourceAppIdURI = "https://graph.microsoft.com"

$authority = "https://login.microsoftonline.com/$Tenant"

    try {

    $authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority

    # https://msdn.microsoft.com/en-us/library/azure/microsoft.identitymodel.clients.activedirectory.promptbehavior.aspx
    # Change the prompt behaviour to force credentials each time: Auto, Always, Never, RefreshSession

    $platformParameters = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters" -ArgumentList "Auto"

    $userId = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.UserIdentifier" -ArgumentList ($User, "OptionalDisplayableId")

        if($Password -eq $null){

            $authResult = $authContext.AcquireTokenAsync($resourceAppIdURI,$clientId,$redirectUri,$platformParameters,$userId).Result

        }

        else {

            if(test-path "$Password"){

            $UserPassword =  get-Content "$Password" 

            $userCredentials = new-object Microsoft.IdentityModel.Clients.ActiveDirectory.UserPasswordCredential -ArgumentList $userUPN,$UserPassword

            $authResult = [Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContextIntegratedAuthExtensions]::AcquireTokenAsync($authContext, $resourceAppIdURI, $clientid, $userCredentials).Result;

            }

            else {

            Write-Host "Path to Password file" $Password "doesn't exist, please specify a valid path..." -ForegroundColor Red
            Write-Host "Script can't continue..." -ForegroundColor Red
            Write-Host
            break

            }

        }

        if($authResult.AccessToken){

        # Creating header for Authorization token

        $authHeader = @{
            'Content-Type'='application/json'
            'Authorization'="Bearer " + $authResult.AccessToken
            'ExpiresOn'=$authResult.ExpiresOn
            }

        return $authHeader

        }

        else {

        Write-Host
        Write-Host "Authorization Access Token is null, please re-run authentication..." -ForegroundColor Red
        Write-Host
        break

        }

    }

    catch {

    write-host $_.Exception.Message -f Red
    write-host $_.Exception.ItemName -f Red
    write-host
    break

    }

}

####################################################


function CloneObject($object){

	$stream = New-Object IO.MemoryStream;
	$formatter = New-Object Runtime.Serialization.Formatters.Binary.BinaryFormatter;
	$formatter.Serialize($stream, $object);
	$stream.Position = 0;
	$formatter.Deserialize($stream);
}

####################################################

function WriteHeaders($authToken){

	foreach ($header in $authToken.GetEnumerator())
	{
		if ($header.Name.ToLower() -eq "authorization")
		{
			continue;
		}

		Write-Host -ForegroundColor Gray "$($header.Name): $($header.Value)";
	}
}

####################################################

function MakeGetRequest($collectionPath){

	$uri = "$baseUrl$collectionPath";
	$request = "GET $uri";
	
	if ($logRequestUris) { Write-Host $request; }
	if ($logHeaders) { WriteHeaders $authToken; }

	try
	{
		$response = Invoke-RestMethod $uri -Method Get -Headers $authToken;
		$response;
	}
	catch
	{
		Write-Host -ForegroundColor Red $request;
		Write-Host -ForegroundColor Red $_.Exception.Message;
		throw;
	}
}

####################################################

function MakePatchRequest($collectionPath, $body){

	MakeRequest "PATCH" $collectionPath $body;

}

####################################################

function MakePostRequest($collectionPath, $body){

	MakeRequest "POST" $collectionPath $body;

}

####################################################

function MakeRequest($verb, $collectionPath, $body){

	$uri = "$baseUrl$collectionPath";
	$request = "$verb $uri";
	
	$clonedHeaders = CloneObject $authToken;
	$clonedHeaders["content-length"] = $body.Length;
	$clonedHeaders["content-type"] = "application/json";

	if ($logRequestUris) { Write-Host $request; }
	if ($logHeaders) { WriteHeaders $clonedHeaders; }
	if ($logContent) { Write-Host -ForegroundColor Gray $body; }

	try
	{
		$response = Invoke-RestMethod $uri -Method $verb -Headers $clonedHeaders -Body $body;
		$response;
	}
	catch
	{
		Write-Host -ForegroundColor Red $request;
		Write-Host -ForegroundColor Red $_.Exception.Message;
		throw;
	}
}

####################################################

function UploadAzureStorageChunk($sasUri, $id, $body){

	$uri = "$sasUri&comp=block&blockid=$id";
	$request = "PUT $uri";

	$iso = [System.Text.Encoding]::GetEncoding("iso-8859-1");
	$encodedBody = $iso.GetString($body);
	$headers = @{
		"x-ms-blob-type" = "BlockBlob"
	};

	if ($logRequestUris) { Write-Host $request; }
	if ($logHeaders) { WriteHeaders $headers; }

	try
	{
		$response = Invoke-WebRequest $uri -Method Put -Headers $headers -Body $encodedBody;
	}
	catch
	{
		Write-Host -ForegroundColor Red $request;
		Write-Host -ForegroundColor Red $_.Exception.Message;
		throw;
	}

}

####################################################

function FinalizeAzureStorageUpload($sasUri, $ids){

	$uri = "$sasUri&comp=blocklist";
	$request = "PUT $uri";

	$xml = '<?xml version="1.0" encoding="utf-8"?><BlockList>';
	foreach ($id in $ids)
	{
		$xml += "<Latest>$id</Latest>";
	}
	$xml += '</BlockList>';

	if ($logRequestUris) { Write-Host $request; }
	if ($logContent) { Write-Host -ForegroundColor Gray $xml; }

	try
	{
		Invoke-RestMethod $uri -Method Put -Body $xml;
	}
	catch
	{
		Write-Host -ForegroundColor Red $request;
		Write-Host -ForegroundColor Red $_.Exception.Message;
		throw;
	}
}

####################################################

function UploadFileToAzureStorage($sasUri, $filepath){

	# Chunk size = 1 MiB
    $chunkSizeInBytes = 1024 * 1024;

	# Read the whole file and find the total chunks.
	#[byte[]]$bytes = Get-Content $filepath -Encoding byte;
    # Using ReadAllBytes method as the Get-Content used alot of memory on the machine
    [byte[]]$bytes = [System.IO.File]::ReadAllBytes($filepath);
	$chunks = [Math]::Ceiling($bytes.Length / $chunkSizeInBytes);

	# Upload each chunk.
	$ids = @();
    $cc = 1

	for ($chunk = 0; $chunk -lt $chunks; $chunk++)
	{
        $id = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($chunk.ToString("0000")));
		$ids += $id;

		$start = $chunk * $chunkSizeInBytes;
		$end = [Math]::Min($start + $chunkSizeInBytes - 1, $bytes.Length - 1);
		$body = $bytes[$start..$end];

        Write-Progress -Activity "Uploading File to Azure Storage" -status "Uploading chunk $cc of $chunks" `
        -percentComplete ($cc / $chunks*100)
        $cc++

        $uploadResponse = UploadAzureStorageChunk $sasUri $id $body;


	}

    Write-Progress -Completed -Activity "Uploading File to Azure Storage"

    Write-Host

	# Finalize the upload.
	$uploadResponse = FinalizeAzureStorageUpload $sasUri $ids;
}

####################################################

function GenerateKey{

	try
	{
		$aes = [System.Security.Cryptography.Aes]::Create();
        $aesProvider = New-Object System.Security.Cryptography.AesCryptoServiceProvider;
        $aesProvider.GenerateKey();
        $aesProvider.Key;
	}
	finally
	{
		if ($aesProvider -ne $null) { $aesProvider.Dispose(); }
		if ($aes -ne $null) { $aes.Dispose(); }
	}
}

####################################################

function GenerateIV{

	try
	{
		$aes = [System.Security.Cryptography.Aes]::Create();
        $aes.IV;
	}
	finally
	{
		if ($aes -ne $null) { $aes.Dispose(); }
	}
}

####################################################

function EncryptFileWithIV($sourceFile, $targetFile, $encryptionKey, $hmacKey, $initializationVector){

	$bufferBlockSize = 1024 * 4;
	$computedMac = $null;

	try
	{
		$aes = [System.Security.Cryptography.Aes]::Create();
		$hmacSha256 = New-Object System.Security.Cryptography.HMACSHA256;
		$hmacSha256.Key = $hmacKey;
		$hmacLength = $hmacSha256.HashSize / 8;

		$buffer = New-Object byte[] $bufferBlockSize;
		$bytesRead = 0;

		$targetStream = [System.IO.File]::Open($targetFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read);
		$targetStream.Write($buffer, 0, $hmacLength + $initializationVector.Length);

		try
		{
			$encryptor = $aes.CreateEncryptor($encryptionKey, $initializationVector);
			$sourceStream = [System.IO.File]::Open($sourceFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read);
			$cryptoStream = New-Object System.Security.Cryptography.CryptoStream -ArgumentList @($targetStream, $encryptor, [System.Security.Cryptography.CryptoStreamMode]::Write);

			$targetStream = $null;
			while (($bytesRead = $sourceStream.Read($buffer, 0, $bufferBlockSize)) -gt 0)
			{
				$cryptoStream.Write($buffer, 0, $bytesRead);
				$cryptoStream.Flush();
			}
			$cryptoStream.FlushFinalBlock();
		}
		finally
		{
			if ($cryptoStream -ne $null) { $cryptoStream.Dispose(); }
			if ($sourceStream -ne $null) { $sourceStream.Dispose(); }
			if ($encryptor -ne $null) { $encryptor.Dispose(); }	
		}

		try
		{
			$finalStream = [System.IO.File]::Open($targetFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read)

			$finalStream.Seek($hmacLength, [System.IO.SeekOrigin]::Begin) > $null;
			$finalStream.Write($initializationVector, 0, $initializationVector.Length);
			$finalStream.Seek($hmacLength, [System.IO.SeekOrigin]::Begin) > $null;

			$hmac = $hmacSha256.ComputeHash($finalStream);
			$computedMac = $hmac;

			$finalStream.Seek(0, [System.IO.SeekOrigin]::Begin) > $null;
			$finalStream.Write($hmac, 0, $hmac.Length);
		}
		finally
		{
			if ($finalStream -ne $null) { $finalStream.Dispose(); }
		}
	}
	finally
	{
		if ($targetStream -ne $null) { $targetStream.Dispose(); }
        if ($aes -ne $null) { $aes.Dispose(); }
	}

	$computedMac;
}

####################################################

function EncryptFile($sourceFile, $targetFile){

	$encryptionKey = GenerateKey;
	$hmacKey = GenerateKey;
	$initializationVector = GenerateIV;

	# Create the encrypted target file and compute the HMAC value.
	$mac = EncryptFileWithIV $sourceFile $targetFile $encryptionKey $hmacKey $initializationVector;

	# Compute the SHA256 hash of the source file and convert the result to bytes.
	$fileDigest = (Get-FileHash $sourceFile -Algorithm SHA256).Hash;
	$fileDigestBytes = New-Object byte[] ($fileDigest.Length / 2);
    for ($i = 0; $i -lt $fileDigest.Length; $i += 2)
	{
        $fileDigestBytes[$i / 2] = [System.Convert]::ToByte($fileDigest.Substring($i, 2), 16);
    }
	
	# Return an object that will serialize correctly to the file commit Graph API.
	$encryptionInfo = @{};
	$encryptionInfo.encryptionKey = [System.Convert]::ToBase64String($encryptionKey);
	$encryptionInfo.macKey = [System.Convert]::ToBase64String($hmacKey);
	$encryptionInfo.initializationVector = [System.Convert]::ToBase64String($initializationVector);
	$encryptionInfo.mac = [System.Convert]::ToBase64String($mac);
	$encryptionInfo.profileIdentifier = "ProfileVersion1";
	$encryptionInfo.fileDigest = [System.Convert]::ToBase64String($fileDigestBytes);
	$encryptionInfo.fileDigestAlgorithm = "SHA256";

	$fileEncryptionInfo = @{};
	$fileEncryptionInfo.fileEncryptionInfo = $encryptionInfo;

	$fileEncryptionInfo;

}

####################################################

function WaitForFileProcessing($fileUri, $stage){

	$attempts= 60;
	$waitTimeInSeconds = 1;

	$successState = "$($stage)Success";
	$pendingState = "$($stage)Pending";
	$failedState = "$($stage)Failed";
	$timedOutState = "$($stage)TimedOut";

	$file = $null;
	while ($attempts -gt 0)
	{
		$file = MakeGetRequest $fileUri;

		if ($file.uploadState -eq $successState)
		{
			break;
		}
		elseif ($file.uploadState -ne $pendingState)
		{
			throw "File upload state is not success: $($file.uploadState)";
		}

		Start-Sleep $waitTimeInSeconds;
		$attempts--;
	}

	if ($file -eq $null)
	{
		throw "File request did not complete in the allotted time.";
	}

	$file;

}

####################################################


function GetMSIAppBody($displayName, $publisher, $description, $filename, $identityVersion, $ProductCode){

	$body = @{ "@odata.type" = "#microsoft.graph.windowsMobileMSI" };
	$body.displayName = $displayName;
	$body.publisher = $publisher;
	$body.description = $description;
	$body.fileName = $filename;
	$body.identityVersion = $identityVersion;
	$body.informationUrl = $null;
	$body.isFeatured = $false;
	$body.privacyInformationUrl = $null;
	$body.developer = ""; 
	$body.notes = "";
	$body.owner = "";
    $body.productCode = "$ProductCode";
    $body.productVersion = "$identityVersion";

	$body;
}

####################################################

function GetAppFileBody($name, $size, $sizeEncrypted, $manifest){

	$body = @{ "@odata.type" = "#microsoft.graph.mobileAppContentFile" };
	$body.name = $name;
	$body.size = $size;
	$body.sizeEncrypted = $sizeEncrypted;
	$body.manifest = $manifest;

	$body;
}

####################################################

function GetAppCommitBody($contentVersionId, $LobType){

	$body = @{ "@odata.type" = "#$LobType" };
	$body.committedContentVersion = $contentVersionId;

	$body;

}

####################################################

Function Get-MSIFileInformation(){

# https://www.scconfigmgr.com/2014/08/22/how-to-get-msi-file-information-with-powershell/

param(
    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [System.IO.FileInfo]$Path,
 
    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("ProductCode", "ProductVersion", "ProductName", "Manufacturer", "ProductLanguage", "FullVersion")]
    [string]$Property
)
Process {

    try {
        # Read property from MSI database
        $WindowsInstaller = New-Object -ComObject WindowsInstaller.Installer
        $MSIDatabase = $WindowsInstaller.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $WindowsInstaller, @($Path.FullName, 0))
        $Query = "SELECT Value FROM Property WHERE Property = '$($Property)'"
        $View = $MSIDatabase.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $MSIDatabase, ($Query))
        $View.GetType().InvokeMember("Execute", "InvokeMethod", $null, $View, $null)
        $Record = $View.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $View, $null)
        $Value = $Record.GetType().InvokeMember("StringData", "GetProperty", $null, $Record, 1)
 
        # Commit database and close view
        $MSIDatabase.GetType().InvokeMember("Commit", "InvokeMethod", $null, $MSIDatabase, $null)
        $View.GetType().InvokeMember("Close", "InvokeMethod", $null, $View, $null)           
        $MSIDatabase = $null
        $View = $null
 
        # Return the value
        return $Value
    }

    catch {

        Write-Warning -Message $_.Exception.Message;
        break;
    
    }

}

    End {
        # Run garbage collection and release ComObject
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($WindowsInstaller) | Out-Null
        [System.GC]::Collect()
    }

}

####################################################

Function Test-SourceFile(){

param
(
    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    $SourceFile
)

    try {

            if(!(test-path "$SourceFile")){

            Write-Host "Source File '$sourceFile' doesn't exist..." -ForegroundColor Red
            throw

            }

        }

    catch {

		Write-Host -ForegroundColor Red $_.Exception.Message;
        Write-Host
		break;

    }

}

####################################################




function Upload-MSILob(){

<#
.SYNOPSIS
This function is used to upload an MSI LOB Application to the Intune Service
.DESCRIPTION
This function is used to upload an MSI LOB Application to the Intune Service
.EXAMPLE
Upload-MSILob "C:\Software\Orca\Orca.Msi" -publisher "Microsoft" -description "Orca"
This example uses all parameters required to add an MSI Application into the Intune Service
.NOTES
NAME: Upload-MSILOB
#>

[cmdletbinding()]

param
(
    [parameter(Mandatory=$true,Position=1)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceFile,

    [parameter(Mandatory=$true,Position=2)]
    [ValidateNotNullOrEmpty()]
    [string]$publisher,

    [parameter(Mandatory=$true,Position=3)]
    [ValidateNotNullOrEmpty()]
    [string]$description
)

	try	{

        $LOBType = "microsoft.graph.windowsMobileMSI"

        Write-Host "Testing if SourceFile '$SourceFile' Path is valid..." -ForegroundColor Yellow
        Test-SourceFile "$SourceFile"

        $MSIPath = "$SourceFile"

        # Creating temp file name from Source File path
        $tempFile = [System.IO.Path]::GetDirectoryName("$SourceFile") + "\" + [System.IO.Path]::GetFileNameWithoutExtension("$SourceFile") + "_temp.bin"

        Write-Host
        Write-Host "Creating JSON data to pass to the service..." -ForegroundColor Yellow

        $FileName = [System.IO.Path]::GetFileName("$MSIPath")

        $PN = (Get-MSIFileInformation -Path "$MSIPath" -Property ProductName | Out-String).trimend()
        $PC = (Get-MSIFileInformation -Path "$MSIPath" -Property ProductCode | Out-String).trimend()
        $PV = (Get-MSIFileInformation -Path "$MSIPath" -Property ProductVersion | Out-String).trimend()
        $PL = (Get-MSIFileInformation -Path "$MSIPath" -Property ProductLanguage | Out-String).trimend()

		# Create a new MSI LOB app.
		$mobileAppBody = GetMSIAppBody -displayName "$PN" -publisher "$publisher" -description "$description" -filename "$FileName" -identityVersion "$PV" -ProductCode "$PC"
        
        Write-Host
        Write-Host "Creating application in Intune..." -ForegroundColor Yellow
		$mobileApp = MakePostRequest "mobileApps" ($mobileAppBody | ConvertTo-Json);

		# Get the content version for the new app (this will always be 1 until the new app is committed).
        Write-Host
        Write-Host "Creating Content Version in the service for the application..." -ForegroundColor Yellow
		$appId = $mobileApp.id;
		$contentVersionUri = "mobileApps/$appId/$LOBType/contentVersions";
		$contentVersion = MakePostRequest $contentVersionUri "{}";

        # Encrypt file and Get File Information
        Write-Host
        Write-Host "Ecrypting the file '$SourceFile'..." -ForegroundColor Yellow
        $encryptionInfo = EncryptFile $sourceFile $tempFile;
        $Size = (Get-Item "$sourceFile").Length
        $EncrySize = (Get-Item "$tempFile").Length

        Write-Host
        Write-Host "Creating the manifest file used to install the application on the device..." -ForegroundColor Yellow

        [xml]$manifestXML = '<MobileMsiData MsiExecutionContext="Any" MsiRequiresReboot="false" MsiUpgradeCode="" MsiIsMachineInstall="true" MsiIsUserInstall="false" MsiIncludesServices="false" MsiContainsSystemRegistryKeys="false" MsiContainsSystemFolders="false"></MobileMsiData>'

        $manifestXML.MobileMsiData.MsiUpgradeCode = "$PC"

        $manifestXML_Output = $manifestXML.OuterXml.ToString()

        $Bytes = [System.Text.Encoding]::ASCII.GetBytes($manifestXML_Output)
        $EncodedText =[Convert]::ToBase64String($Bytes)

		# Create a new file for the app.
        Write-Host
        Write-Host "Creating a new file entry in Azure for the upload..." -ForegroundColor Yellow
		$contentVersionId = $contentVersion.id;
		$fileBody = GetAppFileBody "$FileName" $Size $EncrySize "$EncodedText";
		$filesUri = "mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files";
		$file = MakePostRequest $filesUri ($fileBody | ConvertTo-Json);
	
		# Wait for the service to process the new file request.
        Write-Host
        Write-Host "Waiting for the file entry URI to be created..." -ForegroundColor Yellow
		$fileId = $file.id;
		$fileUri = "mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files/$fileId";
		$file = WaitForFileProcessing $fileUri "AzureStorageUriRequest";

		# Upload the content to Azure Storage.
        Write-Host
        Write-Host "Uploading file to Azure Storage..." -f Yellow

		$sasUri = $file.azureStorageUri;
		UploadFileToAzureStorage $file.azureStorageUri $tempFile;

		# Commit the file.
        Write-Host
        Write-Host "Committing the file into Azure Storage..." -ForegroundColor Yellow
		$commitFileUri = "mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files/$fileId/commit";
		MakePostRequest $commitFileUri ($encryptionInfo | ConvertTo-Json);

		# Wait for the service to process the commit file request.
        Write-Host
        Write-Host "Waiting for the service to process the commit file request..." -ForegroundColor Yellow
		$file = WaitForFileProcessing $fileUri "CommitFile";

		# Commit the app.
        Write-Host
        Write-Host "Committing the file into Azure Storage..." -ForegroundColor Yellow
		$commitAppUri = "mobileApps/$appId";
		$commitAppBody = GetAppCommitBody $contentVersionId $LOBType;
		MakePatchRequest $commitAppUri ($commitAppBody | ConvertTo-Json);

        Write-Host "Removing Temporary file '$tempFile'..." -f Gray
        Remove-Item -Path "$tempFile" -Force
        Write-Host

        Write-Host "Sleeping for $sleep seconds to allow patch completion..." -f Magenta
        Start-Sleep $sleep
        Write-Host

	}
	
    catch {

		Write-Host "";
		Write-Host -ForegroundColor Red "Aborting with exception: $($_.Exception.ToString())";
	
    }

}

####################################################


#region Authentication

$Ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($passwords)
$result = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($Ptr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeCoTaskMemUnicode($Ptr)

$passtosecure = $result

#$SecurePassword = Read-Host -AsSecureString $result
$passtosecure | Out-File "c:\credentials\credentials.txt"

$User = $Useremail
#$PasswordFile = Read-Host -Prompt "Please specify your user password for Azure Authentication" | Out-File c:\credentials\credentials.txt

#$SecurePassword = Get-Content "c:\credentials\credentials.txt" | ConvertTo-SecureString
#$UnsecurePassword = (New-Object PSCredential "user",$SecurePassword).GetNetworkCredential().Password | Out-File c:\credentials\credential.txt


$Password = "c:\credentials\credentials.txt"

$global:authToken = Get-AuthToken -User $User -Password "$Password"

remove-item -Path "c:\credentials\credentials.txt"

####################################################



Write-Host

# Path to Android SDK Location to find aapt.exe tool if you don't specify identityName or identityVersion
# Note: Don't specify direct location to build folder number, just to the build-tools folder as the script will find the latest SDK installed
$AndroidSDKLocation = "C:\AndroidSDK\build-tools"

$baseUrl = "https://graph.microsoft.com/beta/deviceAppManagement/"

$logRequestUris = $true;
$logHeaders = $false;
$logContent = $true;

$sleep = 30

####################################################

#### MSI Install microsoft Teams 64 bit

$MSI_INFO = [Microsoft.VisualBasic.Interaction]::InputBox("Please enter Msi Description", "Details") 

Upload-MSILob "$output" -publisher "Microsoft" -description $MSI_INFO

}

