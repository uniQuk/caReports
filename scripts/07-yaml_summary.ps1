# Requires powershell-yaml module
# Import-Module powershell-yaml

$basePath = Split-Path -Path $PSScriptRoot -Parent
$cleanPath = Join-Path $basePath "policies/yaml/clean"
$docsPath = Join-Path $basePath "analysis/markdown"

# Create docs directory
$null = New-Item -ItemType Directory -Force -Path $docsPath

function Format-DateTime {
    param($dateTimeString)
    if ([string]::IsNullOrEmpty($dateTimeString)) {
        return "N/A"
    }
    try {
        return ([DateTime]$dateTimeString).ToString("dd-MM-yyyy HH:mm")
    }
    catch {
        return "Invalid date"
    }
}

function Format-PolicyValue {
    param($value)
    if ($null -eq $value) { return $null }
    
    if ($value -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $value.Keys) {
            $formattedValue = Format-PolicyValue $value[$key]
            if ($null -ne $formattedValue) {
                $result[$key] = $formattedValue
            }
        }
        return $result
    }
    elseif ($value -is [array]) {
        return @($value | Where-Object { $null -ne $_ })
    }
    else {
        return $value
    }
}

function Format-PropertyDetails {
    param(
        [string]$propertyName,
        $propertyValue,
        [int]$indentLevel = 0
    )
    
    if ($null -eq $propertyValue -or $propertyValue -eq '') {
        return $null
    }
    
    $indent = "  " * $indentLevel
    $details = ""
    
    if ($propertyValue -is [System.Collections.IDictionary]) {
        $details += "`n$indent- **$propertyName**:"
        foreach ($item in $propertyValue.GetEnumerator() | Where-Object { $null -ne $_.Value }) {
            $subDetails = Format-PropertyDetails -propertyName $item.Key -propertyValue $item.Value -indentLevel ($indentLevel + 1)
            if ($subDetails) {
                $details += $subDetails
            }
        }
    }
    elseif ($propertyValue -is [array]) {
        if ($propertyValue.Count -gt 0) {
            $details += "`n$indent- **$propertyName**: $($propertyValue -join ', ')"
        }
    }
    else {
        $details += "`n$indent- **$propertyName**: $propertyValue"
    }
    
    return $details
}

function Get-PolicyDetails {
    param($policy, $fileName)
    
    $details = @"
### $($policy.displayName)
[🔼 Back to top](#table-of-contents)

- **File**: $fileName _(Original: $($policy.displayName))_
- **State**: $($policy.state)
- **Created**: $(Format-DateTime $policy.createdDateTime)
- **Modified**: $(if ($policy.modifiedDateTime) { Format-DateTime $policy.modifiedDateTime } else { "Never" })
- **ID**: $($policy.id)
"@

    # Process all policy properties except basic info
    $excludeProperties = @('displayName', 'state', 'createdDateTime', 'modifiedDateTime', 'id', 'Keys', 'Values', 'Count')
    
    foreach ($prop in $policy.PSObject.Properties) {
        if ($prop.Name -notin $excludeProperties -and $null -ne $prop.Value) {
            $formattedValue = Format-PolicyValue $prop.Value
            if ($null -ne $formattedValue) {
                $details += Format-PropertyDetails -propertyName $prop.Name -propertyValue $formattedValue
            }
        }
    }

    $details += "`n`n"
    return $details
}

# Read all policies
$policies = @()
Get-ChildItem -Path $cleanPath -Filter "*.yaml" | ForEach-Object {
    $yamlContent = Get-Content $_.FullName -Raw
    $policy = ConvertFrom-Yaml $yamlContent
    $policies += $policy
}

# Sort policies by display name
$policies = $policies | Sort-Object { $_.displayName }

# Generate table of contents
$toc = "## Table of Contents`n`n"
foreach ($policy in $policies) {
    $toc += "- [$($policy.displayName)](#$($policy.displayName.ToLower() -replace '[^a-z0-9\s-]','' -replace '\s','-'))`n"
}

# Generate main documentation
$documentation = @"
# Conditional Access Policies

$toc

# Detailed Policy Documentation

"@

foreach ($policy in $policies) {
    $documentation += "`n$(Get-PolicyDetails $policy)"
}

$documentation | Out-File (Join-Path $docsPath "ca-summary.md") -Encoding UTF8

Write-Host "Documentation generated in $docsPath/ca-summary.md"
