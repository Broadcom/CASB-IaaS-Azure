#cloudsoc-azure-functions-rg-813577963

# Function app and storage account names must be unique.
# Variable block
$randomIdentifier = Get-Random
$location = "eastus"
$resourceGroup = "cloudsoc-azure-functions-rg-$randomIdentifier"
$storage =  "cloudsocstg$randomIdentifier"
$functionApp = "cloudsoc-powershell-function-$randomIdentifier"
$tag = @{} # If you want to assign tags, please update the value like @{"Department"="IT","Env"="QA"}. If resource already exists, new tags will be appended
$lable_eventSub = "cloudsoc" #This lable will be assigned to event subscription
$global:existingResourceGroup = $true
$global:existingStorageAccount = $true
$global:existingFunctionApp = $true
$skuStorage = "Standard_LRS"
$archivePath = "cloudsoc-powershell-function.zip"
$event_sub_name = "cloudsocstorageacctrigger"
$osType = "Windows"
$runTime = "PowerShell"
$runTimeVersion = "7.2"
$funcVersion = "4"
$rolestobeused = "EventGrid Contributor", "EventGrid Data Receiver", "Reader and Data Access"
$global:exceptions = ""

function CombineHash([ScriptBlock]$Operator) {
    $Out = @{}
    ForEach ($h in $Input) {
        If ($h -is [Hashtable]) {
            ForEach ($Key in $h.Keys) {
                If (-Not ($Out.ContainsKey($Key))) {$Out.Add($Key,$h[$Key])}
            }
        }
    }
    If ($Operator) {ForEach ($Key in @($Out.Keys)) {$_ = @($Out.$Key); $Out.$Key = Invoke-Command $Operator}}
    $Out
}

function Store-Exceptions-In-File() {
    $exceptionkeypath = $functionApp + '_exception_details'
    if (Test-Path $exceptionkeypath -PathType leaf) {
        Clear-Content $exceptionkeypath
    }
   
    Add-Content $exceptionkeypath "Exceptions Encountered : $($global:exceptions)"
}

function Revert()
{
    Write-Host "Deleting the resources which were created through this script " -ForegroundColor DarkYellow
    # This function will ask for confirmation before deletion. If you don't want it, please add -Force parameter to Remove commands.
    try{
        if($global:existingFunctionApp -eq $false){
      
            Remove-AzWebApp -Name $functionApp -ResourceGroupName $resourceGroup  
        }
        if($global:existingStorageAccount -eq $false){
            Remove-AzStorageAccount -Name $storage -ResourceGroupName $resourceGroup  
        }
        if($global:existingResourceGroup -eq $false){
            Remove-AzResourceGroup -Name $resourceGroup  
        }
    }
    catch {
        $str = "Exception occured in while deleting resources in subscription:" + $currsub 
        Write-Error $str
        $global:exceptions += $str + $_
    }
}

function Write-Function-Details-In-File($resourceGroup, $storage, $functionApp, $archivePath) {
    $secretkeypath = $appname + '_function_details'
    if (Test-Path $secretkeypath -PathType leaf) {
        Clear-Content $secretkeypath
    }

    Add-Content $secretkeypath "Resource Group   : $($resourceGroup)"
    Add-Content $secretkeypath "Storage Account  : $($storage)"
    Add-Content $secretkeypath "Function App     : $($functionApp)"
    Add-Content $secretkeypath "Archive Path     : $($archivePath)"
    
    " "
    #"------------------------------------------------------------------------------------------------"
    Write-Host "Important: The following details are stored to the file, "$secretkeypath -ForegroundColor Yellow
    #"------------------------------------------------------------------------------------------------"
    " "
    "Resource Group : " + $resourceGroup
    "Storage Account : " + $storage
    "Function App  : " + $functionApp
    "Archive Path  : " + $archivePath
}


function Get-Subscription-Azure-Function() {
    $allsubs = ""
    Write-Host "Getting the list of subscriptions..." -ForegroundColor Gray
    if ( (Get-AzSubscription).Name ) {
        $allsubs = (Get-AzSubscription).Name
    }
    else {
        $allsubs = (Get-AzSubscription).SubscriptionName
    }
    $allsubs | Write-Host
    Write-Host "All"
    $subnames = Read-Host -Prompt 'Enter the subscription name where Azure Function App will be created '
    Set-AzContext -Subscription $subnames -ErrorAction Stop > $null
    return $subnames
}

