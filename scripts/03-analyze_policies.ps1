# Create analysis directory if it doesn't exist
$basePath = Split-Path -Path $PSScriptRoot -Parent
$analysisPath = Join-Path $basePath "analysis"
$dataPath = Join-Path $basePath "policies/data"

New-Item -ItemType Directory -Force -Path $analysisPath

# Function to classify policy pattern
function Get-PolicyPattern {
    param($policy)
    
    $pattern = @{
        apps = "Specific Apps"
        platform = "Specific Platforms"
        controls = @()
        clientTypes = "Specific Clients"
    }

    # Determine app scope
    if ($policy.conditions.applications.includeApplications -eq "All") {
        $pattern.apps = "All Apps"
    }

    # Determine platform scope
    if (!$policy.conditions.platforms -or $policy.conditions.platforms.includePlatforms -eq "All") {
        $pattern.platform = "All Platforms"
    }

    # Determine client types
    if ($policy.conditions.clientAppTypes -contains "all") {
        $pattern.clientTypes = "All Clients"
    }

    # Determine controls
    if ($policy.grantControls.builtInControls -contains "mfa") {
        $pattern.controls += "MFA"
    }
    if ($policy.sessionControls.applicationEnforcedRestrictions.isEnabled) {
        $pattern.controls += "App Restrictions"
    }
    if ($pattern.controls.Count -eq 0) {
        $pattern.controls += "No Controls"
    }

    return $pattern
}

# Function to analyze security gaps
function Get-SecurityAnalysis {
    param($policy)
    
    $issues = @()

    # Check for broad exclusions
    if ($policy.conditions.users.excludeUsers -and $policy.conditions.users.excludeUsers.Count -gt 3) {
        $issues += "Has broad user exclusions (${$policy.conditions.users.excludeUsers.Count} users)"
    }

    # Check for test policies
    if ($policy.displayName -match "TEST|DEV") {
        $issues += "Test/Development policy"
    }

    # Check weak controls
    if (!$policy.grantControls -and !$policy.sessionControls) {
        $issues += "No security controls defined"
    }

    # Check state
    if ($policy.state -eq "enabledForReportingButNotEnforced") {
        $issues += "Policy in report-only mode"
    }

    return $issues
}

# Add new function to get emoji indicators
function Get-StateEmoji {
    param($state)
    switch ($state) {
        "enabled" { "✅" }
        "enabledForReportingButNotEnforced" { "🔄" }
        "disabled" { "❌" }
        default { "❓" }
    }
}

# Update the Get-UserScopeEmoji function for more accurate counting and guest icon
function Get-UserScopeEmoji {
    param($policy)
    
    $parts = @()
    
    # Handle Users
    $includeUsers = if ($policy.conditions.users.includeUsers -contains "All") { 
        "All"
    } else {
        $count = if ($policy.conditions.users.includeUsers) {
            @($policy.conditions.users.includeUsers | Where-Object { $_ -ne "All" }).Count
        } else { 0 }
        $count.ToString()
    }
    $excludeUsers = if ($policy.conditions.users.excludeUsers) {
        @($policy.conditions.users.excludeUsers.PSObject.Properties).Count
    } else { 0 }
    if ($includeUsers -ne "0" -or $excludeUsers -gt 0) {
        $parts += "👤 ($includeUsers, $excludeUsers)"
    }
    
    # Handle Groups
    $includeGroups = if ($policy.conditions.users.includeGroups) {
        @($policy.conditions.users.includeGroups.PSObject.Properties).Count
    } else { 0 }
    $excludeGroups = if ($policy.conditions.users.excludeGroups) {
        @($policy.conditions.users.excludeGroups.PSObject.Properties).Count
    } else { 0 }
    if ($includeGroups -gt 0 -or $excludeGroups -gt 0) {
        $parts += "👥 ($includeGroups, $excludeGroups)"
    }
    
    # Handle Roles
    $includeRoles = if ($policy.conditions.users.includeRoles) {
        @($policy.conditions.users.includeRoles.PSObject.Properties).Count
    } else { 0 }
    $excludeRoles = if ($policy.conditions.users.excludeRoles) {
        @($policy.conditions.users.excludeRoles.PSObject.Properties).Count
    } else { 0 }
    if ($includeRoles -gt 0 -or $excludeRoles -gt 0) {
        $parts += "🎯 ($includeRoles, $excludeRoles)"
    }

    # Handle Guests/External Users
    if ($null -ne $policy.conditions.users.includeGuestsOrExternalUsers -or 
        $null -ne $policy.conditions.users.excludeGuestsOrExternalUsers) {
        $includeGuests = if ($policy.conditions.users.includeGuestsOrExternalUsers) { "1" } else { "0" }
        $excludeGuests = if ($policy.conditions.users.excludeGuestsOrExternalUsers) { "1" } else { "0" }
        $parts += "🥷 ($includeGuests, $excludeGuests)"
    }
    
    if ($parts.Count -eq 0) {
        return "👤 (0, 0)"
    }
    
    return ($parts -join ", ")
}

