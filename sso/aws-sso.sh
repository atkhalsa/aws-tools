#!/bin/bash

# This script generates AWS Programmatic Access credentials from a user authenticated via SSO
# Before using, make sure that the AWS SSO is configured in your CLI: `aws configure sso`

GREEN='\033[0;32m'
NC='\033[0m' # No Color
YELLOW='\033[1;33m'
RED='\033[0;31m'

profile=${1:-shf-dev}
region=${2:-us-west-2}
JSON_BASEPATH="${HOME}/.aws/cli/cache"

sso_configured(){
    profileSearchText="profile $profile"

    if [ "$profile" = "default" ]; then 
        profileSearchText="default"
    fi

    if  grep -Fxq "[$profileSearchText]" ~/.aws/config; then
        echo 
    else
        echo 
        echo -e "profile ${YELLOW}$profile${NC} is not configured, configure it first using"
        echo -e "${YELLOW}aws configure sso --profile $profile${NC}"
        echo 
        echo "Some of the values to use are..."
        echo sso start url: https://[company].awsapps.com/start "# replace [company] with your company name"
        echo sso region: $region
        aws configure sso --profile $profile
        exit 1;
    fi
}

read_credentials() {

  # check if login still works, if not then need to be logged in again 
 current_identity=$(aws sts get-caller-identity --profile $profile)
  if [ -z "$current_identity" ]; then
   return 1
  fi
  
  username=$(echo $current_identity | jq -r '.Arn' | cut -d "/" -f3 )
  role_arn_name=$(echo $current_identity | jq -r '.Arn' | cut -d "/" -f2 )
  account_number=$(echo $current_identity | jq -r '.Arn' | cut -d ":" -f5 )
  
  echo -e "Welcome ${GREEN}$username${NC}, you are logged in with role ${GREEN}$role_arn_name${NC}"

   # find the latest CLI JSON file
   json_file=$(ls -tr "${JSON_BASEPATH}" | tail -n1)
   credentials=$(cat ${JSON_BASEPATH}/${json_file})
}

sso-check() {
  local PROFILE=$profile
  
  # 1. Try to get the sso-session name (Modern Config)
  local SESSION=$(aws configure get sso_session --profile "$PROFILE")
  
  local CACHE_FILE=""
  
  if [[ -n "$SESSION" ]]; then
    # Calculate SHA1 of the session name
    # Uses openssl to be cross-platform (works on both Mac and Linux)
    local CHECKSUM=$(echo -n "$SESSION" | openssl sha1 | awk '{print $NF}')
    CACHE_FILE="$HOME/.aws/sso/cache/${CHECKSUM}.json"
  else
    # Fallback: Try to find by Start URL (Legacy Config)
    local URL=$(aws configure get sso_start_url --profile "$PROFILE")
    if [[ -z "$URL" ]]; then
        echo "Error: Profile '$PROFILE' has no sso_session or sso_start_url configured."
        return 1
    fi
    # Grep for the URL since legacy filenames are harder to predict script-wise
    CACHE_FILE=$(grep -l "$URL" ~/.aws/sso/cache/*.json 2>/dev/null | head -n 1)
  fi

  if [[ ! -f "$CACHE_FILE" ]]; then
    echo "No active login found (Cache file missing)."
    return 1
  fi

  # 3. Check Expiration using jq
  # -e makes jq exit with status 0 if true (valid), 1 if false (expired)
  cat "$CACHE_FILE" | jq -e '.expiresAt | fromdate > now' > /dev/null
  
  # Capture the result
  local STATUS=$?
  
  # Use jq to convert ISO 8601 timestamp directly to epoch time
  expiresAtEpoch=$(cat "$CACHE_FILE" | jq -r '.expiresAt | fromdate')
  # Convert epoch time to local timezone for display
  expiresAtLocal=$(date -r "$expiresAtEpoch" +"%Y-%m-%d %H:%M:%S %Z")

  if [ $STATUS -eq 0 ]; then
    echo -e "✅ Valid till: ${GREEN}$expiresAtLocal${NC}"
    return 0
  else
    echo -e "❌ Expired at: ${RED}$expiresAtLocal${NC}, now: $(date +"%Y-%m-%d %H:%M:%S %Z")\n"
    return 1
  fi

}

sso_configured

# First, check if the token is valid and not expired.
sso-check
# If the check fails, initiate the login process.
if [ $? -ne 0 ]; then
  echo "you need to login"
  aws sso login --profile "$profile"
  if [ $? -ne 0 ]; then
    echo "AWS SSO login failed."
    exit 1
  fi
fi

# After ensuring the session is active, read the credentials.
read_credentials
if [ $? -ne 0 ]; then
  echo "Failed to read credentials even after a successful login."
  exit 1
fi

access_key_id=$(echo $credentials | jq -r '.Credentials.AccessKeyId')
secret_access_key=$(echo $credentials | jq -r '.Credentials.SecretAccessKey')
session_token=$(echo $credentials | jq -r '.Credentials.SessionToken')

aws configure set --profile "$profile" aws_access_key_id "$access_key_id"
aws configure set --profile "$profile" aws_secret_access_key "$secret_access_key"
aws configure set --profile "$profile" aws_session_token "$session_token"