function Get-Subscriptions() {
    $allsubs = ""
   #Write-Host "Enter the subscriptions which are configured with CloudSoc for scanning " -ForegroundColor Gray
    if ( (Get-AzSubscription).Name ) {
        $allsubs = (Get-AzSubscription).Name
    }
    else {
        $allsubs = (Get-AzSubscription).SubscriptionName
    }
    $allsubs | Write-Host
    Write-Host "All"
    $subnames = Read-Host -Prompt 'Enter the subscriptions which are configured with CloudSoc for scanning '
    if ('All' -ne $subnames  ) {
        $allsubs = $subnames.Split(",")
        Set-AzContext -Subscription $subnames.Split(',')[0] -ErrorAction Stop > $null
    }
    return $allsubs
}

function Create-Event-Subscription($event_sub_name, $app_id) {
    Write-Host "Adding event grid subscription for " $app_id
    $currsubId = (Get-AzSubscription -SubscriptionName $currsub).ID
    $includedEventTypes = "Microsoft.Resources.ResourceWriteSuccess"
    $execute_cmd = "az eventgrid event-subscription create " + 
    " --name " + $event_sub_name +
    " --source-resource-id /subscriptions/" + $currsubId + 
    " --endpoint " + $app_id +  
    " --endpoint-type azurefunction" +
    " --included-event-types " + $includedEventTypes + 
    " --advanced-filter subject StringContains storageAccounts" + 
    " --label " + $lable_eventSub

    #Helper function to call azure shell commands
    Write-Host $execute_cmd
    $result = Invoke-Expression $execute_cmd
    if ($LastExitCode -gt 0) {
        Write-Error $result
        Exit 1
    }
    $result | ConvertFrom-Json
}

# Create a resource group
function Create-ResourceGroup() {
    try{
        $rg = Get-AzResourceGroup -Name $resourceGroup -Location $location -ErrorVariable notPresent -ErrorAction SilentlyContinue
        if ($notPresent) {
            Write-Host "Creating Resource Group - $resourceGroup in $location..."
            $rg = New-AzResourceGroup -Name $resourceGroup -Location $location -Tag $tag
            $global:existingResourceGroup = $false
        }
        else{
            $resourcetags = (Get-AzResourceGroup -Name $resourceGroup -Location $location).Tags
            $resourcetags = $resourcetags , $tag | CombineHash
            Set-AzureRmResourceGroup -Name $resourceGroup -Tag $resourcetags
        }
        return $rg
    }
    catch {
        $str = "Exception occured in while creating resource group : " + $resourceGroup + " in subscription:" + $currsub 
        Write-Error $str
        $global:exceptions += $str + $_
        Write-Error $global:exceptions
    }
}

# Create a storage account
function Create-StorageAccount(){
    try{
        $storageacc = Get-AzStorageAccount -Name $storage -ResourceGroupName $resourceGroup -ErrorVariable notPresent -ErrorAction SilentlyContinue
        if ($notPresent) {
            Write-Host "Creating Storage Account - $storage"
            $storageacc = New-AzStorageAccount -Name $storage -Location $location -ResourceGroupName $resourceGroup -SkuName $skuStorage -Tag $tag
            $global:existingStorageAccount = $false
        }
        else{
            $resourcetags = (Get-AzStorageAccount -Name $storage -ResourceGroupName $resourceGroup).Tags
            $resourcetags = $resourcetags , $tag | CombineHash
            Set-AzStorageAccount -Name $storage -ResourceGroupName $resourceGroup -Tag $resourcetags
        }
        return $storageacc
    }
    catch{
        $str = "Exception occured in while creating storage account : " + $storage + " in subscription:" + $currsub 
        Write-Error $str
        $global:exceptions += $str + $_
    }
}

# Create function app and assign required permissions
function Create-FunctionApp(){
    try{
        # Create a serverless Powershell function app in the resource group.
        $web_app = Get-AzWebApp -ResourceGroupName $resourceGroup -Name $functionApp -ErrorVariable notPresent -ErrorAction SilentlyContinue
        if ($notPresent) {
            Write-Host "Creating Function App - $functionApp"
            New-AzFunctionApp -Name $functionApp -StorageAccountName $storage -Location $location -ResourceGroupName $resourceGroup -OSType $osType -Runtime $runTime -RuntimeVersion $runTimeVersion -FunctionsVersion $funcVersion -IdentityType "SystemAssigned" -Tag $tag
            $global:existingFunctionApp = $false
            # Publish Azure web app to Newly created function App
            Write-Host "Publishing Code in Function App $functionApp"
            Publish-AzWebapp -ArchivePath $archivePath -Name $functionApp -ResourceGroupName $resourceGroup -Force
        }
        else{
            $resourcetags = (Get-AzWebApp -ResourceGroupName $resourceGroup -Name $functionApp).Tags
            $resourcetags = $resourcetags , $tag | CombineHash
            Update-AzFunctionApp -ResourceGroupName $resourceGroup -Name $functionApp -Tag $resourcetags -Force
        }
    }
    catch {
        $str = "Exception occured in while creating function app : " + $functionApp + " in subscription:" + $currsub 
        Write-Error $str
        $global:exceptions += $str + $_
    }
}