# Modify Get-AppScopeEmoji for clearer summaries
function Get-AppScopeEmoji {
    param($policy)
    
    # Handle User Actions separately (keep existing format)
    if ($policy.conditions.applications.includeUserActions.Count -gt 0) {
        $action = switch ($policy.conditions.applications.includeUserActions[0]) {
            "urn:user:registerdevice" { "Register Device" }
            "urn:user:registersecurityinfo" { "Register Security Info" }
            default { $_ }
        }
        return "📱 User Action: $action"
    }

    # Get counts and names for included apps
    $includeApps = if ($policy.conditions.applications.includeApplications -is [Array]) {
        @($policy.conditions.applications.includeApplications)
    } else {
        @($policy.conditions.applications.includeApplications.PSObject.Properties)
    }

    # Get counts and names for excluded apps - fix counting logic
    $excludeApps = if ($policy.conditions.applications.excludeApplications) {
        if ($policy.conditions.applications.excludeApplications -is [Array]) {
            @($policy.conditions.applications.excludeApplications)
        } else {
            @($policy.conditions.applications.excludeApplications.PSObject.Properties)
        }
    } else {
        @()
    }
    
    # Format the include/exclude display
    if ($includeApps -contains "All") {
        if ($excludeApps.Count -eq 1) {
            $excludeName = if ($excludeApps[0].Value.displayName) {
                $excludeApps[0].Value.displayName
            } else {
                $excludeApps[0]
            }
            return "🌐 (All, $excludeName)"
        }
        return "🌐 (All, $($excludeApps.Count))"
    }
    
    # Handle object-style includeApplications
    if ($includeApps.Count -eq 1) {
        if ($includeApps[0].Value.displayName) {
            return "🌐 ($($includeApps[0].Value.displayName), $($excludeApps.Count))"
        }
        elseif ($includeApps[0] -and $includeApps[0] -ne "All") {
            return "🌐 ($($includeApps[0]), $($excludeApps.Count))"
        }
    }
    
    return "🌐 ($($includeApps.Count), $($excludeApps.Count))"
}

function Get-ControlsEmoji {
    param($policy)
    $controls = @()
    
    # Handle grant controls
    if ($policy.grantControls.builtInControls) {
        if ($policy.grantControls.builtInControls -contains "mfa") {
            $controls += "🔐 MFA"
        }
        if ($policy.grantControls.builtInControls -contains "compliantDevice") {
            $controls += "📱 Compliant"
        }
        if ($policy.grantControls.builtInControls -contains "domainJoinedDevice") {
            $controls += "💻 Domain Joined"
        }
    }

    # Handle session controls
    if ($policy.sessionControls.applicationEnforcedRestrictions.isEnabled) {
        $controls += "🔒 App Enforced"
    }
    if ($policy.sessionControls.cloudAppSecurity.isEnabled) {
        $controls += "✨ MCAS"
    }
    if ($policy.sessionControls.persistentBrowser.isEnabled) {
        $controls += "🌐 No Persist"
    }
    if ($policy.sessionControls.signInFrequency.isEnabled) {
        $freq = "$($policy.sessionControls.signInFrequency.value) $($policy.sessionControls.signInFrequency.frequencyInterval)"
        $controls += "⏱️ Sign-in: $freq"
    }

    if ($controls.Count -eq 0) {
        $controls += "⚪ None"
    }

    # Add operator if multiple grant controls
    if ($policy.grantControls.builtInControls -and 
        $policy.grantControls.builtInControls.Count -gt 1) {
        $controls += "($($policy.grantControls.operator))"
    }

    return ($controls -join ", ")
}

