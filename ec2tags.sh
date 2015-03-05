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
        echo "Setting tags for the resources of ${line:15:10}"
        aws ec2 create-tags --profile=$PROFILE --resources $RESOURCES --tags `cat $TMPFILE`
        unlink $TMPFILE
    fi
    unset RESOURCES
  done
}

processSnapshots() {
  TSNAP="/tmp/$$.tsnap"
  TVOL="/tmp/$$.tvol"

  aws ec2 describe-snapshots --owner-id self | jq -c '.Snapshots[] | {VolumeId: .VolumeId, SnapshotId: .SnapshotId, Timestamp: .StartTime}' > $TSNAP
  aws --profile=$PROFILE ec2 describe-volumes | jq -c '.Volumes[] | {VolumeId: .VolumeId , Tags: .Tags[]}' > $TVOL

  # With this loop we'll set a tag for all snapshots at once that correspond to the given volume
  while read line; do
    VolumeId=`echo $line | jq '.VolumeId'`
    snapshots=(`cat $TSNAP | grep $VolumeId | cut -d "\"" -f 8` )
    tags=`echo $line | jq -c '.Tags' | sed -e 's/{//' -e 's/}//' -e 's/:/=/g'`
    if [[ ! -z $snapshots ]]; then
      echo "Setting tags for ${snapshots[*]}"
      aws ec2 create-tags --profile=$PROFILE --resources ${snapshots[*]} --tags $tags
    fi
  done < $TVOL

  unlink $TSNAP
  unlink $TVOL
}

for PROFILE in ${PROFILES[*]}; do
  echo "Processing the $PROFILE profile on `date +%F' '%T`" >> /var/log/ec2tags.log
  processInstances >> /var/log/ec2tags.log
  processSnapshots >> /var/log/ec2tags.log
done


