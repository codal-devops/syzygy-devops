#!/bin/bash

## start command: "sudo su -c /home/ubuntu/syzygy-devops/test.sh root"

## setting up environment variables

echo "$(tput bold)$(tput setaf 4)installing docker$(tput sgr 0)"

mkdir /etc/docker

cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

systemctl daemon-reload

apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg2

curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
echo 'deb [arch=amd64] https://download.docker.com/linux/debian stretch stable' > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y --no-install-recommends docker-ce
#sudo /etc/init.d/docker restart
systemctl daemon-reload
systemctl restart docker
usermod -aG docker ubuntu

## install kubernetes components

echo "$(tput bold)$(tput setaf 4)installing kubernetes components$(tput sgr 0)"

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -

cat > /etc/apt/sources.list.d/kubernetes.list <<EOF
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF

apt-get update
apt-get install -y kubelet kubeadm kubectl

systemctl restart kubelet

## iniate kubernetes master

echo "$(tput bold)$(tput setaf 4)iniating kubernetes master$(tput sgr 0)"

touch /home/ubuntu/syzygy-devops/kubeadm.yaml

cat <<EOF > kubeadm.yaml
---
apiVersion: kubeadm.k8s.io/v1beta2
featureGates:
  IPv6DualStack: false
kind: ClusterConfiguration
networking:
  podSubnet: 10.244.0.0/16
EOF

kubeadm init --config /home/ubuntu/syzygy-devops/kubeadm.yaml
#kubectl apply -f /home/ubuntu/syzygy-devops/kubeadm.yaml


## AWS CLI Installation

sudo apt-get install awscli -y
