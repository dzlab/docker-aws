#!/bin/bash

set -e

if [[ -z "$DOCKER_HUB_USER" ]]; then
  DOCKER_HUB_USER="dzlabs"
fi

group_name="docker-networking"
NETWORK="demonet"
APP_CONTAINER="demoapp"
HAPROXY_CONTAINER="haproxy"
REDIS_CONTAINER="redis"

# run pre-deploy tasks
pre_deploy() {
  echo "Opening additional ports"
  # get the security group ID
  group_id=$(aws ec2 describe-security-groups --filters Name=group-name,Values=${group_name} | jq '.["SecurityGroups"][0].GroupId' | sed -e 's/^"//'  -e 's/"$//')

  # allow http port for app instances
  aws ec2 authorize-security-group-ingress --group-id ${group_id} --protocol tcp --port 5000 --cidr 0.0.0.0/0

  # allow http/https ports for loadbalancer instance
  aws ec2 authorize-security-group-ingress --group-id ${group_id} --protocol tcp --port 80 --cidr 0.0.0.0/0
  aws ec2 authorize-security-group-ingress --group-id ${group_id} --protocol tcp --port 443 --cidr 0.0.0.0/0

  # allow redis port
  aws ec2 authorize-security-group-ingress --group-id ${group_id} --protocol tcp --port 6379 --cidr 0.0.0.0/0
}

# build docker images
build_images() {
  docker build -t ${DOCKER_HUB_USER}/demoapp ../demoapp
  docker build -t ${DOCKER_HUB_USER}/haproxy haproxy
}

# delpoy consul on all swarm machine instances
deploy_consul() {
  echo "Deploying consul on all nodes"
  kvip=$(docker-machine ip kvstore)
  NODES=($(docker-machine ls -q | grep "swarm" | tr '\n' ' '))
  # deploy consul on all swarm nodes
  for node in "${NODES[@]}"; do
    eval $(docker-machine env ${node})
    nodeip=$(docker-machine ip ${node})
    docker run --name consul-${node} -d \
      --net=host \
      -p 8300:8300 \
      -p 8301:8301 \
      -p 8301:8301/udp \
      -p 8302:8302 \
      -p 8302:8302/udp \
      -p 8400:8400 \
      -p 8500:8500 \
      -p 53:53 \
      -p 53:53/udp \
      progrium/consul \
        -server \
        -advertise ${nodeip} \
        -join ${kvip} \
        -log-level debug
  done
}

# deploy registrator on all swarm machine instances
deploy_registrator() {
  echo "Deploying registrator on all nodes"
  NODES=($(docker-machine ls -q | grep "swarm" | tr '\n' ' '))
  # deploy registrator on all swarm nodes
  for node in "${NODES[@]}"; do
    eval $(docker-machine env ${node})
    nodeip=$(docker-machine ip ${node})
    # deploy registrator on this machine 
    docker run -d \
      -v /var/run/docker.sock:/tmp/docker.sock \
      --name registrator-${node} \
      -h ${node} \
      gliderlabs/registrator \
        -ip ${nodeip} \
        consul://${nodeip}:8500
  done
  # connect docker to swarm master
  eval $(docker-machine env --swarm swarm-master)
}

# deploy application
deploy_app() {
  echo "Creating an overlay network"
  docker network create --driver overlay --subnet=10.0.9.0/24  ${NETWORK}
  kvip=$(docker-machine ip kvstore)
  echo "Depoloying haproxy"
  docker run -d -p 80:80 -p 443:443 \
    -e SERVICE_NAME=api \
    --name ${HAPROXY_CONTAINER} \
    --add-host consulip:${kvip} \
    --dns ${kvip} \
    --net ${NETWORK} \
    ${DOCKER_HUB_USER}/haproxy
  echo "Deploying Redis"
  docker run -d -p 6379:6379 \
    -e SERVICE_NAME=db \
    --name ${REDIS_CONTAINER} \
    --net ${NETWORK} \
    redis
  echo "Deploying application"
  for i in {1..3}; do
    docker run -d -p 5000:5000 \
      -e SERVICE_NAME=${APP_CONTAINER} \
      -e SERVICE_TAGS=v1 \
      -h ${APP}_${i} \
      --net ${NETWORK} \
      --name ${APP_CONTAINER}_${i} \
      ${DOCKER_HUB_USER}/demoapp
  done
}

# Destroy everything
teardown() {
  # may stop them first
  for i in {1..3}; do
    docker rm -f ${APP_CONTAINER}_${i}
  done
  docker rm -f ${HAPROXY_CONTAINER}
  docker rm -f ${REDIS_CONTAINER}
  docker network rm ${NETWORK}
  # destroy any registrator container before starting new one in this machine
  docker ps -aq -f image=gliderlabs/registrator | xargs docker rm -f > /dev/null 2>&1
  # more dangerous option: docker ps -q | xargs docker rm -f
}

################# 
eval $(docker-machine env --swarm swarm-master)

case $1 in 
  build)
    build_images
    ;;
  deploy)
    pre_deploy || true
    deploy_consul && echo "Consul started" || echo "Consul failed"
    deploy_registrator && echo "Registrators started" || echo "Registrators failed"
    deploy_app && echo "Successfully started apps" || echo "Failed to start apps"
    ;;
  rm)
    teardown || true
    ;;  
  curl)
    # check health of app
    curlthis 'app_1:5000/health/check'
    curlthis 'app_2:5000/health/check'
    ;;
  *)
    echo "Usage: demo1.sh [build | deploy | rm | curl]"
    exit 1
esac
