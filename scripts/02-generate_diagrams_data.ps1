# Create directories if they don't exist
$basePath = Split-Path -Path $PSScriptRoot -Parent
$originalPath = Join-Path $basePath "policies/data"
$diagramsPath = Join-Path $basePath "diagrams/data"
New-Item -ItemType Directory -Force -Path $diagramsPath

# At the start of the script
$script:functionCalls = @{}

function Get-SafeId {
    param($text)
    # $script:functionCalls[$MyInvocation.MyCommand.Name]++
    return ($text -replace '[^a-zA-Z0-9]', '_')
}

function Get-FriendlyName {
    param(
        $item,
        [string]$prefix = ""
    )
    # $script:functionCalls[$MyInvocation.MyCommand.Name]++
    if ($item.displayName) {
        $name = $item.displayName
        if ($item.memberCount) {
            $name += "<br/>Members: $($item.memberCount)"
        }
        return $name
    }
    return "$prefix$($item.id)"
}

function Get-RolesText {
    param(
        $roles,
        [string]$type = "Roles"
    )
    # $script:functionCalls[$MyInvocation.MyCommand.Name]++
    if (-not $roles -or -not $roles.PSObject.Properties) { return "" }
    
    $roleNames = @()
    foreach ($role in $roles.PSObject.Properties) {
        if ($role.Value.displayName) {
            $roleNames += $role.Value.displayName
        }
    }
    
    if ($roleNames.Count -eq 0) { return "" }
    return ($type + ":<br/>• " + ($roleNames -join "<br/>• "))
}

function Get-UsersText {
    param($users, $type)
    # $script:functionCalls[$MyInvocation.MyCommand.Name]++
    if (-not $users -or -not $users.PSObject.Properties) { return "" }
    
    $names = @()
    foreach ($user in $users.PSObject.Properties) {
        if ($user.Value.displayName) {
            $names += $user.Value.displayName
        }
    }
    
    if ($names.Count -eq 0) { return "" }
    return "$type Users:<br/>• " + ($names -join "<br/>• ")
}

function Get-GroupsText {
    param($groups, $type)
    # $script:functionCalls[$MyInvocation.MyCommand.Name]++
    if (-not $groups -or -not $groups.PSObject.Properties) { return "" }
    
    $names = @()
    foreach ($group in $groups.PSObject.Properties) {
        if ($group.Value.displayName) {
            $names += "$($group.Value.displayName) (Members: $($group.Value.memberCount))"
        }
    }
    
    if ($names.Count -eq 0) { return "" }
    return "$type Groups:<br/>• " + ($names -join "<br/>• ")
}

function Get-ApplicationsText {
    param($apps, $type)
    # $script:functionCalls[$MyInvocation.MyCommand.Name]++
    if (-not $apps -or -not $apps.PSObject.Properties) { return "" }
    
    $names = @()
    foreach ($app in $apps.PSObject.Properties) {
        if ($app.Value.displayName) {
            $names += $app.Value.displayName
        }
    }
    
    if ($names.Count -eq 0) { return "" }
    return "$type Applications:<br/>• " + ($names -join "<br/>• ")
}

