#!/bin/bash
set -x

export PREVIOUS_CLUSTER=~/root/ocp-dir
export IBMCLOUD_API_KEY=""
for i in 1 2 3 4 5
do
        TF_LOG=debug openshift-install destroy  cluster --log-level=debug --dir $PREVIOUS_CLUSTER  | tee log.log
        sleep 30
        TF_LOG=debug openshift-install destroy  cluster --log-level=debug --dir $PREVIOUS_CLUSTER  | tee log.log

        ibmcloud login

        #set service instance
        ibmcloud pi st <service instance id>

        CLOUD_CONNECTION=$(ibmcloud pi cons | awk "(NR>1)" | tail -n 1 | awk '{print $1}')

        if [ -n "$CLOUD_CONNECTION" ]
        then
                ibmcloud pi cond $CLOUD_CONNECTION
        fi

        ic pi nets |awk "(NR>1)"  |awk '{print $1}' > networks.txt
        while read p ; do ibmcloud pi netd $p; done< networks.txt

        ic pi cons

        ic pi nets
        export IBMCLOUD_OCCMIBCCC_API_KEY=""
        export IBMCLOUD_OIOCCC_API_KEY=""
        export IBMCLOUD_OMAPCC_API_KEY=""
        export CLUSTER_DIR="<cluster_dir>"
        export IBMID="<ibm_id>"
        export CLUSTER_NAME="<cluster_name>"
        export POWERVS_REGION=""
        export POWERVS_ZONE=""
        export SERVICE_INSTANCE_GUID=""
        export VPCREGION=""
        export RESOURCE_GROUP="ipi-resource-group"
        export BASEDOMAIN="ocp-powervs-ppc64le.com"
        export JENKINS_TOKEN=""
 

        /root/hack/create-cluster.sh 2>&1 | tee output-ATTEMPT-${i}.txt

        PREVIOUS_CLUSTER=$CLUSTER_DIR
        rm -rf networks.txt
done