function Get-KeyConditions {
    param($policy)
    $conditions = @()
    if ($policy.conditions.locations) {
        $conditions += "🏢 Location Based"
    }
    if ($policy.conditions.platforms -or $policy.conditions.devices.deviceFilter) {
        $conditions += "💻 Platform/Device Requirements"
    }
    # Add Client App Types condition
    if ($policy.conditions.clientAppTypes -and 
        $policy.conditions.clientAppTypes -notcontains "all") {
        $conditions += "📱 Client Apps: $($policy.conditions.clientAppTypes -join ', ')"
    }
    if ($conditions.Count -eq 0) {
        return "None"
    }
    return ($conditions -join ", ")
}

# Update Get-TemporalAnalysis to remove state transitions
function Get-TemporalAnalysis {
    param($policies)
    
    $temporal = @{
        NewPolicies = @()
        RecentChanges = @()
    }
    
    # Get the last 30 days threshold
    $thirtyDaysAgo = (Get-Date).AddDays(-30)
    
    # Analyze each policy's temporal aspects
    foreach ($policy in $policies) {
        # Safely parse dates with error handling
        $created = $null
        $modified = $null
        
        if (![string]::IsNullOrEmpty($policy.createdDateTime)) {
            try {
                $created = [DateTime]::Parse($policy.createdDateTime)
            } catch {
                Write-Warning "Could not parse creation date for policy: $($policy.displayName)"
                continue
            }
        } else {
            Write-Warning "No creation date found for policy: $($policy.displayName)"
            continue
        }

        if (![string]::IsNullOrEmpty($policy.modifiedDateTime)) {
            try {
                $modified = [DateTime]::Parse($policy.modifiedDateTime)
            } catch {
                # If modified date is invalid, use created date
                $modified = $created
                Write-Warning "Using creation date as modification date for policy: $($policy.displayName)"
            }
        } else {
            # If no modified date exists, use created date
            $modified = $created
        }
        
        # Track new policies
        if ($created -gt $thirtyDaysAgo) {
            $temporal.NewPolicies += @{
                Policy = $policy.displayName
                Created = $created
                DaysOld = [Math]::Floor((New-TimeSpan -Start $created -End (Get-Date)).TotalDays)
            }
        }
        
        # Track recent modifications
        if ($modified -gt $thirtyDaysAgo -and $modified -ne $created) {
            $temporal.RecentChanges += @{
                Policy = $policy.displayName
                Modified = $modified
                DaysSinceChange = [Math]::Floor((New-TimeSpan -Start $modified -End (Get-Date)).TotalDays)
            }
        }
    }
    
    return $temporal
}

# Create analysis directory if it doesn't exist
$analysisPath = Join-Path $basePath "analysis/markdown"
New-Item -ItemType Directory -Force -Path $analysisPath

# Load all policies
$policies = try {
    Get-ChildItem -Path $dataPath -Filter "*.json" -ErrorAction Stop | 
    ForEach-Object { 
        try {
            $content = Get-Content $_.FullName -Raw
            $policy = $content | ConvertFrom-Json
            if (!$policy.conditions -or !$policy.displayName) {
                Write-Warning "Invalid policy format in file: $($_.Name)"
                return
            }
            $policy
        }
        catch {
            Write-Warning "Failed to parse policy file: $($_.Name)"
            Write-Warning $_.Exception.Message
            return
        }
    }
}
catch {
    Write-Error "Failed to read policy files: $_"
    exit 1
}

# Fix initialization structure
$analysis = @{
    patterns = @{}
    stats = @{
        totalPolicies = $policies.Count
        byState = @{}
        byControl = @{}
    }
}

