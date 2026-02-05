## Power BI Workspace Audit
## Benjamin Barshaw <benjamin.barshaw@ode.oregon.gov> - IT Operations & Support Network Team Lead - Oregon Department of Education
#
#  Requirements: MicrosoftPowerBIMgmt PowerShell Module (Install-Module -Name MicrosoftPowerBIMgmt)
#                Fabric/PowerBI Administrator PIM Role
#                Must be connected to the tenant's Power BI space with Login-PowerBIServiceAccount
#
#  This script was created to determine which Power BI workspaces in our tenant were no longer being used. We use the Get-PowerBIActivityEvent cmdlet to retrieve activity logs going back as far as we can go. The cmdlet does not allow you to select date ranges -- you MUST
#  use the same day in the StartDateTime and EndDateTime parameters. To get all logs for a given day we set our StartDateTime for midnight (00:00:00) and our EndDateTime for 1 minute 'til midnight (23:59:59).  The cmdlet is also tricky in that if you select a date out of the 
#  range that it still has data for, it does not give you any useful sort of error it just fails with "Get-PowerBIActivityEvent: Operation returned an invalid status code 'BadRequest'".  For this reason we set a $tryStartDate variable with how many days we wish to attempt to
#  go back and then decrement that integer until we get to 0 pulling logs for each date (30 days ago, 29 days ago, 28 days ago, ad nauseam) as we make our way to today's date. We then retrieve all NON-PERSONAL Power BI workspaces in the tenant and query the logs we pulled for
#  any activity in them. If found, the CSV we export will show the most recent time of the last activity found. We also export any users belonging to the workspace by the access type they possess -- Admin, Contributor, Member, Viewer.  The CSV will be exported to the Current
#  Working Directory (CWD) as PBI_Workspace_Audit-<MMddyyyy>.csv with MMddyyyy being today's date.
#  
### USER DEFINED VARIABLES SECTION ###
# I wouldn't change this, but here is where we define how far back we would care to try
$tryStartDate = 30
### END USER DEFINED VARIABLES SECTION ###

# Create the columns of our CSV export -- originally I had lumped all users into one column but by request split them up into access types
class PBIWorkspace
{
    [string]$WorkspaceName
    [string]$WorkspaceId
    [string]$State
    [string]$LastUsed    
    #[string]$Users # Commented out but left in for posterity
    [string]$Admins
    [string]$Contributors
    [string]$Members
    [string]$Viewers
}

# Get today's date in a format for the CSV
$exportDate = Get-Date -Format MMddyyyy
# Get today's date in a format for Get-Date
$getToday = Get-Date -Format MM/dd/yyyy
# If we just did Get-Date it would return the date with the current time -- by specifying -Date $getToday for today's date it makes the time start at midnight since we want the whole day's worth of activity
$getDate = Get-Date -Date $getToday
# Initialize the array that will house ALL the logs
$getPBILogs = @()

$version = "v1.0"

# If we are connected to the Power BI space we'll get a token (unused) and keep going. If we are NOT connected it will throw an error and attempt to login to the Power BI space. It's tricky, tricky, tricky - Run DMC
try
{
    $areWeConnected = Get-PowerBIAccessToken
}
catch
{
    Login-PowerBIServiceAccount
    $areWeConnected = Get-PowerBIAccessToken
}

# Exit if we are unable to login to Power BI space
If (! $areWeConnected)
{
    Write-Host -ForegroundColor Red "We are not connected to the Power BI space in the tenant! Exiting..."
    exit
}

Write-Host -ForegroundColor Cyan "Power BI Workspace Audit Script $($version) - Benjamin Barshaw <benjamin.barshaw@ode.oregon.gov>"
Write-Host -ForegroundColor Cyan "Getting all non-personal Power BI workspaces in tenant..."
# Retrieve all the Power BI workspaces that aren't "PersonalGroup" -- these are personal Power BI spaces and we aren't interested in them for the audit. If we were interested in those we would simpy remove there Where-Object
$getPBIWorkspaces = Get-PowerBIWorkspace -Scope Organization -All | Where-Object { $_.Type -ne "PersonalGroup" }
Write-Host -ForegroundColor Magenta "Found $($getPBIWorkspaces.Count) workspaces!"

