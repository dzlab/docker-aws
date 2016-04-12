#!/bin/sh

set -e

#$AWS_ACCESS_KEY_ID and $AWS_SECRET_ACCESS_KEY have to be defined, see ~/.aws/credentials

if [ -z $AWS_ACCESS_KEY_ID ]; then
    echo "Please supply your AWS_ACCESS_KEY_ID"
    exit 1
fi
if [ -z $AWS_SECRET_ACCESS_KEY ]; then
    echo "Please supply your AWS_SECRET_ACCESS_KEY"
    exit 1
fi

group_id=""
group_name="docker-networking"
group_id=$(aws ec2 describe-security-groups --filters Name=group-name,Values=${group_name} | jq '.["SecurityGroups"][0].GroupId' | sed -e 's/^"//'  -e 's/"$//')

#my_ip="$(wget -q -O- http://icanhazip.com)"
my_ip=$(curl -s http://icanhazip.com)

# For details https://docs.docker.com/machine/drivers/aws/
# Get the AMI for your region from this list: https://wiki.debian.org/Cloud/AmazonEC2Image/Jessie, or https://cloud-images.ubuntu.com/locator/ec2/
# Paravirtual only - HVM AMI's and Docker Machine don't seem to be working well together
#export AWS_AMI="ami-8aa67cf9"
#export AWS_SSH_USER="admin"
export AWS_DEFAULT_REGION="eu-west-1"
# This is my default VPC, yours will be different
export AWS_VPC_ID="vpc-be157ddb"
export AWS_INSTANCE_TYPE="t2.medium"

#### Set up Security Group in AWS
createSecurityGroup() {
	group_id=$(aws ec2 create-security-group --group-name ${group_name} --vpc-id ${AWS_VPC_ID} --description "A Security Group for Docker Networking" \
		| jq '.GroupId' \
    | sed -e 's/^"//'  -e 's/"$//'
  )
	# Permit SSH, required for Docker Machine  : --cidr ${my_ip}/32
	aws ec2 authorize-security-group-ingress --group-id ${group_id} --protocol tcp --port 22 --cidr $my_ip/32
	aws ec2 authorize-security-group-ingress --group-id ${group_id} --protocol tcp --port 2376 --cidr 0.0.0.0/0
  # Permit Control plane (Serf ports for discovery)
	aws ec2 authorize-security-group-ingress --group-id ${group_id} --protocol tcp --port 7946 --cidr 0.0.0.0/0
	aws ec2 authorize-security-group-ingress --group-id ${group_id} --protocol udp --port 7946 --cidr 0.0.0.0/0
	# Permit Consul HTTP API
	aws ec2 authorize-security-group-ingress --group-id ${group_id} --protocol tcp --port 8500 --cidr 0.0.0.0/0
  # Permit Data plane (VXLAN)
	aws ec2 authorize-security-group-ingress --group-id ${group_id} --protocol udp --port 4789 --cidr 0.0.0.0/0
}

create() {
  #CLUSTER_ID=$(docker run swarm create | tail -n 1)
  echo "01 - Creating a security group for Docker networking"
  createSecurityGroup && echo "Successfully created new security group ${group_name} with ID ${group_id}"
  echo "02 - Setting up kv store"
  docker-machine create -d amazonec2 \
    --amazonec2-security-group ${group_name} \
    kvstore && \
  docker $(docker-machine config kvstore) run -d --net=host progrium/consul --server -bootstrap-expect 1

  # store the IP address of the kvstore machine
  kvip=$(docker-machine ip kvstore)

  echo "03 - Creating SWARM master"
  docker-machine create --driver amazonec2 \
    --amazonec2-security-group ${group_name} \
    --engine-opt "cluster-store consul://${kvip}:8500" \
    --engine-opt "cluster-advertise eth0:2376" \
    --swarm --swarm-master \
    --swarm-discovery=consul://${kvip}:8500 \
    swarm-master
    # For a default bridged networking  --swarm-discovery=token://$CLUSTER_ID \
  echo "04 - Creating swarm nodes on AWS"
  for i in 0 1 2 3; do
    docker-machine create --driver amazonec2 \
      --amazonec2-security-group ${group_name} \
      --engine-opt "cluster-store consul://${kvip}:8500" \
      --engine-opt "cluster-advertise eth0:2376" \
      --swarm \
      --swarm-discovery=consul://${kvip}:8500 \
      swarm-agent-$i &
     # For a default bridged networking --swarm-discovery=token://$CLUSTER_ID \
  done
  wait   
  echo "04 - Set the DOCKER_HOST env variable"
  eval $(docker-machine env --swarm swarm-master)
}

start() {
  echo "01 - Starting key-value store"
  docker-machine start kvstore 
  echo "02 - Starting swarm nodes"
  docker-machine start swarm-master 
  for i in 0 1 2 3; do
    docker-machine start swarm-agent-$i 
  done
  wait
}

teardown() {
  echo "01 - Stopping key-value store"
  docker-machine stop kvstore &
  echo "02 - Stopping swarm nodes"
  docker-machine stop swarm-master &
  for i in 0 1 2 3; do
    docker-machine stop swarm-agent-$i &
  done
  wait
}

remove() {
  echo "01 - Tearing down key-value store"
  docker-machine rm -f kvstore &
  echo "02 - Tearing down swarm nodes"
  docker-machine rm -f swarm-master &
  for i in 0 1 2 3; do
    docker-machine rm -f swarm-agent-$i &
  done
  wait
  echo "03 - Deleting security group ${group_name} with ID ${group_id}"
  #aws ec2 delete-security-group --group-name ${group_name}
  aws ec2 delete-security-group --group-id ${group_id}
}

case $1 in
  mk)
    create
    ;;
  up)
    start
    ;;
  down)
    teardown
    ;;
  rm)
    remove
    ;;
  *)
    echo "Unknown command $1"
    echo "Usage: swarminate.sh [mk | up | down | rm]"
    exit 1
    ;;
esac