# Modify analysis section to remove securityIssues reference
foreach ($policy in $policies) {
    # Get pattern
    $pattern = Get-PolicyPattern -policy $policy
    $patternKey = "$($pattern.apps) - $($pattern.controls -join '+') - $($pattern.platform) - $($pattern.clientTypes)"
    
    if (!$analysis.patterns[$patternKey]) {
        $analysis.patterns[$patternKey] = @()
    }
    $analysis.patterns[$patternKey] += $policy.displayName

    # Update stats
    $analysis.stats.byState[$policy.state]++
    foreach ($control in $pattern.controls) {
        $analysis.stats.byControl[$control]++
    }
}

# Generate JSON report
$analysis | ConvertTo-Json -Depth 10 | 
    Out-File (Join-Path $analysisPath "analysis_report.json")

# Update Get-FormattedTableRow to include markdown link
function Get-FormattedTableRow {
    param($policy)
    $state = Get-StateEmoji -state $policy.state
    $users = Get-UserScopeEmoji -policy $policy
    $apps = Get-AppScopeEmoji -policy $policy
    $controls = Get-ControlsEmoji -policy $policy
    $conditions = Get-KeyConditions -policy $policy
    
    # Create link to policy section using policy name as anchor
    $policyLink = $policy.displayName -replace '[^a-zA-Z0-9\s-]', '' -replace '\s+', '-'
    "| [$($policy.displayName)](#$($policyLink.ToLower())) | $state | $users | $apps | $controls | $conditions |"
}

# Add function to get non-empty conditions
function Get-NonEmptyConditions {
    param($policy)
    
    $conditions = @{}

    # User Configuration
    $userConfig = @{}
    if ($policy.conditions.users.includeUsers) {
        $userConfig['Include Users'] = $policy.conditions.users.includeUsers -contains "All" ? 
            "All Users" : (Get-CleanValue $policy.conditions.users.includeUsers "users")
    }
    if ($policy.conditions.users.excludeUsers.PSObject.Properties.Count -gt 0) {
        $userConfig['Exclude Users'] = Get-CleanValue $policy.conditions.users.excludeUsers "users"
    }
    if ($policy.conditions.users.includeRoles.PSObject.Properties.Count -gt 0) {
        $userConfig['Include Roles'] = Get-CleanValue $policy.conditions.users.includeRoles "roles"
    }
    if ($policy.conditions.users.excludeRoles.PSObject.Properties.Count -gt 0) {
        $userConfig['Exclude Roles'] = Get-CleanValue $policy.conditions.users.excludeRoles "roles"
    }
    if ($userConfig.Count -gt 0) {
        $conditions['User Configuration'] = $userConfig
    }

    # Application Configuration
    $appConfig = @{}
    if ($policy.conditions.applications.includeApplications) {
        $appConfig['Include Apps'] = $policy.conditions.applications.includeApplications -contains "All" ? 
            "All Applications" : (Get-CleanValue $policy.conditions.applications.includeApplications "apps")
    }
    if ($policy.conditions.applications.excludeApplications.PSObject.Properties.Count -gt 0) {
        $appConfig['Exclude Apps'] = Get-CleanValue $policy.conditions.applications.excludeApplications "apps"
    }
    if ($policy.conditions.applications.includeUserActions) {
        $appConfig['User Actions'] = $policy.conditions.applications.includeUserActions -join ", "
    }
    if ($appConfig.Count -gt 0) {
        $conditions['Application Configuration'] = $appConfig
    }

    # Client App Types
    if ($policy.conditions.clientAppTypes) {
        $conditions['Client App Types'] = $policy.conditions.clientAppTypes
    }

    # Platform Requirements
    if ($policy.conditions.platforms) {
        $platformConfig = @{}
        if ($policy.conditions.platforms.includePlatforms) {
            $platformConfig['Include Platforms'] = $policy.conditions.platforms.includePlatforms -contains "all" ? 
                "All Platforms" : ($policy.conditions.platforms.includePlatforms | ForEach-Object { $_.ToUpper()[0] + $_.Substring(1) })
        }
        if ($policy.conditions.platforms.excludePlatforms) {
            $platformConfig['Exclude Platforms'] = $policy.conditions.platforms.excludePlatforms | ForEach-Object { $_.ToUpper()[0] + $_.Substring(1) }
        }
        if ($platformConfig.Count -gt 0) {
            $conditions['Platform Requirements'] = $platformConfig
        }
    }

    # Location Conditions
    if ($policy.conditions.locations) {
        $locationConfig = @{}
        if ($policy.conditions.locations.includeLocations) {
            $locationConfig['Include Locations'] = $policy.conditions.locations.includeLocations
        }
        if ($policy.conditions.locations.excludeLocations) {
            $locationConfig['Exclude Locations'] = $policy.conditions.locations.excludeLocations
        }
        if ($locationConfig.Count -gt 0) {
            $conditions['Location Configuration'] = $locationConfig
        }
    }

    # Access Controls
    $controls = @()
    if ($policy.grantControls.builtInControls) {
        $controls += "Grant Controls: $($policy.grantControls.builtInControls -join ', ')"
    }
    if ($policy.sessionControls.applicationEnforcedRestrictions.isEnabled) {
        $controls += "Session Controls: Application Enforced Restrictions"
    }
    if ($controls.Count -gt 0) {
        $conditions['Access Controls'] = $controls
    }

    # State
    if ($policy.state) {
        $conditions['State'] = $policy.state
    }

    return $conditions
}

