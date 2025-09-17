Function Connect-M365Doc(){
    <#
    .SYNOPSIS
        Acquire a token using MSAL.NET library.
    .DESCRIPTION
        This command will acquire OAuth tokens which are required to document your environment.
        Supports Azure Commercial, Azure Government, and GCC High environments.
    .EXAMPLE Interactive
        Connect-M365Doc
        Displays authentication prompt and allows you to sign in. 

    .EXAMPLE Interactive with Azure Government
        Connect-M365Doc -Cloud Government
        Displays authentication prompt for Azure Government environment.

    .EXAMPLE Interactive with GCC High
        Connect-M365Doc -Cloud GCCHigh
        Displays authentication prompt for GCC High environment.

    .EXAMPLE CustomToken
        Connect-M365Doc -token $token

        You can pass a token you have aquired seperately via Get-MsalToken. You have to make sure, that this token has all required scopes included.
    .EXAMPLE PublicClient-Silent
        Connect-M365Doc -ClientId '00000000-0000-0000-0000-000000000000' -ClientSecret (ConvertTo-SecureString 'SuperSecretString' -AsPlainText -Force) -TenantId '00000000-0000-0000-0000-000000000000'
        
        Get token based on the submitted information. You can creat the app registration in your tenant by using the New-DocumentationAppRegistration command.
    .EXAMPLE PublicClient-Silent with Azure Government
        Connect-M365Doc -ClientId '00000000-0000-0000-0000-000000000000' -ClientSecret (ConvertTo-SecureString 'SuperSecretString' -AsPlainText -Force) -TenantId '00000000-0000-0000-0000-000000000000' -Cloud Government
        
        Get token for Azure Government environment using app registration.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    param(
        [parameter(Mandatory=$true, ParameterSetName='CustomToken')]
        [object]$token,
        [parameter(Mandatory=$true, ParameterSetName='PublicClient-Silent')]
        [guid]$ClientID,
        [parameter(Mandatory=$true, ParameterSetName='PublicClient-Silent')]
        [Security.SecureString]$ClientSecret,
        [parameter(Mandatory=$true, ParameterSetName='PublicClient-Silent')]
        [guid]$TenantId,
        [parameter(Mandatory=$false, ParameterSetName='Interactive')]
        [parameter(Mandatory=$false, ParameterSetName='PublicClient-Silent')]
        [switch]$NeverRefreshToken,
        [parameter(Mandatory=$false, ParameterSetName='Interactive')]
        [switch]$Force,
        [parameter(Mandatory=$false, ParameterSetName='Interactive')]
        [parameter(Mandatory=$false, ParameterSetName='PublicClient-Silent')]
        [ValidateSet('Commercial', 'Government', 'GCCHigh')]
        [string]$Cloud = 'Commercial'
    )
    
    # Define cloud-specific endpoints
    $cloudEndpoints = @{
        'Commercial' = @{
            Authority = 'https://login.microsoftonline.com/'
            GraphEndpoint = 'https://graph.microsoft.com/'
        }
        'Government' = @{
            Authority = 'https://login.microsoftonline.us/'
            GraphEndpoint = 'https://graph.microsoft.us/'
        }
    }
    
    # Get the appropriate cloud endpoints
    $selectedCloud = $cloudEndpoints[$Cloud]
    if (-not $selectedCloud) {
        Write-Error "Invalid cloud environment specified: $Cloud. Valid options are: Commercial, Government"
        return
    }
    
    Write-Verbose "Connecting to $Cloud environment using authority: $($selectedCloud.Authority)"
    
    # Store cloud endpoints globally for use by other functions
    $script:CloudEndpoints = $selectedCloud
    
    switch -Wildcard ($PSCmdlet.ParameterSetName) {
        "CustomToken" {
            # Verify token
            if ($token.ExpiresOn.LocalDateTime -le $(Get-Date)) {
                Write-Error "Token expired, please pass a valid and not expired token."
            } elseif($null -eq $token){
                Write-Error "No Token passed as token parameter, please pass a valid and not expired token."
            } else {
                $script:token = $token
            }
            Write-Verbose "Custom Token expires: $($script:token.ExpiresOn.LocalDateTime)"
            break
        }
        "PublicClient-Silent" {
           # Connect to Microsoft Intune PowerShell App
            $script:tokenRequest = @{
                ClientId = $ClientId
                RedirectUri = "msal37f82fa9-674e-4cae-9286-4b21eb9a6389://auth"
                TenantId = $TenantId
                ClientSecret = $ClientSecret
                Authority = $selectedCloud.Authority + $TenantId
                ForceRefresh = $True # We could be pulling a token from the MSAL Cache, ForceRefresh to ensure it's new and has the longest timeline.
            }
            if($NeverRefreshToken) { $script:tokenRequest.ForceRefresh = $False}
            
            $script:token = Get-MsalToken @script:tokenRequest
            
            # Verify token
            if (-not ($script:token -and $script:token.ExpiresOn.LocalDateTime -ge $(Get-Date))) {
                Write-Error "Connection failed."
            }
            Write-Verbose "PublicClient-Silent Token expires: $($script:token.ExpiresOn.LocalDateTime)"
            break
        }
       "Interactive" {
            # Connect to Microsoft Intune PowerShell App
            $script:tokenRequest = @{
                ClientId    = "37f82fa9-674e-4cae-9286-4b21eb9a6389"
                RedirectUri = "http://localhost"
                Authority   = $selectedCloud.Authority + "common"
                ForceRefresh = $True # We could be pulling a token from the MSAL Cache, ForceRefresh to ensure it's new and has the longest timeline.
            }

            if($NeverRefreshToken) { $script:tokenRequest.ForceRefresh = $False}

            # Verify token
            if (-not ($script:token -and $script:token.ExpiresOn.LocalDateTime -ge $(Get-Date))) {
                $script:token = Get-MsalToken @script:tokenRequest
            } else {
                if($Force){
                    Write-Information "Force reconnection"
                    $script:token = Get-MsalToken @script:tokenRequest
                } else {
                    Write-Information "Already connected."
                }
            }
            Write-Verbose "Interactive Token expires: $($script:token.ExpiresOn.LocalDateTime)"
            break
       }
   }
   
   # Display success message with cloud environment
   Write-Information "Successfully connected to $Cloud environment"
}