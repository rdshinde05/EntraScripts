#Use below script to pull all Group owned by any User in Entra
#CSV Format 
#UserUPN
#first.last@domain.com
#second.user@domain.com
#third.user@domain.com

# Connect to Azure AD
Connect-AzureAD

# Path to input CSV (list of user UPNs)
$InputCSV = "C:\Temp\Users.csv"   # Change path as needed
$OutputCSV = "C:\Temp\UserOwnedGroups.csv" # Change path as needed

# Import user list
$Users = Import-Csv -Path $InputCSV

# Initialize array for results
$Results = @()

foreach ($UserRecord in $Users) {
    $UserUPN = $UserRecord.UserUPN
    Write-Host "Processing user: $UserUPN" -ForegroundColor Cyan

    # Get user object
    $User = Get-AzureADUser -ObjectId $UserUPN -ErrorAction SilentlyContinue
    if ($User) {
        # Get groups owned by the user
        $Groups = Get-AzureADUserOwnedObject -ObjectId $User.ObjectId | Where-Object { $_.ObjectType -eq "Group" }

        foreach ($Group in $Groups) {
            $Results += [PSCustomObject]@{
                UserUPN      = $UserUPN
                GroupObjectId = $Group.ObjectId
                GroupName     = $Group.DisplayName
                Description   = $Group.Description
            }
        }
    }
    else {
        Write-Host "User not found: $UserUPN" -ForegroundColor Yellow
    }
}

# Export results to CSV
$Results | Export-Csv -Path $OutputCSV -NoTypeInformation
Write-Host "Export completed. File saved at: $OutputCSV" -ForegroundColor Green
