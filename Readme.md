## Problem Statement
The data scanning for newly added storage account does not work unless user adds event grid subscription manually or re-runs the powershell script which was used during account onboarding. 

## Purpose
The script is responsible for creating event subscription in a newly added storage account. The event subscription will have a webhook configured with an encrypted token which will give the information about the valid tenant to CloudSoc. 
In case script fails at any step, the resources created through script will be deleted. It will ask for permission to delete the resource to avoid unnecessary issues.

## Permissions required
The user running the script should have following roles assigned: 
1. You can create custom role with below permissions or assign pre-defined roles having above permissions. 
"Microsoft.Authorization/roleAssignments/read",
"Microsoft.Authorization/roleAssignments/write",
"Microsoft.Resources/subscriptions/resourceGroups/read",
"Microsoft.Resources/subscriptions/resourceGroups/write",
"Microsoft.Resources/subscriptions/resourceGroups/delete"
2. Storage Account Contributor
3. EventGrid Contributor
4. Website Contributor 

## Pre-requisites
- 'Az.Functions' = '4.0.7'
- 'Az.Resources' = '6.16.1'
- 'Az.EventGrid' = '1.6.1'

## Execution Steps
1. Download the git files
2. Extract cloudsoc-powershell-function.zip 
3. Open file /cloudsoc-powershell-function/AddWebHookToNewStorageAccount/run.ps1
4. Get $webhook_url and $perpetual_token from connection powershell script and copy them here
5. Create zip file again of folder cloudsoc-powershell-function
6. Open deploy.ps1 and specify the $archivePath as zip file name. Edit other parameters if required.
    - $location = "eastus"
    - $resourceGroup = cloudsoc-azure-functions-rg # This can be existing resource group, the script will create new one if not found
    - $storage =  cloudsocstg # This can be existing storage account, the script will create new one if not found
    - $functionApp = cloudsoc-powershell-function # The script will create new function app 
    - $skuStorage = "Standard_LRS"
 7. Run ./depoly.ps1

## Resources Created
1. Resource Group 
2. Storage Account 
3. Function App - The function app will event grid subscription for newly created storage account
4. Function App will have "EventGrid Contributor", "EventGrid Data Receiver", "Reader and Data Access" permissions on all subscriptions
4. Event grid subscription for new resources

