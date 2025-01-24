# Microsoft published list of common first party apps can be found here:
# https://docs.microsoft.com/en-us/azure/active-directory/develop/reference-app-manifest
# Original list as a string
$applications = @"
ACOM Azure Website	23523755-3a2b-41ca-9315-f81f3f566a95
ADIbizaUX	74658136-14ec-4630-ad9b-26e160ff0fc6
AEM-DualAuth	69893ee3-dd10-4b1c-832d-4870354be3d8
App Service	7ab7862c-4c57-491e-8a45-d52a7e023983
ASM Campaign Servicing	0cb7b9ec-5336-483b-bc31-b15b5788de71
Azure Advanced Threat Protection	7b7531ad-5926-4f2d-8a1d-38495ad33e17
Azure Data Lake	e9f49c6b-5ce5-44c8-925d-015017e9f7ad
"@

# Convert to PowerShell hash table format
$hashTable = "@{`n"
$applications -split "`n" | ForEach-Object {
    if ($_ -match "^(.+?)\s+([0-9a-f\-]{36})$") {
        $name = $matches[1]
        $id = $matches[2]
        $hashTable += "    `"$id`" = `"$name`"`n"
    }
}
$hashTable += "}"

# Output the result
Write-Output $hashTable

# Copy console output into knownApps.txt