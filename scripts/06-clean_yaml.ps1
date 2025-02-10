# Requires powershell-yaml module
# Import-Module powershell-yaml

$basePath = Split-Path -Path $PSScriptRoot -Parent
$completePath = Join-Path $basePath "policies/yaml/complete"
$cleanPath = Join-Path $basePath "policies/yaml/clean"

# Create clean directory if it doesn't exist
$null = New-Item -ItemType Directory -Force -Path $cleanPath

function Remove-EmptyValues {
    param([object]$InputObject)
    
    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in @($InputObject.Keys)) {
            $value = Remove-EmptyValues $InputObject[$key]
            if ($null -ne $value -and $value -ne '' -and 
                (-not ($value -is [array] -and $value.Count -eq 0)) -and
                (-not ($value -is [System.Collections.IDictionary] -and $value.Count -eq 0))) {
                $result[$key] = $value
            }
        }
        return $result
    }
    elseif ($InputObject -is [array]) {
        $result = @($InputObject | ForEach-Object { Remove-EmptyValues $_ } | Where-Object { 
            $null -ne $_ -and $_ -ne '' -and
            (-not ($_ -is [array] -and $_.Count -eq 0)) -and
            (-not ($_ -is [System.Collections.IDictionary] -and $_.Count -eq 0))
        })
        return $result
    }
    else {
        return $InputObject
    }
}

function Sort-Properties {
    param([hashtable]$InputObject)
    
    # Define the preferred order of properties
    $propertyOrder = @(
        'displayName',
        'state',
        'createdDateTime',
        'modifiedDateTime',
        'id'
    )
    
    $orderedData = [ordered]@{}
    
    # First add the properties in our preferred order
    foreach ($prop in $propertyOrder) {
        if ($InputObject.ContainsKey($prop)) {
            $orderedData[$prop] = $InputObject[$prop]
        }
    }
    
    # Then add all remaining properties
    foreach ($key in $InputObject.Keys) {
        if (-not $propertyOrder.Contains($key)) {
            $orderedData[$key] = $InputObject[$key]
        }
    }
    
    return $orderedData
}

Get-ChildItem -Path $completePath -Filter "*.yaml" | ForEach-Object {
    try {
        # Read and parse YAML
        $yamlContent = Get-Content $_.FullName -Raw
        $data = ConvertFrom-Yaml $yamlContent
        
        # Clean the data
        $cleanedData = Remove-EmptyValues $data
        
        # Sort properties in desired order
        $orderedData = Sort-Properties $cleanedData
        
        # Convert back to YAML and save
        $cleanedYaml = $orderedData | ConvertTo-Yaml
        $outputPath = Join-Path $cleanPath $_.Name
        $cleanedYaml | Out-File $outputPath -Encoding UTF8
        
        Write-Host "Cleaned $($_.Name)"
    }
    catch {
        Write-Error "Error processing $($_.Name): $_"
    }
}
