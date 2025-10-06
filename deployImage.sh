#!/bin/bash
baseUrl="https://staging.devtron.info/orchestrator"
set -e 
declare -A microservicesAppIds=(
[casbin]=
[dashboard]=
[orchestrator]=
[kubelink]=
[kubewatch]=
[lens]=
[notifier]=
[imageScanner]=
[gitSensor]=
)

declare -A qaVmCdIds=([qa-devtroncd-5]=0 [qa-devtroncd-4]=0)

getQaEnvIds(){
  local microserviceName=$1;
  local apiEndpoint="$baseUrl/app/cd-pipeline/$microserviceName";
  local response;
  
  for vm in "${!qaVmCdIds[@]}"; do
    response=$(curl -s -H "Cookie: argocd.token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6IkFQSS1UT0tFTjpzdXBlci1hZG1pbi10b2tlbiIsInZlcnNpb24iOiIxIiwiaXNzIjoiYXBpVG9rZW5Jc3N1ZXIifQ.jS0Keid81Ix4c4uzE1T-RZonPQn2WTqax_FDlYRQJ5I" "$apiEndpoint")
    qaVmCdIds[$vm]=$(jq --arg envName $vm -r '.result.pipelines[] | select(.environmentName == $envName) | .id');
    
}

for microservice in "${!microservicesAppIds[@]}"; do
  getQaEndIds "$(microServiceAppIds[$microService])"
  echo "printing the env ids for $microservice"
  echo "$(qaVmCdIds[qa-devtroncd-5])"
  echo "$(qaVmCdIds[qa-devtroncd-4])"
done
