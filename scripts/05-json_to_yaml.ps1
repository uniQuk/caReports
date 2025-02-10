# Install-Module powershell-yaml if not already installed
# Install-Module powershell-yaml -Scope CurrentUser
# Import-Module powershell-yaml

$basePath = Split-Path -Path $PSScriptRoot -Parent
$originalPath = Join-Path $basePath "policies/data"
$yamlPath = Join-Path $basePath "policies/yaml"

# Ensure we have write permissions and create directory
$null = New-Item -ItemType Directory -Force -Path $yamlPath
$acl = Get-Acl $yamlPath
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($currentUser, "FullControl", "Allow")
$acl.SetAccessRule($accessRule)
Set-Acl $yamlPath $acl

function Get-SafeFileName {
    param($originalName)
    
    $hash = [System.Security.Cryptography.MD5]::Create().ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($originalName)
    )
    $shortHash = [System.BitConverter]::ToString($hash).Replace("-", "").Substring(0, 8)
    return "CA_" + $shortHash + ".yaml"
}

# Create a manifest file to map short names to full names
$manifest = @{}

Get-ChildItem -Path $originalPath -Filter "*.json" | ForEach-Object {
    $jsonContent = Get-Content $_.FullName | ConvertFrom-Json
    
    # Generate safe filename
    $safeFileName = Get-SafeFileName $_.BaseName
    
    # Add to manifest
    $manifest[$safeFileName] = @{
        OriginalName = $_.BaseName
        PolicyDisplayName = $jsonContent.displayName
    }
    
    # Convert to YAML
    $yamlContent = $jsonContent | ConvertTo-Yaml
    
    # Create yaml file with safe name
    $outputPath = Join-Path $yamlPath $safeFileName
    $yamlContent | Out-File $outputPath -Encoding UTF8
    
    Write-Host "Converted $($_.Name) to $safeFileName"
}

# Save manifest
$manifestPath = Join-Path $yamlPath "policy_manifest.json"
$manifest | ConvertTo-Json | Out-File $manifestPath -Encoding UTF8