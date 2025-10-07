#!/bin/bash
set -euo pipefail
apt update && apt install -yq tzdata jq curl

baseUrl="https://staging.devtron.info/orchestrator"

declare -A microservicesAppIds=(
  [casbin]=1064
  [dashboard]=1072
  [orchestrator]=1929
  [kubelink]=1063
  [kubewatch]=1070
  [lens]=1071
  [notifier]=1069
  [imageScanner]=1067
  [gitSensor]=1135
)

declare -A qaVmCdIds=(
  [qa-devtroncd-5]=0
  [qa-devtroncd-4]=0
)
declare -A qaVmEnvIds=(
[qa-devtroncd-5]=0
[qa-devtroncd-4]=0
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


for microserviceId in "${!microservicesAppIds[@]}"; do
  for vm in "${!qaVmCdIds[@]}"; do
    getQaCdIds ${microservicesAppIds[$microserviceId]} $vm
    triggerDeployment ${qaVmCdIds[$vm]} ${microserviceImages[$microserviceId]}
    getQaEnvIds $vm
    waitForNewResources
  done
done
