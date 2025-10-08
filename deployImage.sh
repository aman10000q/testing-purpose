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
declare -A orchCmIdInVms(
[qa-devtroncd-5]=480
[qa-devtroncd-4]=470
)
declare -A microserviceImages=(
  [casbin]=""
  [dashboard]=""
  [orchestrator]=""
  [kubelink]=""
  [kubewatch]=""
  [lens]=""
  [notifier]=""
  [imageScanner]=""
  [gitSensor]=""
  [ciRunner]="quay.io/devtron/test:aa40b4e7-2589-91616"
  [chartSync]="asia-south1-docker.pkg.dev/devtron-non-prod/stage-registry/chart-sync:aa40b4e7-4047-91620"
)

getQaCdIds() {
  local appId=$1;
  local vmName=$2;
  local apiEndpoint="$baseUrl/app/cd-pipeline/$appId";
  local response;
  response=$(curl -s -H "Cookie: argocd.token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6IkFQSS1UT0tFTjpzdXBlci1hZG1pbi10b2tlbiIsInZlcnNpb24iOiIxIiwiaXNzIjoiYXBpVG9rZW5Jc3N1ZXIifQ.jS0Keid81Ix4c4uzE1T-RZonPQn2WTqax_FDlYRQJ5I" "$apiEndpoint")
  qaVmCdIds[$vmName]=$(echo "$response" | jq --arg envName "$vmName" -r '.result.pipelines[]? | select(.environmentName == $envName) | .id' 2>/dev/null || echo "")
}
getQaEnvIds(){
local envName=$1;
local apiEndPoint="$baseUrl/env"
local response;
response=$(curl -s -H "Cookie: argocd.token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6IkFQSS1UT0tFTjpzdXBlci1hZG1pbi10b2tlbiIsInZlcnNpb24iOiIxIiwiaXNzIjoiYXBpVG9rZW5Jc3N1ZXIifQ.jS0Keid81Ix4c4uzE1T-RZonPQn2WTqax_FDlYRQJ5I" "$apiEndpoint");
envId=$(echo $response | jq --arg env $envName -r '.result[] | select(.environment_name == envName) | .id')
}
triggerDeployment(){
  local envIdToTrigger=$1;
  local imageToDeploy=$2;
  local apiEndpoint="$baseUrl/webhook/ext-ci/$envIdToTrigger";
  local response;
  response=$(curl -s -H "Cookie: argocd.token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6IkFQSS1UT0tFTjpzdXBlci1hZG1pbi10b2tlbiIsInZlcnNpb24iOiIxIiwiaXNzIjoiYXBpVG9rZW5Jc3N1ZXIifQ.jS0Keid81Ix4c4uzE1T-RZonPQn2WTqax_FDlYRQJ5I" -X POST "$apiEndpoint" -d "{\"dockerImage\":\"$imageToDeploy\"}")
}
waitForNewResources() {
  local appId=$1
  local environmentId=$2
  local maxRetries=5
  local sleepSeconds=5
  local apiEndPoint="$baseUrl/app/detail/resource-tree?app-id=$appId&env-id=$environmentId"
  for ((i=1; i<=maxRetries; i++)); do
    echo "Attempt $i/$maxRetries..."
    response=$(curl -s -H "Cookie: argocd.token=YOUR_TOKEN" "$apiEndPoint")
    status=$(echo "$response" | jq -r '
      .result.resources[]
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
  local resourceName="$5"
  local resourceId="$6"

  local getUrl="https://staging.devtron.info/orchestrator/config/data"
  local postUrl="https://staging.devtron.info/orchestrator/config/environment/cm"

  echo "🔹 Fetching existing ConfigMap..."
  local response
  response=$(curl -s -G "$getUrl" \
    --data-urlencode "appName=$appName" \
    --data-urlencode "envName=$envName" \
    --data-urlencode "configType=PublishedOnly" \
    --data-urlencode "resourceId=$resourceId" \
    --data-urlencode "resourceName=$resourceName" \
    --data-urlencode "resourceType=ConfigMap" \
    -H "Content-Type: application/json" \
    -H "Cookie: argocd.token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6IkFQSS1UT0tFTjpzdXBlci1hZG1pbi10b2tlbiIsInZlcnNpb24iOiIxIiwiaXNzIjoiYXBpVG9rZW5Jc3N1ZXIifQ.jS0Keid81Ix4c4uzE1T-RZonPQn2WTqax_FDlYRQJ5I")

  # Extract the configData object
  local configData
  configData=$(echo "$response" | jq '.result.configMapData.data.configData[0]')

  if [ -z "$configData" ] || [ "$configData" == "null" ]; then
    echo "❌ Failed to fetch ConfigMap data."
    return 1
  fi

  # Update the image fields
  local updatedData
  updatedData=$(echo "$configData" | jq \
    --arg defaultImage "$defaultCiImage" \
    --arg appSyncImage "$appsyncImage" \
    '.data.DEFAULT_CI_IMAGE = $defaultImage | .data.APP_SYNC_IMAGE = $appSyncImage'
  )

  # Extract appId and environmentId for payload
  local appId
  local environmentId
  appId=$(echo "$response" | jq '.result.configMapData.data.configData[0].data.appId // .result.configMapData.data.appId // 0')
  environmentId=$(echo "$response" | jq '.result.configMapData.data.configData[0].data.environmentId // .result.configMapData.data.environmentId // 0')

  # Construct full payload
  local payload
  payload=$(jq -n \
    --argjson configData "[$updatedData]" \
    --arg isExpressEdit "false" \
    '{
      configData: $configData,
      isExpressEdit: ($isExpressEdit | test("true"))
    }'
  )

  echo "🔹 Updating ConfigMap with new images..."
  curl -s -X POST "$postUrl" \
    -H "Content-Type: application/json" \
    -H "Cookie: argocd.token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6IkFQSS1UT0tFTjpzdXBlci1hZG1pbi10b2tlbiIsInZlcnNpb24iOiIxIiwiaXNzIjoiYXBpVG9rZW5Jc3N1ZXIifQ.jS0Keid81Ix4c4uzE1T-RZonPQn2WTqax_FDlYRQJ5I" \
    -d "$payload"

  echo "✅ ConfigMap updated successfully!"
}




for microserviceId in "${!microservicesAppIds[@]}"; do
  for vm in "${!qaVmCdIds[@]}"; do
    getQaCdIds ${microservicesAppIds[$microserviceId]} $vm
    if [[ "${microservicesAppIds[microserviceId]}" == "${microservicesAppIds[orchestrator]}" ]]; then
      updateConfigMapImages "${microserviceImages[ciRunner]}" "${microserviceImages[chartSync]}" "qa-orchestrator" "$vm" "${orchCmIdInVms[$vm]}" "orchestrator-cm"
    fi
    triggerDeployment ${qaVmCdIds[$vm]} ${microserviceImages[$microserviceId]}
    if [[ $microserviceId == "${microservicesAppIds[orchestrator]}" -o $microserviceId == "${microservicesAppIds[casbib]}" -o $microserviceId == "${microservicesAppIds[lens]}" $microserviceId == "${microservicesAppIds[gitSensor]}" ]]; then
       getQaEnvIds $vm
       waitForNewResources "${microservicesAppIds[microserviceId]}" $envId
    fi
  done
done
