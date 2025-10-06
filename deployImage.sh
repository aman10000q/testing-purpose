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

getQaEnvIds() {
  local appId=$1;
  local vmName=$2;
  local apiEndpoint="$baseUrl/app/cd-pipeline/$appId";
  local response;
  response=$(curl -s -H "Cookie: argocd.token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6IkFQSS1UT0tFTjpzdXBlci1hZG1pbi10b2tlbiIsInZlcnNpb24iOiIxIiwiaXNzIjoiYXBpVG9rZW5Jc3N1ZXIifQ.jS0Keid81Ix4c4uzE1T-RZonPQn2WTqax_FDlYRQJ5I" "$apiEndpoint")
  qaVmCdIds[$vmName]=$(echo "$response" | jq --arg envName "$vmName" -r '.result.pipelines[]? | select(.environmentName == $envName) | .id' 2>/dev/null || echo "")
  
}
triggerDeployment(){
  local envIdToTrigger=$1;
  local imageToDeploy=$2;
  local apiEndpoint="$baseUrl/";
  local response;
  response=$(curl -s )
}

for microserviceId in "${!microservicesAppIds[@]}"; do
  for vm in "${!qaVmCdIds[@]}"; do
    getQaEnvIds ${microservicesAppIds[$microserviceId]} $vm
    triggerDeployment ${qaVmCdIds[$vm]} ${microserviceImages[$microserviceId]}
  done
done
