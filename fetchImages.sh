
#!/bin/bash
set -e
source sourcecode/slackMessage.sh

apt update && apt install -yq tzdata jq  curl

# -------------------------
# CONFIGURATION
# -------------------------

BASE_URL="https://staging.devtron.info/orchestrator"
# Put your argocd token here
ARGOCD_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6IkFQSS1UT0tFTjpzdXBlci1hZG1pbi10by1hZGQtY2x1c3RlcnMiLCJ2ZXJzaW9uIjoiMSIsImlzcyI6ImFwaVRva2VuSXNzdWVyIn0.A9v15OZa25EcilUOjR36M1leInPvX46ShxFSQPrqpWI"

# Headers for curl
COMMON_HEADERS=(-H "accept: */*" -H "accept-language: en-US,en;q=0.9" -H "Cookie: argocd.token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6IkFQSS1UT0tFTjpzdXBlci1hZG1pbi10b2tlbiIsInZlcnNpb24iOiIxIiwiaXNzIjoiYXBpVG9rZW5Jc3N1ZXIifQ.jS0Keid81Ix4c4uzE1T-RZonPQn2WTqax_FDlYRQJ5I")

# Microservices and their App IDs
declare -A appIds=(
  [dashboard]=1945
  [orchestrator]=1944
  [kubelink]=1937
  [imageScanner]=1935
  [notifier]=1936
  [kubewatch]=1940
  [lens]=1943
  [casbin]=1934
  [chartSync]=3180
  [gitSensor]=1941
  [ciRunner]=2265
)

# User-provided branches for each microservice
declare -A userBranches=(
  [dashboard]="$dashboard"
  [orchestrator]="$orchestrator"
  [kubelink]="$kubelink"
  [imageScanner]="$imageScanner"
  [notifier]="$notifier"
  [kubewatch]="$kubewatch"
  [lens]="$lens"
  [casbin]="$casbin"
  [chartSync]="$chartSync"
  [gitSensor]="$gitSensor"
  [ciRunner]="$ciRunner"
)

# Associative array to store final images
declare -A latestImages

# -------------------------
# FUNCTIONS
# -------------------------

# Fetch CD pipeline ID based on branch
# Fetch CD pipeline ID based on branch
# Fetch CD pipeline ID based on branch
get_cd_id_for_pipeline() {
  local appId=$1
  local branch=$2
  
  echo "Fetching CD pipeline for AppID=$appId (Branch=$branch)..."
  
  local url="$BASE_URL/app/cd-pipeline/$appId"
  echo "URL: $url"
  
  local response
  response=$(curl -s -H "Cookie: argocd.token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6IkFQSS1UT0tFTjpzdXBlci1hZG1pbi10b2tlbiIsInZlcnNpb24iOiIxIiwiaXNzIjoiYXBpVG9rZW5Jc3N1ZXIifQ.jS0Keid81Ix4c4uzE1T-RZonPQn2WTqax_FDlYRQJ5I" "$url")
  
  echo "Response received (first 200 chars): ${response:0:200}"
  
  cdId=$(echo "$response" | jq -r --arg branch "$branch" '
    .result.pipelines[] 
    | select(.environmentName == $branch)
    | .id
  ' | head -1)
  
  if [[ -z "$cdId" || "$cdId" == "null" ]]; then
   send_slack "Not able to find cdId for app $appId and envName $branch" $thread_id
   exit 1
  fi
}

# Fetch latest deployed image from a CD pipeline
get_latest_image() {
  local cdId=$1
  
  
  echo "Fetching latest deployed image for CD ID=$cdId..."
  
  local currentUrl="$BASE_URL/app/cd-pipeline/$cdId/material?offset=0&size=20&stage=DEPLOY"
  echo "URL: $currentUrl"
  
  local response
  response=$(curl -s -H "Cookie: argocd.token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6IkFQSS1UT0tFTjpzdXBlci1hZG1pbi10b2tlbiIsInZlcnNpb24iOiIxIiwiaXNzIjoiYXBpVG9rZW5Jc3N1ZXIifQ.jS0Keid81Ix4c4uzE1T-RZonPQn2WTqax_FDlYRQJ5I" "$currentUrl")
  
  image=$(echo "$response" | jq -r '
    if .result.ci_artifacts and (.result.ci_artifacts | length > 0) then
      .result.ci_artifacts[0].image
    else
      empty
    end
  ')
  
  if [[ -z "$image" ]]; then
    send_slack " No latest image found for CD ID $cdId" $threadId
    exit 1 
  fi
}

# -------------------------
# MAIN LOOP
# -------------------------
fetchImages() {
  for svc in "${!appIds[@]}"; do
  appId=${appIds[$svc]}
  branch=${userBranches[$svc]}
  
  echo "------------------------------------------------"
  echo "Processing microservice: $svc"
  echo "App ID: $appId | Branch: $branch"
  
  get_cd_id_for_pipeline "$appId" "$branch"
  get_latest_image "$cdId"
  # if ! get_latest_image "$cdId" image; then
  #   continue
  # fi
  
   latestImages[$svc]=$image
done

# -------------------------
# PRINT RESULTS
# -------------------------

echo
echo "================ Latest Images ================"
for svc in "${!latestImages[@]}"; do
  echo "$svc => ${latestImages[$svc]}"
done
send_slack "Images of all microservices has been fetched successfully " $thread_id
}

