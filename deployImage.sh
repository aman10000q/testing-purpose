#!/bin/bash
set -euo pipefail
apt update && apt install -yq tzdata jq curl

baseUrl="https://staging.devtron.info/orchestrator"

declare -A microservicesAppIds=(
  # [casbin]=1064
  # [dashboard]=1072
  [orchestrator]=1929
  # [kubelink]=1063
  # [kubewatch]=1070
  # [lens]=1071
  # [notifier]=1069
  # [imageScanner]=1067
  # [gitSensor]=1135
)

declare -A qaVmCdIds=(
  [qa-devtroncd-5]=0
  # [qa-devtroncd-4]=0
)
declare -A qaVmEnvIds=(
  [qa-devtroncd-5]=0
  [qa-devtroncd-4]=0
)
declare -A orchCmIdInVms=(
  [qa-devtroncd-5]=480
  [qa-devtroncd-4]=470
)
declare -A microserviceImages=(
  [casbin]=""
  [dashboard]=""
  [orchestrator]="asia-south1-docker.pkg.dev/devtron-non-prod/stage-registry/orchestrator:176ae883-11303-92199"
  [kubelink]=""
  [kubewatch]=""
  [lens]=""
  [notifier]=""
  [imageScanner]=""
  [gitSensor]=""
  [ciRunner]="quay.io/devtron/test:aa40b4e7-2589-91616"
  [chartSync]="asia-south1-docker.pkg.dev/devtron-non-prod/stage-registry/chart-sync:aa40b4e7-4047-91620"
)

TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6IkFQSS1UT0tFTjpzdXBlci1hZG1pbi10b2tlbiIsInZlcnNpb24iOiIxIiwiaXNzIjoiYXBpVG9rZW5Jc3N1ZXIifQ.jS0Keid81Ix4c4uzE1T-RZonPQn2WTqax_FDlYRQJ5I"

getQaCdIds() {
  local appId=$1
  local vmName=$2
  local apiEndpoint="$baseUrl/app/cd-pipeline/$appId"
  local response
  response=$(curl -s -H "Cookie: argocd.token=$TOKEN" "$apiEndpoint")
  qaVmCdIds[$vmName]=$(echo "$response" | jq --arg envName "$vmName" -r '.result.pipelines[]? | select(.environmentName == $envName) | .parentPipelineId' 2>/dev/null || echo "")
}

getQaEnvIds(){
  local envName=$1
  local apiEndPoint="$baseUrl/env"
  local response
  response=$(curl -s -H "Cookie: argocd.token=$TOKEN" "$apiEndPoint")
  envId=$(echo "$response" | jq --arg env $envName -r '.result[] | select(.environment_name == $env) | .id')
}

triggerDeployment(){
  local envIdToTrigger=$1
  echo "env id for triggering we are getting is"
  echo $envIdToTrigger
  local imageToDeploy=$2
  local apiEndpoint="$baseUrl/webhook/ext-ci/$envIdToTrigger"
  curl -s -H "Cookie: argocd.token=$TOKEN" -H "api-token: $TOKEN" -X POST "$apiEndpoint" -d "{\"dockerImage\":\"$imageToDeploy\"}"
}

waitForNewResources() {
  local appId=$1
  local environmentId=$2
  local maxRetries=5
  local sleepSeconds=5
  local apiEndPoint="$baseUrl/app/detail/resource-tree?app-id=$appId&env-id=$environmentId"

  for ((i=1; i<=maxRetries; i++)); do
    echo "Attempt $i/$maxRetries..."
    local response
    response=$(curl -s -H "Cookie: argocd.token=$TOKEN" "$apiEndPoint")
    echo "printing the response"
    echo "$response"

    local status
    status=$(echo "$response" | jq -r '
      .result.nodes[]?
      | select(.name | contains("qa-migrate"))
      | select(.kind == "Job")
      | .health.status // empty
    ')

    if [[ "$status" == "Healthy" ]]; then
      echo "Resource is Healthy!"
      return 0
    fi

    if [[ $i -eq $maxRetries ]]; then
      echo "Resource did not become Healthy after $maxRetries attempts."
      return 1
    fi

    sleep "$sleepSeconds"
  done
}


updateConfigMapImages() {
  local defaultCiImage="$1"
  local appsyncImage="$2"
  local appName="$3"
  local envName="$4"
  local resourceId="$5"
  local resourceName="$6"

  local getUrl="$baseUrl/config/data"
  local postUrl="$baseUrl/config/environment/cm"

  echo " Fetching existing ConfigMap..."
  local response
  response=$(curl -s -G "$getUrl" \
    --data-urlencode "appName=$appName" \
    --data-urlencode "envName=$envName" \
    --data-urlencode "configType=PublishedOnly" \
    --data-urlencode "resourceId=$resourceId" \
    --data-urlencode "resourceName=$resourceName" \
    --data-urlencode "resourceType=ConfigMap" \
    -H "Content-Type: application/json" \
    -H "Cookie: argocd.token=$TOKEN")

  # Extract the full configData object
  local configData
  configData=$(echo "$response" | jq '.result.configMapData.data.configData[0]')

  if [ -z "$configData" ] || [ "$configData" == "null" ]; then
    echo " Failed to fetch ConfigMap data."
    return 1
  fi

  # Update only the image fields
  local updatedData
  updatedData=$(echo "$configData" | jq \
    --arg defaultImage "$defaultCiImage" \
    --arg appSyncImage "$appsyncImage" \
    '.data.DEFAULT_CI_IMAGE = $defaultImage | .data.APP_SYNC_IMAGE = $appSyncImage'
  )

  # Extract appId and environmentId from the fetched data
  local appId environmentId
  appId=$(echo "$response" | jq '.result.configMapData.data.appId // .result.configMapData.data.configData[0].data.appId // 0')
  environmentId=$(echo "$response" | jq '.result.configMapData.data.environmentId // .result.configMapData.data.configData[0].data.environmentId // 0')

  # Construct final payload exactly matching API structure
  local payload
  payload=$(jq -n \
    --argjson configData "$updatedData" \
    --arg appId "$appId" \
    --arg environmentId "$environmentId" \
    '{
      appId: ($appId | tonumber),
      environmentId: ($environmentId | tonumber),
      configData: [$configData],
      isExpressEdit: false
    }'
  )

  echo " Updating ConfigMap with new images..."
  curl -s -X POST "$postUrl" \
    -H "Content-Type: application/json" \
    -H "Cookie: argocd.token=$TOKEN" \
    -d "$payload"

  echo " ConfigMap updated successfully!"
}


for microserviceId in "${!microservicesAppIds[@]}"; do
  for vm in "${!qaVmCdIds[@]}"; do
    getQaCdIds ${microservicesAppIds[$microserviceId]} $vm
    if [[ "${microservicesAppIds[$microserviceId]}" == "${microservicesAppIds[orchestrator]}" ]]; then
      updateConfigMapImages "${microserviceImages[ciRunner]}" "${microserviceImages[chartSync]}" "qa-orchestrator" "$vm" "${orchCmIdInVms[$vm]}" "orchestrator-cm"
    fi
    triggerDeployment ${qaVmCdIds[$vm]} ${microserviceImages[$microserviceId]}
    if [[ $microserviceId == "orchestrator" || $microserviceId == "casbin" || $microserviceId == "lens" || $microserviceId == "gitSensor" ]]; then
      getQaEnvIds $vm
      waitForNewResources "${microservicesAppIds[$microserviceId]}" $envId
    fi
  done
done
