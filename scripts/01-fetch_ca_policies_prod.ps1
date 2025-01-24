# Ensure required modules are installed
Import-Module Microsoft.Graph.Identity.SignIns
Import-Module Microsoft.Graph.Groups
Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Identity.DirectoryManagement

# Create directories if they don't exist
$basePath = Split-Path -Path $PSScriptRoot -Parent
$originalPath = Join-Path $basePath "policies/original"
$dataPath = Join-Path $basePath "policies/data"

New-Item -ItemType Directory -Force -Path $originalPath
New-Item -ItemType Directory -Force -Path $dataPath

# Function to get group details
function Get-GroupDetails {
    param($groupId)
    try {
        $group = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
        $members = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$groupId/members/`$count" -Headers @{"ConsistencyLevel"="eventual"}
        
        return @{
            id = $group.id
            displayName = $group.displayName
            memberCount = [int]$members
        }
    }
    catch {
        Write-Warning "Failed to get details for group $groupId"
        return $null
    }
}

# Function to get user details
function Get-UserDetails {
    param($userId)
    try {
        $user = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$userId"
        return @{
            id = $user.id
            userPrincipalName = $user.userPrincipalName
            displayName = $user.displayName
        }
    }
    catch {
        Write-Warning "Failed to get details for user $userId"
        return $null
    }
}

# Add new function to get role template details
function Get-DirectoryRoleTemplateDetails {
    param($roleTemplateId)
    try {
        $role = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/directoryRoleTemplates/$roleTemplateId"
        return @{
            id = $role.id
            displayName = $role.displayName
        }
    }
    catch {
        Write-Warning "Failed to get details for role template $roleTemplateId"
        return $null
    }
}

# Modified Get-DirectoryRoleDetails function
function Get-DirectoryRoleDetails {
    param($roleId)
    try {
        $role = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/directoryRoles/$roleId"
        return @{
            id = $role.id
            displayName = $role.displayName
        }
    }
    catch {
        # If direct role lookup fails, try getting it from role templates
        $roleTemplate = Get-DirectoryRoleTemplateDetails -roleTemplateId $roleId
        if ($roleTemplate) {
            return $roleTemplate
        }
        Write-Warning "Failed to get details for role $roleId"
        return $null
    }
}

# Update Get-ApplicationDetails function to handle both GUID and friendly names
function Get-ApplicationDetails {
    param($appId)
    
    # Define basic known apps (for non-GUID identifiers)
    $basicKnownApps = @{
        "MicrosoftAdminPortals" = "Microsoft Admin Portals"
        "Office365" = "Office 365"
        "All" = "All Applications"
    }

    # Check basic known apps first
    if ($basicKnownApps.ContainsKey($appId)) {
        return @{
            displayName = $basicKnownApps[$appId]
            id = $appId
        }
    }
    
    # Load known applications from file (for GUID identifiers)
    $knownAppsPath = Join-Path (Split-Path -Path $PSScriptRoot -Parent) "config/knownApps.txt"
    $knownApps = @{}
    
    if (Test-Path $knownAppsPath) {
        Get-Content $knownAppsPath | ForEach-Object {
            if ($_ -match '^"([^"]+)"\s*=\s*"([^"]+)"$') {
                $knownApps[$matches[1]] = $matches[2]
            }
        }
    } else {
        Write-Warning "Known apps file not found at: $knownAppsPath"
    }

    # Check if it's a known GUID app
    if ($knownApps.ContainsKey($appId)) {
        return @{
            displayName = $knownApps[$appId]
            id = $appId
        }
    }

    # Only try Graph API for GUID-like strings
    if ($appId -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
        try {
            $app = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals(appId='$appId')"
            return @{
                displayName = $app.displayName
                id = $appId
            }
        }
        catch {
            Write-Warning "Failed to get details for application $appId"
        }
    }

    # Return unknown application if all else fails
    return @{
        displayName = "Unknown Application ($appId)"
        id = $appId
    }
}

# Add function to reorder policy properties
function Get-ReorderedPolicy {
    param($policy)
    
    # Create new ordered hashtable
    $orderedPolicy = [ordered]@{}
    
    # Add displayName first if it exists
    if ($policy.displayName) {
        $orderedPolicy['displayName'] = $policy.displayName
    }
    
    # Add all other properties
    foreach ($prop in $policy.PSObject.Properties) {
        if ($prop.Name -ne "displayName") {
            $orderedPolicy[$prop.Name] = $prop.Value
        }
    }
    
    return $orderedPolicy
}

# Add function to sanitize filenames
function Get-SafeFilename {
    param(
        [string]$filename,
        [string]$defaultName = "unnamed_policy"
    )
    if ([string]::IsNullOrWhiteSpace($filename)) {
        return $defaultName
    }

    # Replace invalid characters and control characters
    $invalids = [System.IO.Path]::GetInvalidFileNameChars()
    $replacement = '_'
    
    # Replace invalid chars and control chars
    $safeName = [RegEx]::Replace($filename, "[$([RegEx]::Escape(-join $invalids))]", $replacement)
    
    # Replace multiple consecutive underscores with single underscore
    $safeName = $safeName -replace '_{2,}', '_'
    
    # Trim underscores from start and end
    $safeName = $safeName.Trim('_')
    
    # Ensure we have a valid filename
    if ([string]::IsNullOrWhiteSpace($safeName)) {
        return $defaultName
    }
    
    # Truncate if too long (Windows max path is 260, leave room for path and extension)
    $maxLength = 200
    if ($safeName.Length -gt $maxLength) {
        $safeName = $safeName.Substring(0, $maxLength)
        $safeName = $safeName.TrimEnd('_')
    }
    
    return $safeName
}

# Get all CA policies
$policies = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies"

# Save original policies individually by name
foreach ($policy in $policies.value) {
    $fileName = Get-SafeFilename -filename $policy.displayName -defaultName $policy.id
    $policy | ConvertTo-Json -Depth 100 | Out-File (Join-Path $originalPath "$fileName.json")
}

# Process each policy
foreach ($policy in $policies.value) {
    $enhancedPolicy = $policy | ConvertTo-Json -Depth 100 | ConvertFrom-Json

    # Process applications section
    if ($policy.conditions.applications) {
        if ($policy.conditions.applications.includeApplications) {
            $enhancedApps = @{}
            foreach ($appId in $policy.conditions.applications.includeApplications) {
                if ($appId -ne "All") {
                    $appDetails = Get-ApplicationDetails -appId $appId
                    if ($appDetails) {
                        $enhancedApps[$appId] = $appDetails
                    }
                } else {
                    $enhancedApps = @("All")
                    break
                }
            }
            $enhancedPolicy.conditions.applications.includeApplications = $enhancedApps
        }

        # Same pattern for excludeApplications
        if ($policy.conditions.applications.excludeApplications) {
            $enhancedApps = @{}
            foreach ($appId in $policy.conditions.applications.excludeApplications) {
                $appDetails = Get-ApplicationDetails -appId $appId
                if ($appDetails) {
                    $enhancedApps[$appId] = $appDetails
                }
            }
            $enhancedPolicy.conditions.applications.excludeApplications = $enhancedApps
        }
    }

    # Process users section
    if ($policy.conditions.users) {
        $users = @{}
        $userLists = @(
            @{ Path = 'includeUsers'; List = $policy.conditions.users.includeUsers },
            @{ Path = 'excludeUsers'; List = $policy.conditions.users.excludeUsers }
        )

        foreach ($userList in $userLists) {
            if ($userList.List) {
                $enhancedUsers = @{}
                foreach ($userId in $userList.List) {
                    if ($userId -ne "All") {
                        $userDetails = Get-UserDetails -userId $userId
                        if ($userDetails) {
                            $enhancedUsers[$userId] = $userDetails
                        }
                    } else {
                        $enhancedUsers = @("All")
                        break
                    }
                }
                $enhancedPolicy.conditions.users."$($userList.Path)" = $enhancedUsers
            }
        }

        # Process groups
        $groupLists = @(
            @{ Path = 'includeGroups'; List = $policy.conditions.users.includeGroups },
            @{ Path = 'excludeGroups'; List = $policy.conditions.users.excludeGroups }
        )

        foreach ($groupList in $groupLists) {
            if ($groupList.List) {
                $enhancedGroups = @{}
                foreach ($groupId in $groupList.List) {
                    $groupDetails = Get-GroupDetails -groupId $groupId
                    if ($groupDetails) {
                        $enhancedGroups[$groupId] = $groupDetails
                    }
                }
                $enhancedPolicy.conditions.users."$($groupList.Path)" = $enhancedGroups
            }
        }

        # Process roles
        $roleLists = @(
            @{ Path = 'includeRoles'; List = $policy.conditions.users.includeRoles },
            @{ Path = 'excludeRoles'; List = $policy.conditions.users.excludeRoles }
        )

        foreach ($roleList in $roleLists) {
            if ($roleList.List) {
                $enhancedRoles = @{}
                foreach ($roleId in $roleList.List) {
                    $roleDetails = Get-DirectoryRoleDetails -roleId $roleId
                    if ($roleDetails) {
                        $enhancedRoles[$roleId] = $roleDetails
                    }
                }
                $enhancedPolicy.conditions.users."$($roleList.Path)" = $enhancedRoles
            }
        }
    }

    # Reorder properties
    $enhancedPolicy = Get-ReorderedPolicy -policy $enhancedPolicy

    # Save enhanced policy
    $fileName = Get-SafeFilename -filename $policy.displayName -defaultName $policy.id
    $enhancedPolicy | ConvertTo-Json -Depth 100 | Out-File (Join-Path $dataPath "$fileName.json")
}

Write-Host "Processing complete. Check the policies folder for results."
