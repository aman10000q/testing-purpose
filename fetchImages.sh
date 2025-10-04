#!/bin/bash
set -e

# -------------------------
# CONFIGURATION
# -------------------------

BASE_URL="https://staging.devtron.info/orchestrator"
# Put your argocd token here
ARGOCD_TOKEN="your_token_here"

# Headers for curl
COMMON_HEADERS=(-H "accept: */*" -H "accept-language: en-US,en;q=0.9" -b "argocd.token=$ARGOCD_TOKEN" \
  -H "user-agent: bash-script")

# Microservices and their App IDs
declare -A appIds=(
  [dashboard]=1930
  [orchestrator]=1931
  [kubelink]=1932
  [imageScanner]=1933
  [notifier]=1934
  [kubewatch]=1935
  [lens]=1936
  [casbin]=1937
  [chartSync]=1938
  [gitSensor]=1939
)

# User-provided branches for each microservice
declare -A userBranches=(
  [dashboard]="develop"
  [orchestrator]="main"
  [kubelink]="devtroncd5"
  [imageScanner]="develop"
  [notifier]="devtroncd6"
  [kubewatch]="develop"
  [lens]="main"
  [casbin]="develop"
  [chartSync]="main"
  [gitSensor]="develop"
)

# Associative array to store final images
declare -A latestImages

# -------------------------
# FUNCTIONS
# -------------------------

# Fetch CD pipeline ID based on branch
get_cd_id_for_pipeline() {
  local appId=$1
  local branch=$2

  echo "Fetching CD pipeline for AppID=$appId (Branch=$branch)..."

  local response
  response=$(curl -s "${COMMON_HEADERS[@]}" "$BASE_URL/app/app-wf/$appId")

  local cdId
  cdId=$(echo "$response" | jq -r --arg branch "$branch" '
    .result[]?.tree[]? 
    | select(.type=="CD_PIPELINE" and .branchName==$branch)
    | .componentId
  ' | head -1)

  if [[ -z "$cdId" || "$cdId" == "null" ]]; then
    echo "⚠️ No CD pipeline found for branch $branch in app $appId"
    return 1
  fi

  echo "✅ Found CD ID: $cdId"
  echo "$cdId"
}

# Fetch latest deployed image from a CD pipeline
get_latest_image() {
  local cdId=$1

  echo "Fetching latest deployed image for CD ID=$cdId..."

  local response
  response=$(curl -s "${COMMON_HEADERS[@]}" \
    "$BASE_URL/app/cd-pipeline/$cdId/material?offset=0&size=20&stage=DEPLOY")

  local image
  image=$(echo "$response" | jq -r '.result[]? | select(.latest==true) | .image' | head -1)

  if [[ -z "$image" || "$image" == "null" ]]; then
    echo "⚠️ No latest image found for CD ID $cdId"
    return 1
  fi

  echo "✅ Latest image: $image"
  echo "$image"
}

# -------------------------
# MAIN LOOP
# -------------------------

for svc in "${!appIds[@]}"; do
  appId=${appIds[$svc]}
  branch=${userBranches[$svc]}

  echo "------------------------------------------------"
  echo "Processing microservice: $svc"
  echo "App ID: $appId | Branch: $branch"

  cdId=$(get_cd_id_for_pipeline "$appId" "$branch") || continue
  image=$(get_latest_image "$cdId") || continue

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
