# SSO

This folder has 2 scripts to help with AWS SSO login.

These script can be aliased like `aws-sso` to make it easier to use.

These scripts after login with aws sso, update session token in `~/.aws/credentials` file, to help developers with aws sdk.

## aws-sso.sh
This script uses cli profiles `--profile {profile name}`

### Usage
```bash
./aws-sso.sh {profile name}
```

## aws-sso-role.sh
This script uses sso session name `--profile {profile name}` and `--session-name {session name}`

### Usage
```bash
./aws-sso-role.sh {profile name} {region} {session name}
```