# Updated function to create a single combined roles node
function Get-RolesNodes {
    param(
        $roles,
        [string]$type
    )
    # $script:functionCalls[$MyInvocation.MyCommand.Name]++
    if (-not $roles -or -not $roles.PSObject.Properties) { return @() }
    
    $roleNames = @()
    foreach ($role in $roles.PSObject.Properties) {
        if ($role.Value.displayName) {
            $roleNames += $role.Value.displayName
        }
    }
    
    if ($roleNames.Count -eq 0) { return @() }
    
    $lines = @()
    $roleText = "$type Roles:<br/>• " + ($roleNames -join "<br/>• ")
    $lines += "    users --> roles_$($type.ToLower())[""$roleText""]"
    return $lines
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
    
    # Applications section
    if ($policy.conditions.applications) {
        $lines += "    conditions --> applications"
        if ($policy.conditions.applications.includeApplications -eq "All") {
            $lines += "    applications --> all[""All Applications""]"
        } else {
            $includeAppsText = Get-ApplicationsText -apps $policy.conditions.applications.includeApplications -type "Include"
            $excludeAppsText = Get-ApplicationsText -apps $policy.conditions.applications.excludeApplications -type "Exclude"
            
            if ($includeAppsText) { $lines += "    applications --> apps_include[""$includeAppsText""]" }
            if ($excludeAppsText) { $lines += "    applications --> apps_exclude[""$excludeAppsText""]" }
        }
    }
    
    # Users section
    if ($policy.conditions.users) {
        $lines += "    conditions --> users"
        
        # Handle All Users case
        if ($policy.conditions.users.includeUsers -eq "All") {
            $lines += "    users --> all_users[""All Users""]"
        } else {
            # Include/Exclude Users as combined nodes
            $includeUsersText = Get-UsersText -users $policy.conditions.users.includeUsers -type "Include"
            $excludeUsersText = Get-UsersText -users $policy.conditions.users.excludeUsers -type "Exclude"
            
            if ($includeUsersText) { $lines += "    users --> users_include[""$includeUsersText""]" }
            if ($excludeUsersText) { $lines += "    users --> users_exclude[""$excludeUsersText""]" }
        }

        # Groups as combined nodes
        $includeGroupsText = Get-GroupsText -groups $policy.conditions.users.includeGroups -type "Include"
        $excludeGroupsText = Get-GroupsText -groups $policy.conditions.users.excludeGroups -type "Exclude"
        
        if ($includeGroupsText) { $lines += "    users --> groups_include[""$includeGroupsText""]" }
        if ($excludeGroupsText) { $lines += "    users --> groups_exclude[""$excludeGroupsText""]" }

        # Roles with individual nodes
        if ($policy.conditions.users.includeRoles.PSObject.Properties) {
            $lines += Get-RolesNodes -roles $policy.conditions.users.includeRoles -type "Include"
        }
        if ($policy.conditions.users.excludeRoles.PSObject.Properties) {
            $lines += Get-RolesNodes -roles $policy.conditions.users.excludeRoles -type "Exclude"
        }
    }

    # Client App Types
    if ($policy.conditions.clientAppTypes) {
        $lines += "    conditions --> clientAppTypes"
        foreach ($appType in $policy.conditions.clientAppTypes) {
            $lines += "    clientAppTypes --> $($appType -replace '\W', '_')[""$appType""]"
        }
    }

    # Add after the clientAppTypes section and before the grantControls section

    # Platforms
    if ($policy.conditions.platforms) {
        $lines += "    conditions --> platforms"
        if ($policy.conditions.platforms.includePlatforms) {
            $includePlatforms = $policy.conditions.platforms.includePlatforms -join "<br/>• "
            $lines += "    platforms --> include_platforms[""Include Platforms:<br/>• $includePlatforms""]"
        }
        if ($policy.conditions.platforms.excludePlatforms) {
            $excludePlatforms = $policy.conditions.platforms.excludePlatforms -join "<br/>• "
            $lines += "    platforms --> exclude_platforms[""Exclude Platforms:<br/>• $excludePlatforms""]"
        }
    }

    # Locations
    if ($policy.conditions.locations) {
        $lines += "    conditions --> locations"
        if ($policy.conditions.locations.includeLocations) {
            $includeLocations = $policy.conditions.locations.includeLocations -join "<br/>• "
            $lines += "    locations --> include_locations[""Include Locations:<br/>• $includeLocations""]"
        }
        if ($policy.conditions.locations.excludeLocations) {
            $excludeLocations = $policy.conditions.locations.excludeLocations -join "<br/>• "
            $lines += "    locations --> exclude_locations[""Exclude Locations:<br/>• $excludeLocations""]"
        }
    }

    # Risk Levels
    if ($policy.conditions.signInRiskLevels) {
        $signInRisks = $policy.conditions.signInRiskLevels -join "<br/>• "
        $lines += "    conditions --> signInRisk[""Sign-in Risk Levels:<br/>• $signInRisks""]"
    }

    if ($policy.conditions.userRiskLevels) {
        $userRisks = $policy.conditions.userRiskLevels -join "<br/>• "
        $lines += "    conditions --> userRisk[""User Risk Levels:<br/>• $userRisks""]"
    }

    if ($policy.conditions.servicePrincipalRiskLevels) {
        $spRisks = $policy.conditions.servicePrincipalRiskLevels -join "<br/>• "
        $lines += "    conditions --> spRisk[""Service Principal Risk Levels:<br/>• $spRisks""]"
    }

    if ($policy.conditions.insiderRiskLevels) {
        $insiderRisks = $policy.conditions.insiderRiskLevels -join "<br/>• "
        $lines += "    conditions --> insiderRisk[""Insider Risk Levels:<br/>• $insiderRisks""]"
    }

    # Device Platforms
    if ($policy.conditions.devices) {
        $lines += "    conditions --> devices"
        if ($policy.conditions.devices.deviceFilter) {
            # Escape internal quotes by using single quotes or escaped double quotes
            $rule = $policy.conditions.devices.deviceFilter.rule.Replace('"', '\\"')
            $lines += "    devices --> deviceFilter[""Device Filter: $($policy.conditions.devices.deviceFilter.mode)<br/>Rule: $rule""]"
        }
    }

    # Authentication Flows
    if ($policy.conditions.authenticationFlows) {
        $lines += "    conditions --> authFlows[""Authentication Flows""]"
        if ($policy.conditions.authenticationFlows.includeAuthenticationFlows) {
            $flows = $policy.conditions.authenticationFlows.includeAuthenticationFlows -join "<br/>• "
            $lines += "    authFlows --> includeFlows[""Include Flows:<br/>• $flows""]"
        }
    }

    # Client Applications
    if ($policy.conditions.clientApplications) {
        $lines += "    conditions --> clientApps[""Client Applications""]"
        if ($policy.conditions.clientApplications.includeServicePrincipals) {
            $services = $policy.conditions.clientApplications.includeServicePrincipals -join "<br/>• "
            $lines += "    clientApps --> includeServices[""Include Service Principals:<br/>• $services""]"
        }
        if ($policy.conditions.clientApplications.excludeServicePrincipals) {
            $services = $policy.conditions.clientApplications.excludeServicePrincipals -join "<br/>• "
            $lines += "    clientApps --> excludeServices[""Exclude Service Principals:<br/>• $services""]"
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

# Used for debug purposes - requires uncommenting the functionCalls code above
# At the end of the script
# Write-Host "Function usage stats:"
# $script:functionCalls.GetEnumerator() | ForEach-Object {
#     Write-Host "$($_.Key): $($_.Value) calls"
# }
