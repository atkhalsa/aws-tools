#!/bin/bash

# This script generates AWS Programmatic Access credentials from a user authenticated via SSO
# Before using, make sure that the AWS SSO is configured in your CLI: `aws configure sso`

GREEN='\033[0;32m'
NC='\033[0m' # No Color
YELLOW='\033[1;33m'

profile=${1:-shf-dev}
region=${2:-us-west-2}
sso_session_name=${3:-shf-sso}
JSON_BASEPATH="${HOME}/.aws/sso/cache"
JSON_BASEPATH_CLI="${HOME}/.aws/cli/cache"
get_creds=false

sso_configured(){
    profileSearchText="profile $profile"

    if [ "$profile" = "default" ]; then 
        profileSearchText="default"
    fi

    if  grep -Fxq "[$profileSearchText]" ~/.aws/config && grep -Fxq "[sso-session ${sso_session_name}]" ~/.aws/config; then
        echo 
    else
        echo 
        echo -e "profile ${YELLOW}$profile${NC} or sso-session ${YELLOW}${sso_session_name}${NC} is not configured, configure it first using"
        echo -e "${YELLOW}aws configure sso${NC}"
        echo 
        echo "Some of the values to use are..."
        echo SSO session name: ${sso_session_name} "# name you want to save sso session in config with"
        echo SSO Start URL: https://[company].awsapps.com/start  "# [company] is the name of your company"
        echo SSO Region: $region
        echo SSO registration scopes: sso:account:access
        echo CLI profile name: $profile
        aws configure sso
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
  
  echo "Welcome ${GREEN}$username${NC}, you are logged in with role ${GREEN}$role_arn_name${NC}"

   # find the latest CLI JSON file
   json_file=$(ls -tr "${JSON_BASEPATH}" | tail -n1)
   credentials=$(cat ${JSON_BASEPATH}/${json_file})
}
sso_configured
read_credentials

if [ $? -ne 0 ]; then
  echo you need to login
  get_creds=true
  aws sso login --sso-session ${sso_session_name}

  if [ $? -ne 0 ]; then
    exit 1
  fi

  read_credentials
fi

sso_token_expiry=$(echo $credentials | jq -r '.expiresAt')
sso_token_expiry_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$sso_token_expiry" +%s)
now=$(TZ=UTC date +%s)

# check if token is expired then login again
if [ $sso_token_expiry_epoch -lt $now ]; then
  get_creds=true
  echo "Token expired @ ${sso_token_expiry}, logging in again"
  aws sso login --sso-session ${sso_session_name}
  read_credentials
fi

sso_access_token=$(echo $credentials | jq -r '.accessToken')
sso_account_id=$(aws configure get sso_account_id --profile $profile)
sso_role_name=$(aws configure get sso_role_name --profile $profile)

# check if token expired based on cache file or if get_creds is true
json_file=$(aws configure get cache_file --profile $profile)
credentials=$(cat ${JSON_BASEPATH_CLI}/${json_file})
role_token_expiry=$(echo $credentials | jq -r '.Credentials.Expiration')
role_token_expiry_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$role_token_expiry" +%s)

if [ $role_token_expiry_epoch -lt $now ] || [ $get_creds = true ]; then
  echo "Role token expired @ ${role_token_expiry} or new SSO token, getting new role credentials"
  role_creds=$(aws sso get-role-credentials --role-name $sso_role_name --account-id $sso_account_id --access-token $sso_access_token)
   # find the latest CLI JSON file
    json_file=$(ls -tr "${JSON_BASEPATH_CLI}" | tail -n1)
    aws configure set --profile "$profile" cache_file "$json_file"

    expiration=$(echo $role_creds | jq -r '.roleCredentials.expiration')
    access_key_id=$(echo $role_creds | jq -r '.roleCredentials.accessKeyId')
    secret_access_key=$(echo $role_creds | jq -r '.roleCredentials.secretAccessKey')
    session_token=$(echo $role_creds | jq -r '.roleCredentials.sessionToken')
else
    access_key_id=$(echo $credentials | jq -r '.Credentials.AccessKeyId')
    secret_access_key=$(echo $credentials | jq -r '.Credentials.SecretAccessKey')
    session_token=$(echo $credentials | jq -r '.Credentials.SessionToken')
fi 



aws configure set --profile "$profile" aws_access_key_id "$access_key_id"
aws configure set --profile "$profile" aws_secret_access_key "$secret_access_key"
aws configure set --profile "$profile" aws_session_token "$session_token"