# Add function for cleaning values
function Get-CleanValue {
    param(
        $value,
        [string]$type = "default"
    )
    
    if ($value -is [array]) {
        return $value.Count
    }
    
    if ($value.PSObject.Properties) {
        $count = @($value.PSObject.Properties).Count
        switch ($type) {
            "users" { return "$count users" }
            "roles" { return "$count roles" }
            "apps" { return "$count applications" }
            default { return $count }
        }
    }
    
    return $value
}

# Modify policy_analysis.md generation to include proper indentation
function Format-MarkdownSection {
    param($title, $content)
    @"

#### $title
$content
"@
}

# Modify Get-PolicyAnalysisReport to include pattern counts
function Get-PolicyAnalysisReport {
    param($policies)
    
    # Calculate pattern counts with all required fields
    $patternCounts = @{
        blockPolicies = @($policies | Where-Object { $_.grantControls.builtInControls -contains "block" }).Count
        allowPolicies = @($policies | Where-Object { $_.grantControls.builtInControls -notcontains "block" }).Count
        active = @($policies | Where-Object { $_.state -eq "enabled" }).Count
        reportOnly = @($policies | Where-Object { $_.state -eq "enabledForReportingButNotEnforced" }).Count
        disabled = @($policies | Where-Object { $_.state -eq "disabled" }).Count
        mfaPolicies = @($policies | Where-Object { $_.grantControls.builtInControls -contains "mfa" }).Count
        compliantDevice = @($policies | Where-Object { $_.grantControls.builtInControls -contains "compliantDevice" }).Count
        domainJoined = @($policies | Where-Object { $_.grantControls.builtInControls -contains "domainJoinedDevice" }).Count
        mcasControls = @($policies | Where-Object { $_.sessionControls.cloudAppSecurity.isEnabled }).Count
        deviceFilters = @($policies | Where-Object { $_.conditions.devices.deviceFilter }).Count
        allApps = @($policies | Where-Object { $_.conditions.applications.includeApplications -contains "All" }).Count
        locationBased = @($policies | Where-Object { $null -ne $_.conditions.locations }).Count
        signInFrequency = @($policies | Where-Object { $_.sessionControls.signInFrequency.isEnabled }).Count
        persistentBrowser = @($policies | Where-Object { $_.sessionControls.persistentBrowser.isEnabled }).Count
    }

    # Build sections
    $headerSection = @"
# Conditional Access Policy Analysis

## Legend
- ✅ Active Policy
- 🔄 Report-Only Policy
- ❌ Disabled Policy
- 👤 Users (included, excluded)
- 👥 Groups (included, excluded)
- 🎯 Roles (included, excluded)
- 🥷 Guests (included, excluded)
- 🌐 Applications (included, excluded)
- 📱 User Actions, Client Apps & Device Compliance
- 💻 Domain Joined Devices & Platform Requirements
- 🔐 MFA Required
- 🔒 App Enforced Restrictions
- ✨ MCAS Controls
- ⏱️ Sign-in Frequency
- ⚪ No Controls
- 🏢 Location Based

## Policy Overview
| Policy Name | State | Users | Apps | Controls | Key Conditions |
|-------------|-------|-------|------|----------|----------------|
"@

    $tableSection = ($policies | ForEach-Object { Get-FormattedTableRow -policy $_ }) -join "`n"

    $patternsSection = @"

## Policy Patterns Found

Total Policies: $($policies.Count)

Policy States:
- Active policies: $($patternCounts.active) policies
- Report-only mode: $($patternCounts.reportOnly) policies
- Disabled: $($patternCounts.disabled) policies

Access Controls:
- Allow Access: $($patternCounts.allowPolicies) policies
- Block Access: $($patternCounts.blockPolicies) policies
- MFA required: $($patternCounts.mfaPolicies) policies
- Compliant device required: $($patternCounts.compliantDevice) policies
- Domain joined device required: $($patternCounts.domainJoined) policies

Session Controls:
- MCAS monitoring: $($patternCounts.mcasControls) policies
- Sign-in frequency set: $($patternCounts.signInFrequency) policies
- Browser persistence configured: $($patternCounts.persistentBrowser) policies

Conditions:
- All applications: $($patternCounts.allApps) policies
- Location-based conditions: $($patternCounts.locationBased) policies
- Device filters: $($patternCounts.deviceFilters) policies

"@

    # Fix formatting in detailed conditions section
    $detailsSection = ($policies | ForEach-Object {
        $conditions = Get-NonEmptyConditions -policy $_
        $policyDetails = "`n### $($_.displayName)"
        foreach ($section in $conditions.Keys) {
            $content = if ($conditions[$section] -is [array]) {
                ($conditions[$section] | ForEach-Object { "- $_" }) -join "`n"
            }
            elseif ($conditions[$section] -is [hashtable]) {
                ($conditions[$section].GetEnumerator() | ForEach-Object { 
                    "- $($_.Key): $($_.Value)" 
                }) -join "`n"
            }
            else {
                "- $($conditions[$section])"
            }
            $policyDetails += (Format-MarkdownSection -title $section -content $content)
        }
        $policyDetails
    }) -join "`n"

    # Get temporal analysis
    $temporal = Get-TemporalAnalysis -policies $policies
    $temporalSection = @"

## Temporal Analysis

### Policy State Distribution
| State | Count | Percentage |
|-------|-------|------------|
| Enabled | $($patternCounts.active) | $([math]::Round($patternCounts.active/$policies.Count * 100, 1))% |
| Report-Only | $($patternCounts.reportOnly) | $([math]::Round($patternCounts.reportOnly/$policies.Count * 100, 1))% |
| Disabled | $($patternCounts.disabled) | $([math]::Round($patternCounts.disabled/$policies.Count * 100, 1))% |

### Recent Policy Changes
"@
    if ($temporal.RecentChanges) {
        $temporalSection += @"

| Policy Name | Days Since Change | Last Modified |
|-------------|------------------|---------------|
"@
        $temporal.RecentChanges | Sort-Object DaysSinceChange | ForEach-Object {
            $temporalSection += "`n| $($_.Policy) | $($_.DaysSinceChange) | $($_.Modified.ToString('yyyy-MM-dd')) |"
        }
    } else {
        $temporalSection += "`n- No recent changes detected in the last 30 days"
    }

    $temporalSection += @"

### New Policies (Last 30 Days)
"@
    if ($temporal.NewPolicies) {
        $temporalSection += @"

| Policy Name | Days Old | Created Date |
|-------------|----------|--------------|
"@
        $temporal.NewPolicies | Sort-Object DaysOld | ForEach-Object {
            $temporalSection += "`n| $($_.Policy) | $($_.DaysOld) | $($_.Created.ToString('yyyy-MM-dd')) |"
        }
    } else {
        $temporalSection += "`n- No new policies created in the last 30 days"
    }

    # Combine all sections
    $sections = @(
        $headerSection,
        $tableSection,
        $patternsSection,
        $detailsSection,
        $temporalSection
    )

    return ($sections -join "`n")
}

# Generate and save report
Get-PolicyAnalysisReport -policies $policies | 
    Out-File (Join-Path $analysisPath "policy_analysis.md")

Write-Host "Analysis complete. Check the analysis/markdown folder for the report."
