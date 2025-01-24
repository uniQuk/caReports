# Create directories if they don't exist
$basePath = Split-Path -Path $PSScriptRoot -Parent
$originalPath = Join-Path $basePath "policies/original"
$diagramsPath = Join-Path $basePath "diagrams/original"
New-Item -ItemType Directory -Force -Path $diagramsPath

function Get-SafeId {
    param($text)
    return ($text -replace '[^a-zA-Z0-9]', '_')
}

function Get-UserConditionSummary {
    param($users)
    $conditions = @()
    
    if ($users.includeUsers -contains "All") {
        $conditions += "All Users"
    }
    elseif ($users.includeUsers) {
        $conditions += "Users: $($users.includeUsers.Count)"
    }
    
    if ($users.includeGroups) {
        $conditions += "Groups: $($users.includeGroups.Count)"
    }
    
    if ($users.excludeUsers) {
        $conditions += "Excl Users: $($users.excludeUsers.Count)"
    }
    
    if ($users.excludeGroups) {
        $conditions += "Excl Groups: $($users.excludeGroups.Count)"
    }

    if ($users.excludeGuestsOrExternalUsers) {
        $conditions += "No External Users"
    }

    return ($conditions -join "<br/>") -replace '"', '\"'
}

function Get-ApplicationSummary {
    param($apps)
    if (-not $apps) { return "All Apps" }
    
    $text = if ($apps.includeApplications -contains "All") {
        "All Applications"
    }
    elseif ($apps.includeApplications) {
        "Apps: $($apps.includeApplications -join ', ')"
    }
    
    if ($apps.excludeApplications) {
        $text += "<br/>Excl: $($apps.excludeApplications -join ', ')"
    }
    
    return $text -replace '"', '\"'
}

function Get-ClientAppTypesText {
    param($clientAppTypes)
    if (-not $clientAppTypes -or $clientAppTypes -contains "all") {
        return "All Client Types"
    }
    return "Apps: $($clientAppTypes -join ', ')"
}

# Process each policy file
Get-ChildItem -Path $originalPath -Filter "*.json" | ForEach-Object {
    $policy = Get-Content $_.FullName | ConvertFrom-Json
    $safeFileName = Get-SafeId -text $policy.displayName
    
    # Build the diagram content
    $lines = @()
    $lines += "#### Conditional Access Policy: $($policy.displayName)"
    $lines += ""
    $lines += '```mermaid'
    $lines += "graph LR"
    $lines += "    id[""$($policy.displayName)""] --> state[""state: $($policy.state)""]"
    $lines += "    id --> conditions"
    
    # Applications
    if ($policy.conditions.applications) {
        $lines += "    conditions --> applications"
        if ($policy.conditions.applications.includeApplications) {
            $lines += "    applications --> includeApplications"
            foreach ($app in $policy.conditions.applications.includeApplications) {
                $safeAppId = $app -replace '\W', '_'
                $lines += "    includeApplications --> app_$($safeAppId)[""$app""]"
            }
        }
    }
    
    # Users
    if ($policy.conditions.users) {
        $lines += "    conditions --> users"
        $userTypes = @('includeUsers', 'excludeUsers', 'includeGroups', 'excludeGroups', 'includeRoles', 'excludeRoles')
        foreach ($type in $userTypes) {
            if ($policy.conditions.users.$type) {
                $lines += "    users --> $type"
                foreach ($item in $policy.conditions.users.$type) {
                    $safeId = $item -replace '\W', '_'
                    $prefix = $type[0]
                    $lines += "    $type --> ${prefix}_${safeId}[""$item""]"
                }
            }
        }
    }

    # Client App Types
    if ($policy.conditions.clientAppTypes) {
        $lines += "    conditions --> clientAppTypes"
        foreach ($appType in $policy.conditions.clientAppTypes) {
            $lines += "    clientAppTypes --> $($appType -replace '\W', '_')[""$appType""]"
        }
    }

    # Grant Controls
    if ($policy.grantControls) {
        $lines += "    id --> grantControls"
        $lines += "    grantControls --> grantControlsOperator[""operator: $($policy.grantControls.operator)""]"
        if ($policy.grantControls.builtInControls) {
            $lines += "    grantControls --> builtInControls"
            foreach ($control in $policy.grantControls.builtInControls) {
                $lines += "    builtInControls --> bic_$($control -replace '\W', '_')[""$control""]"
            }
        }
    }
    
    $lines += '```'
    
    # Save diagram
    $outputPath = Join-Path -Path $diagramsPath -ChildPath "$safeFileName.md"
    $lines | Out-File -FilePath $outputPath -Encoding utf8
}

Write-Host "Diagrams generated in $diagramsPath"
