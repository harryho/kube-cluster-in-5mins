## Install basic packages 
install__ubuntu_packages(){
  sudo apt-get update
  sudo apt-get install -y apt-transport-https ca-certificates curl

  cp ~/.bashrc ~/.bashrc.bak
  cp ~/.profile ~/.profile.bak

  echo "alias rm='rm -i'">>~/.bashrc
  echo "alias scpf='source ~/.profile'">>.bashrc
  echo "alias scrc='source ~/.bashrc'">>.bashrc
}

install_centos_packages(){
  sudo apt-get update
  sudo apt-get install -y apt-transport-https ca-certificates curl

  cp ~/.bashrc ~/.bashrc.bak
  cp ~/.profile ~/.profile.bak

  echo "alias rm='rm -i'">>~/.bashrc
  echo "alias scpf='source ~/.profile'">>.bashrc
  echo "alias scrc='source ~/.bashrc'">>.bashrc
}


## Install Container Runtime
install_containerd(){
  wget  https://github.com/containerd/containerd/releases/download/v1.6.10/containerd-1.6.10-linux-amd64.tar.gz

  sudo tar Cxzvf /usr/local containerd-1.6.10-linux-amd64.tar.gz
}


## Use `systemd`

enable_systemd(){
  wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service

  sudo mkdir -p /usr/local/lib/systemd/system

  sudo cp containerd.service /usr/local/lib/systemd/system

  sudo systemctl daemon-reload
  sudo systemctl enable --now containerd
}

# Install runc

install_runc(){

  wget https://github.com/opencontainers/runc/releases/download/v1.1.4/runc.amd64

  sudo install -m 755 runc.amd64 /usr/local/sbin/runc
}

#### Install Kubectl

install_kubectl(){
  sudo apt-get update
  sudo apt-get install -y apt-transport-https ca-certificates curl

  sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg

  echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

  # download kubectl
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

  # validate 
  curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
  echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
  # install
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

  # Add bash completion
  echo 'source <(kubectl completion bash)' >>~/.bashrc
  source ~/.bashrc

  # check version
  kubectl version --client
  kubectl cluster-info
}


#### Install kubeadm , kubelet

install_kubeadm_kubelet(){
  DOWNLOAD_DIR="/usr/local/bin"
  sudo mkdir -p "$DOWNLOAD_DIR"

  # Install crictl (required for kubeadm / Kubelet Container Runtime Interface (CRI))
  CRICTL_VERSION="v1.25.0"
  ARCH="amd64"
  curl -L "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-${ARCH}.tar.gz" | sudo tar -C $DOWNLOAD_DIR -xz

  # Install kubeadm, kubelet, kubectl and add a kubelet systemd service
  RELEASE="$(curl -sSL https://dl.k8s.io/release/stable.txt)"
  ARCH="amd64"
  cd $DOWNLOAD_DIR
  sudo curl -L --remote-name-all https://dl.k8s.io/release/${RELEASE}/bin/linux/${ARCH}/{kubeadm,kubelet}
  sudo chmod +x {kubeadm,kubelet}

  RELEASE_VERSION="v0.4.0"
  curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/kubepkg/templates/latest/deb/kubelet/lib/systemd/system/kubelet.service" | sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | sudo tee /etc/systemd/system/kubelet.service
  sudo mkdir -p /etc/systemd/system/kubelet.service.d
  curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/kubepkg/templates/latest/deb/kubeadm/10-kubeadm.conf" | sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | sudo tee /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

  sudo systemctl enable kubelet.service
  sudo systemctl restart kubelet.service
}


### Configura IP forwarding

update_network_cfg() {
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
# Apply sysctl params without reboot
sudo sysctl --system
}


### Install CNI

isntall_cni(){
  wget https://go.dev/dl/go1.19.3.linux-amd64.tar.gz
  sudo rm -rf /usr/local/go && sudo  tar -C /usr/local -xzf go1.19.3.linux-amd64.tar.gz

  echo "export PATH=$PATH:/usr/local/go/bin" >> ~/.profile
  source ~/.profile
  go version

  git clone https://github.com/containerd/containerd.git
  cd containerd/script/setup
  ./install-cni

}

### pre-run kubeadm 

pre_run_kubeadm() {
  sudo swapoff -a 
  sudo apt install ebtables ethtool
  sudo apt install socat
  sudo apt install conntrack
  sudo apt install socat
}

### Create Kubernetes Cluster

create_cluster(){
  sudo kubeadm init > ka-init.log

  cat ka-init.log
}



### Setup the cluster configuration

get_cluster() {
  chown <uid>:<gid> ~/.kube/config

  kubectl cluster-info
}


### Dry-run test

dry_run() {
  kubectl auth can-i create deployments --namespace dev
  # yes
  kubectl auth can-i create deployments --namespace prod
  # yes
}

### Install plugins

install_metric_server(){
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
}

### Reset 
reset() {
    kubeadm reset  -f
    iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
}


init_master(){
  install_packages

  install_containerd

  enable_systemd

  install_runc

  install_kubectl

  install_kubeadm_kubelet

  update_network_cfg

  isntall_cni

  pre_run_kubeadm

  create_cluster
}


init_node() {

  install_containerd

  enable_systemd

  install_runc

  install_kubectl

  install_kubeadm_kubelet

  update_network_cfg

  isntall_cni

  pre_run_kubeadm

  # join the kube master - Use the command from master init log
  # E.g. kubectl join 192.168.1.112:6443 --token xxxxx \
  #    --discovery-token-ca-cert-hash sha256:a5aaaaaaaaaaaaaaaaaaaaaaa

}

main() {
  case "${1}" in
    u|ubuntu)
      install__ubuntu_packages
      ;;
    c|centos)
      install__centos_packages
      ;;
    m|master)
      init_master
      ;;
    n|node)
      init_node
      ;;
    r|reset)
      reset
      ;;
    *)
      echo "Usage: $0 <[u]buntu| [c]entos | [m]aster | [n]ode | [r]eset>
      u: Init ubuntu env
      c: Init centos env
      m: Create master control plane
      n: Create worker ndoe
      r: Reset configuration
      "

      return 1
      ;;
  esac
}

main "$@"
