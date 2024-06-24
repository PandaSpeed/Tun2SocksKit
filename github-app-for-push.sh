#!/usr/bin/env bash

privateKeyFilePath="$HOME/.ssh/pandaspeed-bot.2024-05-14.private-key.pem"
app_id="897900"
private_key=$(cat $privateKeyFilePath)

# Shared content to use as template
header='{
    "alg": "RS256",
    "typ": "JWT"
}'
payload_template='{}'

build_payload() {
    jq -c \
    --arg iat_str "$(date +%s)" \
    --arg app_id "${app_id}" \
    '
        ($iat_str | tonumber) as $iat
        | .iat = $iat
        | .exp = ($iat + 300)
        | .iss = ($app_id | tonumber)
        ' <<<"${payload_template}" | tr -d '\n'
}

b64enc() { openssl enc -base64 -A | tr '+/' '-_' | tr -d '='; }
json() { jq -c . | LC_CTYPE=C tr -d '\n'; }
rs256_sign() { openssl dgst -binary -sha256 -sign <(printf '%s\n' "$1"); }

sign() {
    local algo payload sig
    algo=${1:-RS256}
    algo=${algo^^}
    payload=$(build_payload) || return
    signed_content="$(json <<<"$header" | b64enc).$(json <<<"$payload" | b64enc)"
    sig=$(printf %s "$signed_content" | rs256_sign "$private_key" | b64enc)
    printf '%s.%s\n' "${signed_content}" "${sig}"
}

token=$(sign)
echo "TOKEN: $token"


# From here we can use this token to request an Installation Token, which will be used with the Git commands later. 

installation_list_response=$(curl -s -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.github.machine-man-preview+json" \
    https://api.github.com/app/installations)
 
installation_id=$(echo $installation_list_response | jq '.[] | select(.app_id=='${app_id}')' | jq -r '.id')
 
if [ -z "$installation_id" ];
then
   >&2 echo "Unable to obtain installation ID"
   >&2 echo "$installation_list_response"
   exit 1
fi
 
# authenticate as github app and get access token
installation_token_response=$(curl -s -X POST \
        -H "Authorization: Bearer ${token}" \
        -H "Accept: application/vnd.github.machine-man-preview+json" \
        https://api.github.com/app/installations/$installation_id/access_tokens)
 
installation_token=$(echo $installation_token_response | jq -r '.token')
 
if [ -z "$installation_token" ];
then
   >&2 echo "Unable to obtain installation token"
   >&2 echo "$installation_token_response"
   exit 1
fi
 
echo $installation_token


# set the Username and Email for the GitHub App. These are complied with the information from the GitHub App name and ID.

githubToken="$installation_token"
githubUsername="pandaspeed-bot"
githubId="$app_id"
githubEmail="${githubId}+${githubUsername}[bot]@users.noreply.github.com"
 
git remote set-url origin $(git config remote.origin.url | sed "s/github.com/${githubUsername}:${githubToken}@github.com/g")
git config --local user.name "${githubUsername}"
git config --local user.email "${githubEmail}"
