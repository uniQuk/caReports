# Load configuration
$basePath = Split-Path -Path $PSScriptRoot -Parent
$configPath = Join-Path $basePath "config/naming-rules.json"
$config = Get-Content $configPath | ConvertFrom-Json

# Read all JSON policy files
$policiesPath = Join-Path $basePath "policies/data"
$policies = Get-ChildItem -Path $policiesPath -Filter "*.json" | ForEach-Object {
    $content = Get-Content $_.FullName | ConvertFrom-Json
    @{
        FilePath = $_.FullName
        OriginalName = $content.displayName
        Policy = $content
    }
}

# Add sequence tracking hashtables
$script:sequenceCounters = @{
    Simple = @{
        admin = 10
        device = 20
        default = 1
        emergency = 1
    }
    MS = @{
        Global = 1
        Admins = 100
        Internals = 200
        GuestUsers = 400
    }
}

function Get-NextNumber($category, $type) {
    $currentNumber = $script:sequenceCounters[$category][$type]
    $script:sequenceCounters[$category][$type] = $currentNumber + 1
    return $currentNumber
}

function Get-PolicyPersona($policy) {
    if ($policy.conditions.users.includeRoles.PSObject.Properties.Count -gt 0) {
        return "Admins"
    }
    if ($policy.conditions.users.includeUsers -contains "All") {
        return "Global"
    }
    return "Internals"
}

function Get-PolicyControls($policy) {
    $controls = @()
    if ($policy.grantControls.builtInControls) {
        $controls += $policy.grantControls.builtInControls
    }
    return ($controls -join "+")
}

function Get-AppDisplayName($appId) {
    if ([string]::IsNullOrEmpty($appId)) {
        return "Selected"
    }

    $appId = $appId.ToString()
    if ($config.appMappings.PSObject.Properties[$appId]) {
        return $config.appMappings.PSObject.Properties[$appId].Value
    }

    return "Selected"
}

function Get-PolicyTarget($policy) {
    if (!$policy.conditions -or !$policy.conditions.applications) {
        return "Selected"
    }

    $apps = $policy.conditions.applications.includeApplications
    
    if (!$apps -or $apps.Count -eq 0) {
        return "Selected"
    }
    
    if ($apps -contains "All") { 
        return "AllApps" 
    }
    
    if ($apps.Count -gt 1) {
        return "Selected"
    }
    
    $appId = $apps[0]
    if ([string]::IsNullOrEmpty($appId)) {
        return "Selected"
    }
    
    return Get-AppDisplayName $appId
}

function Get-PolicyPlatforms($policy) {
    if (!$policy.conditions.platforms) { return "AnyPlatform" }
    $platforms = $policy.conditions.platforms.includePlatforms
    if ($platforms -contains "all") { return "AnyPlatform" }
    return ($platforms -join "+")
}

function Get-ASDType($policy) {
    if ($policy.conditions.users.includeRoles.PSObject.Properties.Count -gt 0) {
        return $config.asdTypes.admin
    }
    if ($policy.conditions.platforms) {
        return $config.asdTypes.device
    }
    if ($policy.conditions.users.includeGuestsOrExternalUsers) {
        return $config.asdTypes.guest
    }
    if ($policy.conditions.locations) {
        return $config.asdTypes.location
    }
    return $config.asdTypes.default
}

function Get-ASDAction($policy) {
    if ($policy.grantControls.builtInControls -contains "block") {
        return "B"
    }
    if ($policy.sessionControls) {
        return "S"
    }
    return "G"
}

function Get-ASDPurpose($policy) {
    # Get base type and action
    $type = Get-ASDType $policy
    $action = Get-ASDAction $policy
    
    # Get specific controls and conditions
    $hasLegacyAuth = $policy.conditions.clientAppTypes -contains "other"
    $hasRiskLevels = $policy.conditions.userRiskLevels.Count -gt 0 -or $policy.conditions.signInRiskLevels.Count -gt 0
    $hasMFA = $policy.grantControls.builtInControls -contains "mfa"
    $hasCompliantDevice = $policy.grantControls.builtInControls -contains "compliantDevice"
    $hasSession = $null -ne $policy.sessionControls
    
    # Handle app targeting
    $target = Get-PolicyTarget $policy
    $appPart = if ($target -ne "AllApps") { "$target-" } else { "" }
    
    # Get purpose based on type and conditions
    $purpose = switch ($type) {
        "ADM" {
            if ($hasSession) { $config.asdPurposes.admin.session }
            elseif ($hasCompliantDevice) { $config.asdPurposes.admin.compliantDevice }
            elseif ($hasMFA) { $config.asdPurposes.admin.mfa }
            else { $config.asdPurposes.admin.block }
        }
        "DEV" {
            if ($hasCompliantDevice) { $config.asdPurposes.device.compliantDevice }
            elseif ($hasMFA) { $config.asdPurposes.device.mfa }
            else { $config.asdPurposes.device.block }
        }
        "USR" {
            if ($action -eq "B") {
                if ($hasLegacyAuth) { $config.asdPurposes.user.block.legacy }
                elseif ($hasRiskLevels) { $config.asdPurposes.user.block.risk }
                else { $config.asdPurposes.user.block.default }
            }
            elseif ($hasSession) { $config.asdPurposes.user.session }
            elseif ($hasMFA) { $config.asdPurposes.user.mfa }
            else { $config.asdPurposes.user.compliantDevice }
        }
        default { "AccessControl" }
    }
    
    return "$appPart$purpose"
}

function Get-PolicyNumber($persona) {
    $number = Get-NextNumber "MS" $persona
    return "CA$($number.ToString('000'))"
}

