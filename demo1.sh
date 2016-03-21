#!/bin/bash

set -e

# run demo app https://github.com/nathanleclaire/awsapp
# docker-machine should be configured before running this script

group_name="docker-networking"

# modify security group to open new ports
open_ports() {
  # get the security group ID
  group_id=$(aws ec2 describe-security-groups --filters Name=group-name,Values=${group_name} | jq '.["SecurityGroups"][0].GroupId' | sed -e 's/^"//'  -e 's/"$//')

  # allow http port for app instances
  aws ec2 authorize-security-group-ingress --group-id ${group_id} --protocol tcp --port 8000 --cidr 0.0.0.0/0
  aws ec2 authorize-security-group-ingress --group-id ${group_id} --protocol tcp --port 8001 --cidr 0.0.0.0/0

  # allow http/https ports for loadbalancer instance
  aws ec2 authorize-security-group-ingress --group-id ${group_id} --protocol tcp --port 80 --cidr 0.0.0.0/0
  aws ec2 authorize-security-group-ingress --group-id ${group_id} --protocol tcp --port 443 --cidr 0.0.0.0/0
 
  # allow redis port
  aws ec2 authorize-security-group-ingress --group-id ${group_id} --protocol tcp --port 6379 --cidr 0.0.0.0/0
}

# run all containers in a link mode
run_linked_containers () {
  # start "database" container
  echo "1. Starting 'redis' container"
  docker run -d -p 6379:6379 --name redis redis

  # start "app" containers
  echo "2. Starting 'app' containers"
  for i in {0..1}; do
    PORT=800${i}

    docker run -d -e SRV_NAME=s${i} -p ${PORT}:5000 --link redis:redis --name "app"_${i} nathanleclaire/awsapp:Thu_Nov_13_06_28_48_UTC_2014

    # give app a second to come back up
    sleep 1
  done

  # start "haproxy" container
  echo "3. Starting 'haproxy' container"
  docker run -d -P --link app_0 --name haproxy nathanleclaire/haproxy 
}

# run all containers using an overlay network
run_overlay_containers() {
  # docs: https://docs.docker.com/engine/userguide/networking/get-started-overlay/
  echo "1. Creating an overlay network"
  docker network create --driver overlay --subnet=10.0.9.0/24  demonet
  # to see all networks: docker network ls
  
  echo "2. Starting 'redis' container in 'demonet'"
  docker run -d -p 6379:6379 --name redis --net demonet redis

  echo "3. Starting 'app' containers"
  for i in {0..1}; do
    PORT=800${i}

    docker run -d -e SRV_NAME=s${i} -p ${PORT}:5000 --net demonet --name "app"_${i} nathanleclaire/awsapp:Thu_Nov_13_06_28_48_UTC_2014

    # give app a second to come back up
    sleep 1
  done

  sleep 5
  echo "4. Starting 'haproxy' container"
  docker run -d -p 80:80 -p 443:443 --net demonet --name haproxy dzlabs/haproxy 
}

# run a curl on a container
curlthis() {
  #docker run -it --net host nathanleclaire/curl curl "localhost:$1/health/$2"
  docker run -it --net host nathanleclaire/curl curl "$1"
}

################# 

open_ports || true

eval $(docker-machine env --swarm swarm-master)

#run_linked_containers && echo "Successfully started all containers" || echo "Failed to start all containers"
run_overlay_containers && echo "Successfully started all containers" || echo "Failed to start all containers"

# check health of apps
curlthis 'app_0:8000/health-check'
curlthis 'app_1:8001/health-check'

# build haproxy: docker build -t dzlabs/haproxy haproxy
# ssh into container: docker exec -i -t ba1313ff5bac bash
# modify health endpoint to `health-check` in /etc/haproxy/haproxy.cfg
# restart or start/stop container: docker restart 9d740f14779e
