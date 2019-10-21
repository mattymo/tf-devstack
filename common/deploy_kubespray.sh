#!/bin/bash

set -o errexit

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/common.sh"

# parameters

K8S_MASTERS=${K8S_MASTERS:-$NODE_IP}
K8S_NODES=${K8S_NODES:-$NODE_IP}
K8S_POD_SUBNET=${K8S_POD_SUBNET:-}
K8S_SERVICE_SUBNET=${K8S_SERVICE_SUBNET:-}
CNI=${CNI:-cni}
# kubespray parameters like CLOUD_PROVIDER can be set as well prior to calling this script

[ "$(whoami)" == "root" ] && echo Please run script as non-root user && exit

# install required packages

if [ "$DISTRO" == "centos" ]; then
    sudo yum install -y python3 python3-pip libyaml-devel python3-devel ansible git
elif [ "$DISTRO" == "ubuntu" ]; then
    #TODO: should be broken for now
    sudo apt-get update
    sudo apt-get install -y python3 python3-pip libyaml-dev python3-dev ansible git
else
    echo "Unsupported OS version" && exit
fi

# prepare ssh key authorization for all-in-one single node deployment

[ ! -d ~/.ssh ] && mkdir ~/.ssh && chmod 0700 ~/.ssh
[ ! -f ~/.ssh/id_rsa ] && ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ''
[ ! -f ~/.ssh/authorized_keys ] && touch ~/.ssh/authorized_keys && chmod 0600 ~/.ssh/authorized_keys
grep "$(<~/.ssh/id_rsa.pub)" ~/.ssh/authorized_keys -q || cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

# deploy kubespray

[ ! -d kubespray ] && git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray/
sudo pip3 install -r requirements.txt

cp -rfp inventory/sample/ inventory/mycluster
declare -a IPS=( $K8S_MASTERS $K8S_NODES )
masters=( $K8S_MASTERS )
echo Deploying to IPs ${IPS[@]} with masters ${masters[@]}
export KUBE_MASTERS_MASTERS=${#masters[@]}
CONFIG_FILE=inventory/mycluster/hosts.yml python3 contrib/inventory_builder/inventory.py ${IPS[@]}
sed -i "s/kube_network_plugin: .*/kube_network_plugin: $CNI/g" inventory/mycluster/group_vars/k8s-cluster/k8s-cluster.yml
echo "helm_enabled: true" >> inventory/mycluster/group_vars/k8s-cluster/k8s-cluster.yml
extra_vars=""
[[ -z $K8S_POD_SUBNET ]] && extra_vars="-e kube_pods_subnet=$K8S_POD_SUBNET"
[[ -z $K8S_SERVICE_SUBNET ]] && extra_vars="$extra_vars -e kube_service_addresses=$K8S_SERVICE_SUBNET"
ansible-playbook -i inventory/mycluster/hosts.yml --become --become-user=root cluster.yml $extra_vars

mkdir -p ~/.kube
sudo cp /root/.kube/config ~/.kube/config
sudo chown -R $(id -u):$(id -g) ~/.kube

cd ../
