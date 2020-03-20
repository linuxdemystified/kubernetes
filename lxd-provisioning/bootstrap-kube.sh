#!/bin/bash

# Install docker from Docker-ce repository
echo   "[TASK 1] Install docker container engine"
#apt install -y yum-utils device-mapper-persistent-data lvm2 > /dev/null 2>&1
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - > /dev/null 2>&1
add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable" > /dev/null 2>&1
apt-get update
apt-get install docker-ce docker-ce-cli containerd.io >/dev/null 2>&1

# Enable docker service
echo   "[TASK 2] Enable and start docker service"
systemctl enable docker >/dev/null 2>&1
systemctl start docker

# Add apt repo file for Kubernetes
echo   "[TASK 3] Add apt repo file for kubernetes"
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update

# Install Kubernetes
echo   "[TASK 4] Install Kubernetes (kubeadm, kubelet and kubectl)"
apt install -y kubeadm kubelet kubectl 
apt-mark hold kubelet kubeadm kubectl > /dev/null 2>&1

# Start and Enable kubelet service
echo   "[TASK 5] Enable and start kubelet service"
systemctl enable kubelet >/dev/null 2>&1
echo   'KUBELET_EXTRA_ARGS="--fail-swap-on=false"' > /usr/bin/kubelet
systemctl daemon-reload
systemctl start kubelet >/dev/null 2>&1

# Install Openssh server
echo   "[TASK 6] Install and configure ssh"
apt install -y openssh-server >/dev/null 2>&1
sed -i 's/.*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl enable sshd >/dev/null 2>&1
systemctl start sshd >/dev/null 2>&1

# Set Root password
echo   "[TASK 7] Set root password"
echo   "kubeadmin" | passwd --stdin root >/dev/null 2>&1

# Install additional required packages
echo "[TASK 8] Install additional packages"
apt install -y which net-tools sudo sshpass less >/dev/null 2>&1

# Hack required to provision K8s v1.15+ in LXC containers
mknod /dev/kmsg c 1 11

#######################################
# To be executed only on master nodes #
#######################################

if [[ $(hostname) =~ .*master.* ]]
then

  # Initialize Kubernetes
  echo   "[TASK 9] Initialize Kubernetes Cluster"
  kubeadm init --pod-network-cidr=10.244.0.0/16 --ignore-preflight-errors=all #>> /root/kubeinit.log 2>&1

  # Copy Kube admin config
  echo   "[TASK 10] Copy kube admin config to root user .kube directory"
  if [ ! -d /root/.kube ]
  then
      mkdir /root/.kube
  fi
  cp /etc/kubernetes/admin.conf /root/.kube/config

  # Deploy flannel network
  echo   "[TASK 11] Deploy flannel network"
  kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml > /dev/null 2>&1

  # Generate Cluster join command
  echo   "[TASK 12] Generate and save cluster join command to /joincluster.sh"
  joinCommand=$(kubeadm token create --print-join-command 2>/dev/null) 
  echo   "$joinCommand --ignore-preflight rrors=all" > /joincluster.sh

fi

#######################################
# To be executed only on worker nodes #
#######################################

if [[ $(hostname) =~ .*worker.* ]]
then

  # Join worker nodes to the Kubernetes cluster
  echo   "[TASK 9] Join node to Kubernetes Cluster"
  sshpass -p "kubeadmin" scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no kmaster.lxd:/joincluster.sh /joincluster.sh 2>/tmp/joincluster.log
  bash /joincluster.sh >> /tmp/joincluster.log 2>&1

fi



