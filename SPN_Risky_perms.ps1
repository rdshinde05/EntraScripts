# -------------------------
# SPN High-Risk Permission Audit (Graph) + Owners
# -------------------------
$ErrorActionPreference = 'Stop'

Write-Host "=== Starting SPN High-Risk Permission Audit ===" -ForegroundColor Cyan

# 1) Connect to Graph with enough scopes for app perms + delegated grants + owners
$scopes = @(
  "Application.Read.All",
  "Directory.Read.All",
  "DelegatedPermissionGrant.Read.All"   # often needed to read OAuth2PermissionGrants
)

Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
Connect-MgGraph -Scopes $scopes | Out-Null
$ctx = Get-MgContext
Write-Host ("Connected. TenantId: {0}, Account: {1}" -f $ctx.TenantId, $ctx.Account) -ForegroundColor Green

# 2) Risky permissions list (edit if you want)
$riskyPerms = @(
  "Directory.ReadWrite.All",
  "RoleManagement.ReadWrite.Directory",
  "Application.ReadWrite.All",
  "AppRoleAssignment.ReadWrite.All",
  "Domain.ReadWrite.All",
  "Policy.ReadWrite.ConditionalAccess",
  "UserAuthenticationMethod.ReadWrite.All",
  "IdentityRiskEvent.ReadWrite.All",
  "User.ReadWrite.All",
  "Group.ReadWrite.All",
  "Mail.Read",
  "Mail.ReadWrite",
  "Mail.Send",
  "Files.Read.All",
  "Files.ReadWrite.All",
  "Sites.Read.All",
  "Sites.ReadWrite.All",
  "offline_access"
)

# 3) Get Microsoft Graph service principal (permission catalog)
$graphAppId = "00000003-0000-0000-c000-000000000000"
Write-Host "Fetching Microsoft Graph service principal..." -ForegroundColor Yellow
$graphSp = Get-MgServicePrincipal -Filter "appId eq '$graphAppId'" -Property "id,appId,displayName,appRoles,oauth2PermissionScopes"
if (-not $graphSp) { throw "Microsoft Graph service principal not found." }

Write-Host ("Graph SP OK: {0} ({1})" -f $graphSp.DisplayName, $graphSp.Id) -ForegroundColor Green

# 4) Build mappings for Application permissions (appRoles) and Delegated scopes
$appRoleMap = @{}
foreach ($r in $graphSp.AppRoles) {
  if ($r.Value -and ($r.AllowedMemberTypes -contains "Application")) {
    $appRoleMap[[string]$r.Id] = $r.Value
  }
}

$delegatedScopeSet = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($s in $graphSp.Oauth2PermissionScopes) {
  if ($s.Value) { [void]$delegatedScopeSet.Add($s.Value) }
}

$riskyAppRoleIds = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($kv in $appRoleMap.GetEnumerator()) {
  if ($kv.Value -in $riskyPerms) { [void]$riskyAppRoleIds.Add($kv.Key) }
}

$riskyDelegatedPerms = $riskyPerms | Where-Object { $_ -in $delegatedScopeSet }

Write-Host ("Risky app-role IDs loaded: {0}" -f $riskyAppRoleIds.Count) -ForegroundColor Gray
Write-Host ("Risky delegated scopes found in Graph catalog: {0}" -f ($riskyDelegatedPerms.Count)) -ForegroundColor Gray

# 5) Owner resolver (cached)
$ownerCache = @{}

function Get-SpOwnerSummary {
  param([Parameter(Mandatory=$true)][string]$ServicePrincipalId)

  if ($ownerCache.ContainsKey($ServicePrincipalId)) { return $ownerCache[$ServicePrincipalId] }

  $owners = @()
  try {
    $owners = Get-MgServicePrincipalOwner -ServicePrincipalId $ServicePrincipalId -All
  } catch {
    $owners = @()
  }

  $ownerNames = @()
  $ownerUPNs  = @()

  foreach ($o in $owners) {
    # Resolve as user if possible
    try {
      $u = Get-MgUser -UserId $o.Id -Property "displayName,userPrincipalName" -ErrorAction Stop
      if ($u.DisplayName) { $ownerNames += $u.DisplayName }
      if ($u.UserPrincipalName) { $ownerUPNs += $u.UserPrincipalName }
      continue
    } catch {}

    # Resolve as service principal owner
    try {
      $sp2 = Get-MgServicePrincipal -ServicePrincipalId $o.Id -Property "displayName" -ErrorAction Stop
      if ($sp2.DisplayName) { $ownerNames += ("SPN:" + $sp2.DisplayName) }
      continue
    } catch {}

    # Fallback
    if ($o.AdditionalProperties.displayName) { $ownerNames += [string]$o.AdditionalProperties.displayName }
    else { $ownerNames += $o.Id }
  }

  $result = [PSCustomObject]@{
    Owners     = (($ownerNames | Sort-Object -Unique) -join "; ")
    OwnerUPNs  = (($ownerUPNs  | Sort-Object -Unique) -join "; ")
    OwnerCount = (($ownerNames | Sort-Object -Unique).Count)
  }

  $ownerCache[$ServicePrincipalId] = $result
  return $result
}

