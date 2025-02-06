#!/bin/sh

nx_conf=/etc/nginx/nginx.conf

AWS_IAM_ADDR="http://169.254.169.254"
AWS_IAM_TOKEN_ENDPOINT="$AWS_IAM_ADDR/latest/api/token"
AWS_IAM_METADATA_ENDPOINT="$AWS_IAM_ADDR/latest/dynamic/instance-identity/document"
AWS_FOLDER='/root/.aws'

header_config() {
    mkdir -p ${AWS_FOLDER}
    echo "[default]" > /root/.aws/config
}
region_config() {
    echo "region = $@" >> /root/.aws/config
}

test_config() {
    grep -qrni $@ ${AWS_FOLDER} 2>/dev/null
}

fix_perm() {
    chmod 600 -R ${AWS_FOLDER}
}

# test if region is mounted as secret
if test_config region; then
    echo "region found in ~/.aws mounted as secret"
# configure regions if variable specified at run time
elif [[ "$REGION" != "" ]]; then
    header_config
    region_config $REGION
    fix_perm
# check if the region can be pulled from AWS IAM
else
    # get token for IMDSv2
    echo "Get aws metadata token"
    META_API_TOKEN=$(curl -sS -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" "$AWS_IAM_TOKEN_ENDPOINT")

    echo "Query aws metadata endpoint for region"
    REGION=$(curl -sS -H "X-aws-ec2-metadata-token: $META_API_TOKEN" "$AWS_IAM_METADATA_ENDPOINT" | jq -r .region)
    if [[ "x${REGION}" != "x" ]]; then
        echo "region detected from iam"
        header_config
        region_config $REGION
        fix_perm
    else
        echo "No region detected"
        exit 1
    fi
fi

# test if key and secret are mounted as secret
if test_config aws_access_key_id; then
    echo "aws key and secret found in ~/.aws mounted as secrets"
# if both key and secret are declared
elif [[ "$AWS_KEY" != "" && "$AWS_SECRET" != "" ]]; then
    echo "aws_access_key_id = $AWS_KEY" >> ${AWS_FOLDER}/config
    echo "aws_secret_access_key = $AWS_SECRET" >> ${AWS_FOLDER}/config
    fix_perm
# if the key and secret are not mounted as secrets
else
    echo "key and secret not available in ~/.aws/"
    if aws ecr get-authorization-token | grep expiresAt; then
        echo "iam role configured to allow ecr access"
    else
        echo "key and secret not mounted as secret, declared as variables or available from iam role"
        exit 1
    fi
fi

# update the auth token
if [ "$REGISTRY_ID" = "" ]; then
    aws_cli_exec=$(aws ecr get-login --no-include-email)
else
    aws_cli_exec=$(aws ecr get-login --no-include-email --registry-ids $REGISTRY_ID)
fi

auth=$(grep X-Forwarded-User ${nx_conf} | awk '{print $4}'| uniq | tr -d "\n\r")
token=$(echo "${aws_cli_exec}" | awk '{print $6}')
auth_n=$(echo AWS:${token}  | base64 |tr -d "[:space:]")
reg_url=$(echo "${aws_cli_exec}" | awk '{print $7}')

sed -i "s|${auth%??}|${auth_n}|g" ${nx_conf}
sed -i "s|REGISTRY_URL|$reg_url|g" ${nx_conf}

/renew_token.sh &

exec "$@"