function Get-SimpleSequenceNumber($policy) {
    if ($policy.displayName -match "EMERGENCY|EM\d+") {
        $number = Get-NextNumber "Simple" "emergency"
        return "EM$($number.ToString('00'))"
    }
    
    if ($policy.conditions.users.includeRoles.Count -gt 0) {
        $number = Get-NextNumber "Simple" "admin"
        return "CA$($number.ToString('00'))"
    }
    if ($policy.conditions.platforms) {
        $number = Get-NextNumber "Simple" "device"
        return "CA$($number.ToString('00'))"
    }
    
    $number = Get-NextNumber "Simple" "default"
    return "CA$($number.ToString('00'))"
}

function Get-SimpleResponse($policy) {
    if ($policy.grantControls.builtInControls -contains "block") {
        return "Block"
    }
    if ($policy.grantControls.builtInControls -contains "mfa") {
        return "RequireMFA"
    }
    if ($policy.grantControls.builtInControls -contains "compliantDevice") {
        return "RequireCompliant"
    }
    if ($policy.sessionControls) {
        return "AllowSession"
    }
    return "Grant"
}

function Get-SimpleUsers($policy) {
    if ($policy.conditions.users.includeRoles.Count -gt 0) {
        return "Admins"
    }
    if ($policy.conditions.users.includeUsers -contains "All") {
        return "AllUsers"
    }
    return "SelectedUsers"
}

function Get-SimpleConditions($policy) {
    $conditions = @()
    
    if ($policy.conditions.locations) {
        $conditions += "ExternalAccess"
    }
    if ($policy.conditions.platforms) {
        if ($policy.conditions.platforms.includePlatforms -contains "all") {
            $conditions += "AllPlatforms"
        } else {
            $conditions += ($policy.conditions.platforms.includePlatforms -join "And")
        }
    }
    
    return ($conditions -join "-") -replace "^$", "NoConditions"
}

# Reset sequence counters before processing
$script:sequenceCounters.Simple.admin = 10
$script:sequenceCounters.Simple.device = 20
$script:sequenceCounters.Simple.default = 1
$script:sequenceCounters.Simple.emergency = 1
$script:sequenceCounters.MS.Global = 1
$script:sequenceCounters.MS.Admins = 100
$script:sequenceCounters.MS.Internals = 200
$script:sequenceCounters.MS.GuestUsers = 400

# Generate different naming conventions
$namedPolicies = $policies | ForEach-Object {
    $policy = $_.Policy
    
    # Simple MS Format
    $seqNum = Get-SimpleSequenceNumber $policy
    $apps = Get-PolicyTarget $policy
    $response = Get-SimpleResponse $policy
    $users = Get-SimpleUsers $policy
    $conditions = Get-SimpleConditions $policy
    $simpleFormat = "$seqNum-$apps-$response-$users-$conditions"
    
    # MS Format
    $persona = Get-PolicyPersona $policy
    $policyNumber = Get-PolicyNumber $persona  # Store policy number first
    $policyType = "BaseProtection"  # Could be enhanced based on policy analysis
    $target = Get-PolicyTarget $policy
    $platforms = Get-PolicyPlatforms $policy
    $controls = Get-PolicyControls $policy
    $msFormat = "$policyNumber-$persona-$policyType-$target-$platforms-$controls"
    
    # ASD Format with cleaner purpose
    $asdType = Get-ASDType $policy
    $asdAction = Get-ASDAction $policy
    $asdPurpose = Get-ASDPurpose $policy
    $asdFormat = "$asdType-$asdAction-$asdPurpose"
    
    @{
        OriginalName = $_.OriginalName
        SimpleFormat = $simpleFormat
        MSFormat = $msFormat
        ASDFormat = $asdFormat
    }
}

# Create markdown report
$report = @"
# Conditional Access Policy Naming Conventions

## Policy Names Comparison

| Original Name | Simple Format | MS Format | ASD Format |
|--------------|---------------|-----------|------------|
$(($namedPolicies | ForEach-Object { 
    $originalName = $_.OriginalName
    $simpleFormat = $_.SimpleFormat
    $msFormat = $_.MSFormat
    $asdFormat = $_.ASDFormat
    "| $originalName | $simpleFormat | $msFormat | $asdFormat |"
}) -join "`n")

## Naming Convention Rules

### Simple MS Format: SequenceNumber-Apps-Response-Users-Conditions
- SequenceNumber: CA01-99 for regular policies, EM01-99 for emergency policies
- Apps: Target applications (AllApps, O365, etc.)
- Response: Policy action (Block, RequireMFA, etc.)
- Users: Target users (AllUsers, Admins, etc.)
- Conditions: Access conditions (ExternalAccess, Platforms, etc.)

### MS Format: Persona-PolicyType-Target-Platform-Controls
- Persona: Identifies the main user group (Global, Admins, Internals)
- PolicyType: The type of policy (BaseProtection, etc.)
- Target: The applications being targeted (AllApps or specific apps)
- Platform: Device platform requirements
- Controls: The policy controls (block, mfa, compliantDevice, etc.)

### ASD Format: Type-Action-Purpose
- Type: ADM (Admins), DEV (Devices), GST (Guests), LOC (Locations), USR (Users)
- Action: B (Block), S (Session), G (Grant)
- Purpose: Brief description of policy intent

## Persona Definitions

- **Global**: Policies that apply to all users or don't target specific groups
- **Admins**: Users with administrative roles
- **Internals**: Standard employees and end-users
"@

# Save the report
$reportPath = Join-Path $basePath "analysis/markdown/naming_conventions.md"
$report | Out-File -FilePath $reportPath -Encoding utf8