# 6) Fetch OAuth2 delegated grants to Microsoft Graph (for all apps)
Write-Host "Fetching OAuth2PermissionGrants (delegated consents)..." -ForegroundColor Yellow
$allGrants = Get-MgOauth2PermissionGrant -All -Property "clientId,consentType,resourceId,scope,principalId"
$graphGrants = $allGrants | Where-Object { $_.ResourceId -eq $graphSp.Id -and $_.Scope }
Write-Host ("Delegated grants to Graph found: {0}" -f $graphGrants.Count) -ForegroundColor Green

# Index grants by clientId (service principal id)
$grantMap = @{}
foreach ($g in $graphGrants) {
  if (-not $grantMap.ContainsKey($g.ClientId)) { $grantMap[$g.ClientId] = @() }
  $grantMap[$g.ClientId] += $g
}

# 7) Enumerate Service Principals
Write-Host "Fetching all service principals..." -ForegroundColor Yellow
$sps = Get-MgServicePrincipal -All -Property "id,appId,displayName"
Write-Host ("Total service principals: {0}" -f $sps.Count) -ForegroundColor Green

$results = New-Object 'System.Collections.Generic.List[object]'
$processed = 0

foreach ($sp in $sps) {
  $processed++

  # --- Application permissions: appRoleAssignments for this SP ---
  # Use ResourceId filter to reduce noise
  $assignments = @()
  try {
    $assignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -All
  } catch {
    # If a single SP errors, continue but DO NOT stay silent
    Write-Host ("WARN: Failed AppRoleAssignments for {0} ({1}) : {2}" -f $sp.DisplayName,$sp.Id,$_.Exception.Message) -ForegroundColor DarkYellow
    $assignments = @()
  }

  foreach ($a in $assignments) {
    if ($a.ResourceId -ne $graphSp.Id) { continue }
    if (-not $a.AppRoleId) { continue }

    $roleId = [string]$a.AppRoleId
    if ($riskyAppRoleIds.Contains($roleId)) {
      $permName = $appRoleMap[$roleId]
      $ownerInfo = Get-SpOwnerSummary -ServicePrincipalId $sp.Id

      $results.Add([PSCustomObject]@{
        DisplayName        = $sp.DisplayName
        AppId              = $sp.AppId
        ServicePrincipalId = $sp.Id
        PermissionType     = "Application"
        Permission         = $permName
        ConsentType        = $null
        Owners             = $ownerInfo.Owners
        OwnerUPNs          = $ownerInfo.OwnerUPNs
        OwnerCount         = $ownerInfo.OwnerCount
      }) | Out-Null
    }
  }

  # --- Delegated permissions: OAuth2 grants indexed by SP.Id ---
  if ($grantMap.ContainsKey($sp.Id)) {
    $ownerInfo = Get-SpOwnerSummary -ServicePrincipalId $sp.Id
    foreach ($g in $grantMap[$sp.Id]) {
      $scopes = ($g.Scope -split "\s+") | Where-Object { $_ }
      foreach ($s in $scopes) {
        if ($s -in $riskyDelegatedPerms) {
          $results.Add([PSCustomObject]@{
            DisplayName        = $sp.DisplayName
            AppId              = $sp.AppId
            ServicePrincipalId = $sp.Id
            PermissionType     = "Delegated"
            Permission         = $s
            ConsentType        = $g.ConsentType
            Owners             = $ownerInfo.Owners
            OwnerUPNs          = $ownerInfo.OwnerUPNs
            OwnerCount         = $ownerInfo.OwnerCount
          }) | Out-Null
        }
      }
    }
  }

  # Occasional heartbeat so you SEE activity
  if ($processed % 200 -eq 0) {
    Write-Host ("Processed {0}/{1} SPNs..." -f $processed, $sps.Count) -ForegroundColor Gray
  }
}

# 8) Output & export
$final = $results | Sort-Object PermissionType, DisplayName, Permission -Unique

Write-Host "=== Completed ===" -ForegroundColor Cyan
Write-Host ("Findings: {0}" -f $final.Count) -ForegroundColor Green

if ($final.Count -eq 0) {
  Write-Host "No risky permissions found for the configured list." -ForegroundColor Yellow
} else {
  $final | Format-Table -AutoSize
}

$csvPath = Join-Path (Get-Location) "SPN_HighRiskPermissions_WithOwners.csv"
$final | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host ("CSV exported: {0}" -f $csvPath) -ForegroundColor Green
