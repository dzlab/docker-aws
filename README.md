docker-aws
==============
[![License](http://img.shields.io/:license-mit-blue.svg)](http://doge.mit-license.org)

docker-aws is a collection of samples that aims at showing pratical cases of using Docker Swarm on AWS.

### Usage
```bash
# Create a Docker Swarm 
./swarminate.sh mk

# Run demo applications 
cd demoNUM && ./run deploy

# Destroy all machines in Swarm 
./swarminate.sh rm
```

### Warning
The `swarminate.sh` will create AWS resources with a cost that depends on their up time.
Don't forget to destroy these resources when you're done.

### Contribute
More demos will be added in the future. Any contribution is welcome.

