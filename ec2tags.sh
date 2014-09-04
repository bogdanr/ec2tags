#!/bin/bash
#
# This script is used to add tags for the resources associated to an instance
#
# Author: Bogdan Radulescu <bogdan@nimblex.net>

# Settings
#
# We need to define profiles in 
PROFILES=(bk-eu-west bk-us-west bk-us-east bk-ap-southeast)

# Check if we have jq
which jq >/dev/null
if [[ $? != "0" ]]; then
    if [[ `uname -m` = "x86_64" ]]; then
        wget -O /usr/local/bin/jq http://stedolan.github.io/jq/download/linux64/jq
    else
        wget -O /usr/local/bin/jq http://stedolan.github.io/jq/download/linux32/jq
    fi
    chmod +x /usr/local/bin/jq
fi



TMPFILE="/tmp/$$.tmp"

processInstances() {
  aws ec2 describe-instances --profile=$PROFILE | jq '.Reservations[].Instances[] | { InstanceId: .InstanceId, VpcId: .VpcId, NetworkInterfaceId: .NetworkInterfaces[].NetworkInterfaceId, VolumeId: .BlockDeviceMappings, Tags: .Tags } | del(.VolumeId[].DeviceName) | del(.VolumeId[].Ebs.Status) | del(.VolumeId[].Ebs.DeleteOnTermination)' -c | \
  while read line; do
    RESOURCES=`echo $line | jq '.VolumeId[].Ebs.VolumeId' -r`
    RESOURCES=$RESOURCES" `echo $line | jq '.NetworkInterfaceId' -r`"
    echo $line | jq '.Tags[]' -c | awk '/Product/' | \
        while read line; do
            echo $line | sed -e 's/{//' -e 's/}//' -e 's/:/=/g' >> $TMPFILE
        done
    if [ -f $TMPFILE ]; then
        echo "Setting tags for the resources of the ${line:15:10} instance"
        aws ec2 create-tags --profile=$PROFILE --resources $RESOURCES --tags `cat $TMPFILE`
        unlink $TMPFILE
    fi
    unset RESOURCES
  done
}


for PROFILE in ${PROFILES[*]}; do
  processInstances >> /var/log/ec2tags.log
done

#Perhaps we can use this for additional checks
#aws ec2 describe-tags | jq '.Tags[]' -c


