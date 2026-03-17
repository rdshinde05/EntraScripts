<#
Lists all Service Principals in the tenant that have Microsoft Graph Mail.Read or Mail.ReadWrite
Includes:
  - Application permissions (App role assignments to Microsoft Graph)
  - Delegated permissions (OAuth2 permission grants that include Mail.Read / Mail.ReadWrite)
Enhancement:
  - Adds Owners (DisplayName + UPN if user)
Exports: SPNs_With_Mail_ReadWrite_WithOwners.csv
#>

# --------- Connect ----------
#$scopes = @("Application.Read.All","Directory.Read.All")
#Connect-MgGraph -Scopes $scopes | Out-Null

Connect-MgGraph

# --------- Constants ----------
$graphAppId    = "00000003-0000-0000-c000-000000000000"
$targetPerms   = @("Mail.Read","Mail.ReadWrite")

# --------- Helper: Get owners for a service principal ----------
function Get-SpOwnerSummary {
    param([Parameter(Mandatory=$true)][string]$ServicePrincipalId)

    try {
        # Returns directoryObjects (users, servicePrincipals, etc.)
        $owners = Get-MgServicePrincipalOwner -ServicePrincipalId $ServicePrincipalId -All
    } catch {
        $owners = @()
    }

    if (-not $owners) {
        return [PSCustomObject]@{
            Owners     = ""
            OwnerUPNs  = ""
            OwnerCount = 0
        }
    }

    $ownerNames = @()
    $ownerUPNs  = @()

    foreach ($o in $owners) {
        # Try to resolve to a user (UPN exists) otherwise treat as generic directory object
        try {
            $u = Get-MgUser -UserId $o.Id -Property "displayName,userPrincipalName" -ErrorAction Stop
            $ownerNames += $u.DisplayName
            if ($u.UserPrincipalName) { $ownerUPNs += $u.UserPrincipalName }
            continue
        } catch { }

        try {
            $sp = Get-MgServicePrincipal -ServicePrincipalId $o.Id -Property "displayName,appId" -ErrorAction Stop
            $ownerNames += ("SPN:" + $sp.DisplayName)
            continue
        } catch { }

        # Fallback
        if ($o.AdditionalProperties.displayName) {
            $ownerNames += [string]$o.AdditionalProperties.displayName
        } else {
            $ownerNames += $o.Id
        }
    }

    [PSCustomObject]@{
        Owners     = ($ownerNames | Sort-Object -Unique) -join "; "
        OwnerUPNs  = ($ownerUPNs  | Sort-Object -Unique) -join "; "
        OwnerCount = ($ownerNames | Sort-Object -Unique).Count
    }
}

# --------- Get Microsoft Graph service principal ----------
$graphSp = Get-MgServicePrincipal -Filter "appId eq '$graphAppId'" -Property "id,appId,displayName,appRoles,oauth2PermissionScopes"
if (-not $graphSp) { throw "Microsoft Graph service principal not found in this tenant." }

# App roles = Application permissions
$mailAppRoles = @($graphSp.AppRoles | Where-Object { $_.Value -in $targetPerms })

# --------- Application permissions: AppRoleAssignments ----------
$appRoleAssignments = Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $graphSp.Id -All

$appResults = foreach ($a in $appRoleAssignments) {
    $role = $mailAppRoles | Where-Object { $_.Id -eq $a.AppRoleId }
    if ($role) {
        $sp = Get-MgServicePrincipal -ServicePrincipalId $a.PrincipalId -Property "id,appId,displayName"
        $ownerInfo = Get-SpOwnerSummary -ServicePrincipalId $sp.Id

        [PSCustomObject]@{
            DisplayName        = $sp.DisplayName
            AppId              = $sp.AppId
            ServicePrincipalId = $sp.Id
            PermissionType     = "Application"
            Permission         = $role.Value
            ConsentType        = $null
            Owners             = $ownerInfo.Owners
            OwnerUPNs          = $ownerInfo.OwnerUPNs
            OwnerCount         = $ownerInfo.OwnerCount
        }
    }
}

# --------- Delegated permissions: OAuth2PermissionGrants ----------
$oauthGrants = Get-MgOauth2PermissionGrant -All

$delegatedResults = foreach ($g in $oauthGrants) {
    if ($null -ne $g.Scope -and ($g.Scope -match "(^| )Mail\.Read( |$)|(^| )Mail\.ReadWrite( |$)")) {
        $sp = Get-MgServicePrincipal -ServicePrincipalId $g.ClientId -Property "id,appId,displayName"
        $ownerInfo = Get-SpOwnerSummary -ServicePrincipalId $sp.Id

        $matched = @()
        foreach ($p in $targetPerms) {
            if ($g.Scope -match "(^| )$([regex]::Escape($p))( |$)") { $matched += $p }
        }

        foreach ($m in $matched) {
            [PSCustomObject]@{
                DisplayName        = $sp.DisplayName
                AppId              = $sp.AppId
                ServicePrincipalId = $sp.Id
                PermissionType     = "Delegated"
                Permission         = $m
                ConsentType        = $g.ConsentType
                Owners             = $ownerInfo.Owners
                OwnerUPNs          = $ownerInfo.OwnerUPNs
                OwnerCount         = $ownerInfo.OwnerCount     }
        }
    }
}

# --------- Combine + Deduplicate ----------
$final = @($appResults + $delegatedResults) |
    Where-Object { $_ -ne $null } |
    Sort-Object PermissionType, DisplayName, Permission -Unique

# --------- Output ----------
$final | Format-Table -AutoSize

# --------- Export CSV ----------
$csvPath = Join-Path (Get-Location) "SPNs_With_Mail_ReadWrite_WithOwners.csv"
$final | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "`nExported: $csvPath" -ForegroundColor Green