# Start at 30 days ago and work our way down to 0
For ($i = $tryStartDate; $i -ge 0; $i--)
{
    Write-Host -ForegroundColor DarkCyan "Getting workspace activity from $($i) days ago..."
    # Here we go back $i days at midnight    
    $startDate = ($getDate).AddDays(-$i)
    # Here we go back $i days at 1 minute 'til midnight
    $endDate = Get-Date -Date $startDate -Hour 23 -Minute 59 -Second 59
    # Oh yeah - this cmdlet is a REAL JERK about the format of the time you give it. I found out after I came up with this that the same thing could have been accomplished with (Get-Date -Date $startDate).ToString("s") -- live and learn
    $startTime = (Get-Date -Format "o" -Date ($startDate).ToString()).Split('.')[0]
    $endTime = (Get-Date -Format "o" -Date ($endDate).ToString()).Split('.')[0]

    try
    {
        # Retrieve the logs for the day
        $getJson = Get-PowerBIActivityEvent -StartDateTime $startTime -EndDateTime $endTime -ErrorAction Stop
        # Add all the logs for the day to our array
        $getPBILogs += $getJson
    }
    catch
    {
        # I'm fairly confident you'll get at least one of these if you kept the $tryStartDate variable at 30
        Write-Host -ForegroundColor Red "Problem getting Power BI Activity Events from $($i) days ago!"
    }    
}

# Convert our JSON to PowerShell objects for searching
$getSearchable = $getPBILogs | ConvertFrom-Json

# Cycle through all retrieved PBI workspaces
ForEach ($pbiWorkspace in $getPBIWorkspaces)
{
    Write-Host -ForegroundColor Yellow "Working on $($pbiWorkspace.Name)..."
    
    # Create arrays for all the potential various access rights -- we'll add users into their respective array
    $adminsTempArray = @()
    $contributorsTempArray = @()
    $membersTempArray = @()
    $viewersTempArray = @()

    # Create our class object and start populating it with data retrieved from the Get-PowerBIWorkspace cmdlet
    $exportMe = [PBIWorkspace]::new()
    $exportMe.WorkspaceName = $pbiWorkspace.Name
    $exportMe.WorkspaceId = $pbiWorkspace.Id
    $exportMe.State = $pbiWorkspace.State
    
    # Try to find activity in our large log array for the current workspace
    $findWorkspace = $getSearchable | Where-Object { $_.WorkspaceName -eq $pbiWorkspace.Name }
    If ($findWorkspace)
    {
        # If we find activity/activities, we sort them and use [-1] to get the LAST object which after sorting should be the most recent
        $exportMe.LastUsed = ($findWorkspace.CreationTime | Sort-Object)[-1]
    }
    Else
    {
        # If no activity found just put a dash
        $exportMe.LastUsed = "-"
    }
    
    # Cycle through all the users found for the workspace
    ForEach ($pbiUser in $pbiWorkspace.Users)
    {
        # We use the access right (permission) to add the users into their respective array
        switch ($pbiUser.AccessRight)
        {
            "Admin"
            {
                $adminsTempArray += $pbiUser.UserPrincipalName
            }
            "Contributor"
            {
                $contributorsTempArray += $pbiUser.UserPrincipalName
            }
            "Member"
            {
                $membersTempArray += $pbiUser.UserPrincipalName
            }
            "Viewer"
            {
                $viewersTempArray += $pbiUser.UserPrincipalName
            }
        }
    }

    # This was when I had them all in one column -- left for posterity
    #$exportMe.Users = $pbiWorkspace.Users.UserPrincipalName -join ","
    
    # We take any users found in the access right arrays and join them together into a string separating them with a comma
    $exportMe.Admins = $adminsTempArray -join ", "
    $exportMe.Contributors = $contributorsTempArray -join ", "
    $exportMe.Members = $membersTempArray -join ", "
    $exportMe.Viewers = $viewersTempArray -join ", "    

    # Export our populated PBIWorkSpace class object to the CSV
    $exportMe | Export-Csv -Append -NoTypeInformation -Path ".\PBI_Workspace_Audit-$exportDate.csv"
}
# FIN