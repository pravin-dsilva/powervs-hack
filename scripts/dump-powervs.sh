#!/usr/bin/env bash

declare -a ENV_VARS
ENV_VARS=( "CLUSTER_DIR" "IBMCLOUD_API_KEY" )

for VAR in ${ENV_VARS[@]}
do
	if [[ ! -v ${VAR} ]]
	then
		echo "${VAR} must be set!"
		exit 1
	fi
	VALUE=$(eval "echo \"\${${VAR}}\"")
	if [[ -z "${VALUE}" ]]
	then
		echo "${VAR} must be set!"
		exit 1
	fi
done

set -euo pipefail

export INFRA_ID=$(jq -r '.infraID' ${CLUSTER_DIR}/metadata.json)
if [ -z "${INFRA_ID}" ]
then
	echo "Error: INFRA_ID is null?"
	exit 1
fi

export POWERVS_REGION=$(jq -r '.powervs.region' ${CLUSTER_DIR}/metadata.json)
if [ -z "${POWERVS_REGION}" ]
then
	echo "Error: POWERVS_REGION is null?"
	exit 1
fi

export SERVICE_ID=$(jq -r '.powervs.serviceInstanceID' ${CLUSTER_DIR}/metadata.json)
if [ -z "${SERVICE_ID}" ]
then
	echo "Error: SERVICE_ID is null?"
	exit 1
fi

export SERVICE_INSTANCE=$(ibmcloud resource service-instances --output JSON | jq -r '.[] | select(.guid|test("'${SERVICE_ID}'")) | .name')
if [ -z "${SERVICE_INSTANCE}" ]
then
	echo "Error: SERVICE_INSTANCE is null?"
	exit 1
fi

DNSRESOLV=""
hash getent && DNSRESOLV="getent ahostsv4"
hash dig && DNSRESOLV="dig +short"
if [ -z "${DNSRESOLV}" ]
then
	echo "Either getent or dig must be present!"
	exit 1
fi

if [ -z "$(${DNSRESOLV} ${POWERVS_REGION}.power-iaas.cloud.ibm.com)" ]
then
	echo "Error: POWERVS_REGION (${POWERVS_REGION}) is invalid!"
	exit 1
fi

export SERVICE_ID=$(ibmcloud pi service-list --json | jq -r '.[] | select (.Name|test("^'${SERVICE_INSTANCE}'$")) | .CRN')
if [ -z "${SERVICE_INSTANCE}" ]
then
	echo "Error: SERVICE_ID is null?"
       	exit 1
fi

export CLOUD_INSTANCE_ID=$(echo ${SERVICE_ID} | cut -d: -f8)
if [ -z "${CLOUD_INSTANCE_ID}" ]
then
	echo "Error: CLOUD_INSTANCE_ID is null?"
	exit 1
fi

BEARER_TOKEN=$(curl --silent -X POST "https://iam.cloud.ibm.com/identity/token" -H "content-type: application/x-www-form-urlencoded" -H "accept: application/json" -d "grant_type=urn%3Aibm%3Aparams%3Aoauth%3Agrant-type%3Aapikey&apikey=${IBMCLOUD_API_KEY}" | jq -r .access_token)
if [ -z "${BEARER_TOKEN}" -o "${BEARER_TOKEN}" == "null" ]
then
	echo "Error: Bearer token is empty/null?"
	exit 1
fi

echo "8<--------8<--------8<--------8<-------- Cloud Connection 8<--------8<--------8<--------8<--------"

CLOUD_UUID=$(ibmcloud pi connections --json | jq -r '.Payload.cloudConnections[] | select (.name|test("'${INFRA_ID}'")) | .cloudConnectionID')

if [ -z "${CLOUD_UUID}" ]
then
	echo "Error: Could not find a Cloud Connection with the name ${INFRA_ID}"
else
	ibmcloud pi connection ${CLOUD_UUID} || true
fi

echo "8<--------8<--------8<--------8<-------- Direct Link 8<--------8<--------8<--------8<--------"

DL_UUID=$(ibmcloud dl gateways --output json | jq -r '.[] | select (.name|test("'${INFRA_ID}'")) | .id')

if [ -z "${DL_UUID}" ]
then
	echo "Error: Could not find a Direct Link with the name ${INFRA_ID}"
else
	ibmcloud dl gateway ${DL_UUID} || true
fi

echo "8<--------8<--------8<--------8<-------- VPC 8<--------8<--------8<--------8<--------"

VPC_UUID=$(ibmcloud is vpcs --output json | jq -r '.[] | select (.name|test("'${INFRA_ID}'")) | .id')

if [ -z "${VPC_UUID}" ]
then
	echo "Error: Could not find a VPC with the name ${INFRA_ID}"
else
	ibmcloud is vpc ${VPC_UUID} || true
fi

echo "8<--------8<--------8<--------8<-------- DHCP networks 8<--------8<--------8<--------8<--------"

DHCP_NETWORKS_RESULT=$(curl --silent --location --request GET "https://${POWERVS_REGION}.power-iaas.cloud.ibm.com/pcloud/v1/cloud-instances/${CLOUD_INSTANCE_ID}/services/dhcp" --header 'Content-Type: application/json' --header "CRN: ${SERVICE_ID}" --header "Authorization: Bearer ${BEARER_TOKEN}")
echo "${DHCP_NETWORKS_RESULT}" | jq -r '.[] | "\(.id) - \(.network.name)"'

echo "8<--------8<--------8<--------8<-------- DHCP network information 8<--------8<--------8<--------8<--------"

while read DHCP_UUID
do
	RESULT=$(curl --silent --location --request GET "https://${POWERVS_REGION}.power-iaas.cloud.ibm.com/pcloud/v1/cloud-instances/${CLOUD_INSTANCE_ID}/services/dhcp/${DHCP_UUID}" --header 'Content-Type: application/json' --header "CRN: ${SERVICE_ID}" --header "Authorization: Bearer ${BEARER_TOKEN}")
	echo "${RESULT}" | jq -r '.'

done < <( echo "${DHCP_NETWORKS_RESULT}" | jq -r '.[] | .id' )

echo "8<--------8<--------8<--------8<-------- Instance names, ids, and MAC addresses 8<--------8<--------8<--------8<--------"

ibmcloud pi instances --json | jq -r '.Payload.pvmInstances[] | select (.serverName|test("'${INFRA_ID}'")) | [.serverName, .pvmInstanceID, .addresses[].ip, .addresses[].macAddress]'
