##CSV Format GroupName	GroupDescription	Owners	Members

## Set execution policy (only needed once per session)
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

## Connect to Azure
Connect-AzureAD

# Import security group details from CSV file
$CSVRecords = Import-CSV "C:\Groups.csv"   ## Change file path

$TotalItems = $CSVRecords.Count
$i = 0

# Iterate through groups
ForEach ($CSVRecord in $CSVRecords) {
    $GroupName        = $CSVRecord."GroupName"
    $GroupDescription = $CSVRecord."GroupDescription"
    $Owners           = if ($CSVRecord."Owners")  { $CSVRecord."Owners" -split ';' } else { $null }
    $Members          = if ($CSVRecord."Members") { $CSVRecord."Members" -split ';' } else { $null }

    Try {
        $i++
        Write-Progress -Activity "Processing group $GroupName" -Status "$i out of $TotalItems"

        # Check if group already exists
        $ExistingGroup = Get-AzureADGroup -Filter "DisplayName eq '$GroupName'"

        if ($ExistingGroup) {
            Write-Host "Group '$GroupName' already exists. Skipping creation." -ForegroundColor Yellow
        }
        else {
            # Create new group
            $NewGroup = New-AzureADGroup -DisplayName $GroupName `
                                         -Description $GroupDescription `
                                         -MailEnabled $false `
                                         -SecurityEnabled $true `
                                         -MailNickname $GroupName.Replace(" ","")

            Write-Host "Group '$GroupName' created successfully." -ForegroundColor Green

            # Add owners
            if ($Owners) {
                foreach ($Owner in $Owners) {
                    $OwnerObj = Get-AzureADUser -ObjectId $Owner -ErrorAction SilentlyContinue
                    if ($OwnerObj) {
                        Add-AzureADGroupOwner -ObjectId $NewGroup.ObjectId -RefObjectId $OwnerObj.ObjectId
                    }
                }
            }

            # Add members
            if ($Members) {
                foreach ($Member in $Members) {
                    $MemberObj = Get-AzureADUser -ObjectId $Member -ErrorAction SilentlyContinue
                    if ($MemberObj) {
                        Add-AzureADGroupMember -ObjectId $NewGroup.ObjectId -RefObjectId $MemberObj.ObjectId
                    }
                }
            }

            # Validation step: show group details
            $CreatedGroup = Get-AzureADGroup -ObjectId $NewGroup.ObjectId
            $CreatedOwners = Get-AzureADGroupOwner -ObjectId $NewGroup.ObjectId | Select-Object -ExpandProperty UserPrincipalName

            Write-Host "`nValidation for group '$($CreatedGroup.DisplayName)':"
            Write-Host " - Group Name: $($CreatedGroup.DisplayName)"
            Write-Host " - Group Owner(s): $($CreatedOwners -join ', ')"
            Write-Host " - Created DateTime: $($CreatedGroup.CreationDateTime)"
            Write-Host ""
        }
    }
    Catch {
        Write-Host "Error creating group $GroupName: $_" -ForegroundColor Red
    }
}

