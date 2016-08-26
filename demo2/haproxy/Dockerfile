FROM alpine
MAINTAINER dzlab <dzlabs@outlook.com>

run apk --update add haproxy curl


# Download consul-template
env CONSUL_TEMPLATE_VERSION=0.14.0
run cd /tmp && \
  curl -O https://releases.hashicorp.com/consul-template/${CONSUL_TEMPLATE_VERSION}/consul-template_${CONSUL_TEMPLATE_VERSION}_linux_amd64.zip && \
  unzip consul-template_${CONSUL_TEMPLATE_VERSION}_linux_amd64.zip && \
  mv consul-template /usr/bin && \
  rm -rf /tmp/*

# add consul-template config file
add haproxy.json /etc/haproxy/haproxy.json
# add consul-template templating file
add haproxy.ctmpl /etc/haproxy/haproxy.ctmpl

# start consul-template
CMD ["consul-template", "-config=/etc/haproxy/haproxy.json"]

expose 80
expose 443
