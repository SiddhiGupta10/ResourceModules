$parameterObjs = Get-content -path "../../../src/data/DefaultParameterTemplate.json"
$parameterObj = $parameterObjs | ConvertFrom-Json

function Get-CustomParameterObj {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)]
        [PSCustomObject] $obj,

        [Parameter(Mandatory = $True, ValueFromPipeline = $True)]
        [PSCustomObject] $parameterObj
    )
    $ParamsToExclude = @("apiVersion", "dependsOn")
    
    if ($obj){
        $obj | Get-Member -MemberType NoteProperty | ForEach-Object {
            $tempKey = $_.Name
            $jsonRequest = @{
                "value" = $obj.$tempKey
            }
            Write-Host $tempKey
            Write-Host $obj.$tempKey
            $parameterObj.parameters | Where-Object { $tempKey -notin $ParamsToExclude } | Add-Member -Name $tempKey -MemberType NoteProperty -Value $jsonRequest -Force 
            if ($obj.$tempKey) { Get-CustomParameterObj -obj $obj.$tempKey -parameterObj $parameterObj }
            else { return $parameterObj }
        }
    }

}

function Get-CustomParameterObjSubtype {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)]
        [PSCustomObject] $obj,

        [Parameter(Mandatory = $True, ValueFromPipeline = $True)]
        [PSCustomObject] $parameterObj ,

        [Parameter(Mandatory = $True, ValueFromPipeline = $True)]
        [PSCustomObject] $subType

    )
    #$ParamsToExclude = @("apiVersion", "dependsOn")
    if ($obj) {
        $obj | Get-Member -MemberType NoteProperty | ForEach-Object {
            $tempKey = $_.Name
            #$members = $obj.$tempKey | Get-Member -MemberType NoteProperty
            $jsonRequest = @{
                $tempKey = $obj.$tempKey
            }
            
            Write-Host $jsonRequest
            #$jsonRequest | Add-Member -Name $tempKey -Value @{value=$obj.$tempKey} -MemberType NoteProperty
            #$parameterObj.parameters.$subType | Add-Member -Name $tempKey -MemberType NoteProperty -Value $jsonRequest -Force
            #$parameterObj.parameters.$subType | Add-Member -Name $tempKey -MemberType NoteProperty -Value $obj.$tempKey -Force
            # if ($obj.$tempKey) {
            #     Get-CustomParameterObjSubtype -obj $obj.$tempKey -parameterObj $parameterObj -subType $subType
            # }
            # else {
            #     $custParamObj = $parameterObj.parameters.$subType
            #     return $jsonRequest
            # }
            return $jsonRequest
        }
    }
}
function Get-SubResourceObjectType {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True, ValueFromPipeline=$True)]
        [string]$resourceType,

        [Parameter(Mandatory=$True, ValueFromPipeline=$True)]
        [string]$subType,

        [Parameter(Mandatory=$True, ValueFromPipeline=$True)]
        [string]$carmlPath
    )
    # Use the Parent Module for Building arm template.
    $modulePath = $carmlPath+$resourceType.Replace("/"+$subType,"")

    # Build Json for parsing the parameters
    az bicep build -f $modulePath/deploy.bicep

    # Getting the json file as pscustomobject
    $carmlContent = (Get-Content $modulePath/deploy.json) | ConvertFrom-Json 
    
    Write-Host $subType " : " $carmlContent.parameters.$subType.type
    return $carmlContent.parameters.$subType.type
}

function Convert-ARMToBicepParameters {
    Param(
        [parameter(mandatory)][string] $exportedArmLocation,
        [parameter(mandatory)][string] $proccessedArmLocation
    )
    Write-Host $exportedArmLocation
    Write-Host $proccessedArmLocation
    $inputJson = Get-content -Path $exportedArmLocation
    $jsonConvertInputJson = $inputJson | ConvertFrom-Json
    write-Host "Length of resources: " $jsonConvertInputJson.resources.Length

    $carmlPath = '../../../src/carml/'

    foreach ($eachResourceInputJson in $jsonConvertInputJson.resources) {

        $resourceType = $eachResourceInputJson.type
        Write-Host "-----" $resourceType "-----"

        # if length of resourceType.split > 2 there is a child resource
        if ( $resourceType.Split("/").Length -gt 2) {
            $subtypeFull = $resourceType
            $subType = $subtypeFull.Split('/')[-1]
        }
        else { 
            $subtypeFull = "" 
            ## Call to find generate parameters object
            # Call for parent resource. 
            Get-CustomParameterObj -obj $eachResourceInputJson -parameterObj $parameterObj
            Write-Host "parameter to object" $parameterObj
        }
        
        if ($subtypeFull) {
            ## Call to find sub-resource object type
            $objectType = Get-SubResourceObjectType -resourceType $resourceType  -subType $subType -carmlPath $carmlPath

            if ($objectType -eq "object") { $parameterObj.parameters | Add-Member -Name $subType -MemberType NoteProperty -Value @{value = $eachResourceInputJson } }
            elseif ($objectType -eq "array") { $parameterObj.parameters | Add-Member -Name $subType -MemberType NoteProperty -Value @{value = @($eachResourceInputJson) } }
            # Get-CustomParameterObjSubtype -obj $eachResourceInputJson -parameterObj $parameterObj -subType $subType
        }
        else { Write-Host "No sub type" }
    }
    #return $parameterObj
    #$jqJsonTemplate = "$statePath/src/storage_parameter_jq.jq"
    #$parameterToObj = ($parameterObj.parameters | ConvertTo-Json -Depth 200 | jq -r -f $jqJsonTemplate | ConvertFrom-Json)
    
    ConvertTo-Json -InputObject $parameterToObj -Depth 200 | Set-Content -Path $proccessedArmLocation
}



$tempExportPath = '../../../Infra_Apps/rakshana_subscription/cost/Microsoft.Storage_storageAccounts/westredisrak.deploy.json'
$paramExportPath = '../../../Infra_Apps/rakshana_subscription/cost/Microsoft.Storage_storageAccounts/parameters/param_storage.json'
Convert-ARMToBicepParameters -exportedArmLocation $tempExportPath -proccessedArmLocation $paramExportPath

