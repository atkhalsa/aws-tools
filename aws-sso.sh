#!/bin/bash

# This script generates AWS Programmatic Access credentials from a user authenticated via SSO
# Before using, make sure that the AWS SSO is configured in your CLI: `aws configure sso`

GREEN='\033[0;32m'
NC='\033[0m' # No Color
YELLOW='\033[1;33m'

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
        echo sso start url: https://superhifi.awsapps.com/start
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
sso_configured
read_credentials

if [ $? -ne 0 ]; then
  echo you need to login
  aws sso login --profile "$profile"

  if [ $? -ne 0 ]; then
    exit 1
  fi

  read_credentials
fi

access_key_id=$(echo $credentials | jq -r '.Credentials.AccessKeyId')
secret_access_key=$(echo $credentials | jq -r '.Credentials.SecretAccessKey')
session_token=$(echo $credentials | jq -r '.Credentials.SessionToken')

aws configure set --profile "$profile" aws_access_key_id "$access_key_id"
aws configure set --profile "$profile" aws_secret_access_key "$secret_access_key"
aws configure set --profile "$profile" aws_session_token "$session_token"