function Assign-Role-FunctionApp($sub_name){
    try{
        # Create a serverless Powershell function app in the resource group.
        $web_app = Get-AzWebApp -ResourceGroupName $resourceGroup -Name $functionApp -ErrorVariable notPresent -ErrorAction SilentlyContinue
        if ($notPresent) {
            Write-Host "Assigning 'EventGrid Contributor', 'EventGrid Data Receiver', 'Reader and Data Access' role to Function App - $functionApp"
            foreach ($role in $rolestobeused) {
                if ($null -eq (Get-AzRoleAssignment -ObjectId $web_app.Identity.PrincipalId -RoleDefinitionName  $role)) {
                    $role = New-AzRoleAssignment -RoleDefinitionName $role -ObjectId $web_app.Identity.PrincipalId  -Scope "/subscriptions/$sub_name" -ErrorAction Stop
                }
            }
            return $web_app
        }
    }
    catch {
        $str = "Exception occured in while creating function app : " + $functionApp + " in subscription:" + $currsub
        Write-Error $str
        $global:exceptions += $str + $_
    }
}

function Create-Resources($currsub){
    try {
        Write-Host "Azure Subscriptions detected" -ForegroundColor Cyan 
        #$allsubs | Write-Host
        Write-Host "Deploying in subscription - " $currsub -ForegroundColor Cyan

        $rg = Create-ResourceGroup
    
        if ($null -ne $rg ) {
            # Create an Azure storage account in the resource group.
            $storageacc = Create-StorageAccount
            if ($null -ne $storageacc ) {
                # Create a serverless Powershell function app in the resource group.
                Create-FunctionApp
            }
        }
    }
    catch {
        $str = "Exception occured in while executing script : " + $functionApp + " in subscription:" + $currsub 
        Write-Error $str
        $global:exceptions += $str + $_
    }
    if ("" -ne $global:exceptions ) {
        Write-Error "Error while running script in subcription - " + $currsub 
        Store-Exceptions-In-File
        Write-Error "Deleting all the resources which were created in subscription - " + $currsub
        Revert
        return $false
    }
    else{
        Write-Host "Resource creation is successful, please refer file: " "for more details" -ForegroundColor Green
        Write-Function-Details-In-File $resourceGroup $storage $functionApp $archivePath
        return $true
    }
}

function Configure-Subscriptions($allsubs){
    if ($null -ne $allsubs) {
        foreach ($currsub in $allsubs) {
            try {
                    Write-Host $currsub
                    #Set-AzContext -Subscription $currsub
                    Write-Host "Configuring in subscription - " $currsub -ForegroundColor Green
                    Assign-Role-FunctionApp $currsub
                    $web_app = Get-AzWebApp -ResourceGroupName $resourceGroup -Name $functionApp -ErrorVariable notPresent -ErrorAction SilentlyContinue
                    $endpoint = $web_app.Id + "/functions/AddWebHookToNewStorageAccount"
                    Write-Host "Sleeping for 10 seconds, so function publishing gets complete"
                    Start-Sleep -s 10 
                    Create-Event-Subscription $event_sub_name $endpoint
                    Write-Host "Configuration is successful for subscription - " + $currsub -ForegroundColor Green
                }
            catch {
                Write-Error "Error while configuring events in subscription - $currsub"
            }
        }
    }
    else {
        Write-Error 'No Subscription is selected in the scope. Aborting Script' 
    }  
}

if (($PSVersionTable.PSVersion -ge '5.1') `
        -and (Get-Module -ListAvailable Az.Resources) `
        -and (Get-Module -ListAvailable Az.Functions) `
        -and (Get-Module -ListAvailable Az.EventGrid) `
        -and (Get-Module -ListAvailable Az.Accounts)) {
    
    Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"
    Update-AzConfig -DisplaySecretsWarning $false
    Set-Item -Path Env:\AZURE_CLIENTS_SHOW_SECRETS_WARNING -Value $false
    $ErrorActionPreference = "Stop"

    Connect-AzAccount >$null
    #get desired list of subscriptions

    $currsub = Get-Subscription-Azure-Function 
    $allsubs = Get-Subscriptions

    $IsSuccess = Create-Resources $currsub
    if($IsSuccess){
        Configure-Subscriptions $allsubs
    }
    else{
        Write-Error "Resource creation failed, skipping configuration"
    }
}
