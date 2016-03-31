from ubuntu:14.04

run \
  apt-get update && \
  apt-get install -y haproxy && \
  rm -rf /var/lib/apt/lists/*

add haproxy.cfg /etc/haproxy/haproxy.cfg
# look for apps ip addr
#env app_0 $(getent hosts app_0 | awk '{ print $1 }')
#env app_1 $(getent hosts app_1 | awk '{ print $1 }')
#run sed -i 's/app_0/'${app_0}'/g' /etc/haproxy/haproxy.cfg
#run sed -i 's/app_1/'${app_1}'/g' /etc/haproxy/haproxy.cfg

run echo 'EXTRAOPTS="-db"' >>/etc/default/haproxy

cmd ["haproxy", "-f", "/etc/haproxy/haproxy.cfg", "-p", "-/var/run/haproxy.pid"]

expose 80
expose 443
