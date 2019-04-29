#!/bin/bash
set -e

##################################################################
# Project: Kube-Cluster
# Version: 1.0
#
# This script is meant to setup kubernetes cluster via kubeadm on Ubuntu 16+.
# It is supposed to be run by root user. All installation follows the
# instructions from https://kubernetes.io
#
# The script has been tested on Ubuntu Server 16, 18. You will get your
# cluster up and run in 5 mins.
#
# Please check out the README of repo. I recommend you test it on VM via
# VirtualBox or VMWare first.
##################################################################


VER="1.0"
AUTHOR="Harry Ho"
PROJECT="kube-cluster"
PROJECT_ENTRY="kube-cluster.sh"
LOGO="logo"

BEGIN="BEGIN"
END="END"

LOG_LEVEL_1=1
LOG_LEVEL_2=2
LOG_LEVEL_3=3
DEFAULT_LOG_LEVEL=$LOG_LEVEL_1


CRYING="(T_T)"
SMILING="(^_^)"
WORKING="(6_6)"
HOORAY="(^o^)/"

VERBOSE=0
WORKING_DIR=""
DEFAULT_LOG_FILE=""



__green() {
    printf '\033[1;31;32m%b\033[0m' "$1"
    return
}

__hints(){
  __green "Use --help to find out the usage. \n"
  return
}

__red() {
    printf '\033[1;31;40m%b\033[0m' "$1"
    printf "\n" >&2
    return
}

_printargs() {

    if [ -z "$NO_TIMESTAMP" ] || [ "$NO_TIMESTAMP" = "0" ]; then
      printf -- "%s" "[$(date)] "
    fi
    if [ -z "$2" ]; then
      printf -- "%s" "$1"
    else
      printf -- "%s" "$1='$2'"
    fi
     printf "\n"
  
}

_upper_case() {
  tr 'a-z' 'A-Z'
}

_lower_case() {
  tr 'A-Z' 'a-z'
}

_endswith() {
  _str="$1"
  _sub="$2"
  echo "$_str" | grep -- "$_sub\$" >/dev/null 2>&1
}


_startswith() {
  _str="$1"
  _sub="$2"
  echo "$_str" | grep "^$_sub" >/dev/null 2>&1
}


_contains() {
  _str="$1"
  _sub="$2"
  echo "$_str" | grep -- "$_sub" >/dev/null 2>&1
}

_log() {
  [ -z "$LOG_FILE" ] && return
  _printargs "$@" >>"$LOG_FILE"
}

_info() {
  _log "$@"
  _printargs "$@"
}


_err() {
  _log "$@"
  printf -- "ERROR: %s" "[$(date)]" >&2; printf "\n" >&2

  if [ -z "$2" ]; then
    __red "$1" >&2
  else
    __red "$1='$2'" >&2
  fi
  printf "\n" >&2

}

_debug() {
  [ "$VERBOSE" -gt "0" ] && $( printf "$@" >&2 ; printf "\n" >&2 ; )

  if [ "${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}" -ge "$LOG_LEVEL_1" ]; then 
    _log "$@"
  fi

  if [ "${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}" -ge "$LOG_LEVEL_2" ]; then
     _printargs "$@" >&2
  fi
}

_cleanup() {
  _USER=""
  LOG_LEVEL=$DEFAULT_LOG_LEVEL
  LOG_FILE=""
  VERBOSE=0
}

_check_permission(){
  if [[ "$(whoami)" != "root" ]]
  then
    __red "The script must be run as root"
    __red "Please switch to root user"
    exit
  fi
}


_command_exists() {
    command -v "$@" > /dev/null 2>&1
}

install_docker(){
  _debug install_docker

  printf -- "$BEGIN install_docker(): %s" "[$(date)]" >&2; printf "\n" >&2

  apt-get update;
  apt-get install -y apt-transport-https \
    ca-certificates curl \
    gnupg-agent software-properties-common;

  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  sudo apt-key fingerprint 0EBFCD88

  add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu  $(lsb_release -cs) stable"

  apt-get update

  apt-get install -y docker-ce docker-ce-cli containerd.io

  usermod -aG docker $_USER
  
  printf -- "$END install_docker(): %s" "[$(date)]" >&2; printf "\n" >&2

}

__update_cgroup(){

  _debug "$BEGIN __update_cgroup"
  # setup the daemon with systemd as cgroup driver
  echo '
  {
    "exec-opts": ["native.cgroupdriver=systemd"],
    "log-driver": "json-file",
    "log-opts": {
      "max-size": "100m"
    },
    "storage-driver": "overlay2"
  }'>/etc/docker/daemon.json

  mkdir -p /etc/systemd/system/docker.service.d

  # # Restart docker.
  systemctl daemon-reload
  systemctl restart docker

   _debug "$END __update_cgroup"
}



install_kube(){
  _debug install_kube

  printf -- "$BEGIN install_kube(): %s" "[$(date)]" >&2; printf "\n" >&2

  _debug __update_cgroup

  apt-get update && apt-get install -y apt-transport-https curl

  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -

  echo "deb https://apt.kubernetes.io/ kubernetes-xenial main">/etc/apt/sources.list.d/kubernetes.list
  
  apt-get update
  apt-get install -y kubelet kubeadm kubectl
  apt-mark hold kubelet kubeadm kubectl

  printf -- "$END install_kube(): %s" "[$(date)]" >&2; 
  printf "\n" >&2
}

disable_swap(){

  SWAP=$(swapon -s)
  if [ -z "$SWAP" ]
  then
    _debug "SWAP is disabled"
  else
    swapoff -a
    sed -i.bak -e '/^UUID.*swap/d' /etc/fstab
    _debug "Swap drive is removed. You can roll back from file /etc/fstab.bak"
  fi
}

init_cluster() {

  printf -- "$BEGIN init_cluster(): %s" "[$(date)]" >&2; printf "\n" >&2
  _debug init_cluster

  disable_swap

  kubeadm init>kube-init.log
  cat kube-init.log

  # reload daemon and restart kubelet
  systemctl daemon-reload
  systemctl restart kubelet

  printf -- "$END init_cluster(): %s" "[$(date)]" >&2; printf "\n" >&2

}

install_dashboard() {

  printf -- "$BEGIN install_dashboard(): %s" "[$(date)]" >&2; printf "\n" >&2
  _debug install_dashboard

  export KUBECONFIG=/etc/kubernetes/admin.conf

  ## Install pod network
  sysctl net.bridge.bridge-nf-call-iptables=1

  kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"

  # set node be able to schedule
  kubectl taint nodes --all node-role.kubernetes.io/master-

  # create new account and role bind for dashboard
  cat<<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kube-system
EOF

  # install dashboard
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v1.10.1/src/deploy/recommended/kubernetes-dashboard.yaml

  # get token to access dashboard
  kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}')

  # set nodeport for dashboard pod
  _debug "$WORKING:rename context name to us2-dev-cxt"
  kubectl config use-context kubernetes-admin@kubernetes
  kubectl config rename-context  kubernetes-admin@kubernetes us2-dev-cxt
  kubectl config use-context us2-dev-cxt

  _debug "Update IP type to nodeport"
  kubectl -n kube-system  get service kubernetes-dashboard -o yaml | sed -e 's/type\: ClusterIP/type\: NodePort/g' | kubectl replace -f -

  __install_heapster

  printf -- "$END install_dashboard(): %s" "[$(date)]" >&2; printf "\n" >&2

 }

__install_heapster() {

   _debug __install_heapster
   printf -- "$BEGIN __install_heapster(): %s" "[$(date)]" >&2; printf "\n" >&2

   [[ -d "us2hho-heapster" ]] && rm -rf us2hho-heapster
   git clone https://github.com/us2hho/heapster  us2hho-heapster
   kubectl apply -f us2hho-heapster/deploy/kube-config/rbac/
   kubectl apply -f us2hho-heapster/deploy/kube-config/influxdb/
   rm -rf us2hho-heapster

   printf -- "$END __install_heapster(): %s" "[$(date)]" >&2; printf "\n" >&2
}

setup_kube_config(){

  printf -- "$BEGIN setup_kube_config(): %s" "[$(date)]" >&2;
  printf "\n" >&2

  # setup kube config for a regular user
  _debug "WORKING_DIR" "$WORKING_DIR"
  _debug "LOG_FILE" "$LOG_FILE"

  if [[ -d "$WORKING_DIR/.kube" ]]
  then
      _debug "$WORKING: Backup old .kube folder to .kube_backup"
      rm -rf $WORKING_DIR/.kube_backup
      mv -f  $WORKING_DIR/.kube $WORKING_DIR/.kube_backup
  fi

  mkdir -p $WORKING_DIR/.kube
  cp -i /etc/kubernetes/admin.conf $WORKING_DIR/.kube/config
  chown -R $_USER:$_USER $WORKING_DIR/.kube

  __green "$SMILING:new cluster is ready."
  printf "\nBefore you attempt to access the dashboard via browse, \n"
  printf "please check out the status of pods and services via 'kubectl'. \n"
  __green  "\n$HOORAY: You can use kubeclt proxy to access the dashboard from localhost:8001\n"


  _debug "unset KUBECONFIG"
  unset KUBECONFIG

  printf -- "$END setup_kube_config(): %s" "[$(date)]" >&2; 
  printf "\n" >&2

  su $_USER && cd

}

init() {
   printf -- "$BEGIN init(): %s" "[$(date)]" >&2; 
   printf "\n" >&2

   _debug init

   install_docker
   install_kube

   reset

   init_cluster
   install_dashboard

   setup_kube_config

   printf -- "$END init(): %s" "[$(date)]" >&2; 
   printf "\n" >&2
}

reset() {

  printf -- "$BEGIN reset(): %s" "[$(date)]" >&2; 
  printf "\n" >&2

  if _command_exists kubelet ; then
     # check if the cluster is still available
    NodeNotFound=$(systemctl status kubelet | grep "not found" | wc --lines)

    if [ $NodeNotFound > 0 ] ;
    then
    #   printf "\n $CRYING: WARNING: Your IP address has been changed!!!"
      printf "\n $WORKING: Kubeadm will be reset and init again. \n"
    fi;

    _debug "$WORKING: reset kubeadm at "$(date)


    kubeadm reset  -f

    iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X


    if [[ -d "/etc/kubernetes" ]]
    then
      rm -rf /etc/kubernetes/manifests /etc/kubernetes/pki
      rm -f /etc/kubernetes/admin.conf /etc/kubernetes/kubelet.conf /etc/kubernetes/bootstrap-kubelet.conf /etc/kubernetes/controller-manager.conf /etc/kubernetes/scheduler.conf
    fi;

    systemctl restart docker
    systemctl daemon-reload
    systemctl stop kubelet

    for c in $(docker container ls | egrep  -o "k8s_weave.*" )
    do
      docker container stop $c  --force
      docker container rm $c --force
    done;

    if [[ -d "/home/$_USER/.kube/" ]]
    then
      [[ -f "/home/$_USER/.kube/config" ]] && rm -f /home/$_USER/.kube/config;
      [[ -d "/home/$_USER/.kube/cache" ]] && rm -rf /home/$_USER/.kube/cache;
    fi;

    if [[ -d "/root/.kube/" ]]
    then
      [[ -f "/root/.kube/config" ]] && rm -f /root/.kube/config;
      [[ -d "/root/.kube/cache" ]] && rm -rf /root/.kube/cache;
    fi;

    systemctl start kubelet
  else
    msg="$CRYING: Kubelet is not found! Please install kubelet first"
    _debug $msg
    __hints
    exit
  fi;

  printf -- "$END reset(): %s" "[$(date)] " >&2; 
  printf "\n" >&2
}

__uninstall(){

  __red "WARNING!!! It is a hidden feature. You are supposed to know what you are doinig. \n"

  read -p "Do you want to continue? Y or N [yYnN]: " _yes_or_no

  if [[ "$_yes_or_no" == "Y" ]] || [[ "$_yes_or_no" == "y" ]] ; then
    printf -- "$BEGIN __uninstall(): %s" "[$(date)]" >&2; 
    printf "\n" >&2
    _debug __uninstall
    __red "\n The script will start uninstallation process in 5 seconds. You can cancel by pressing Ctrl + C or Ctrl + D or Ctrl + Z".
    sleep 5
    _debug "Stop and disable kubelet and docker"
    
    sudo systemctl disable docker
    sudo systemctl disable kubelet
    _debug "Uninstall kubelet and docker"
    apt-mark unhold kubectl kubeadm kubelet
    apt purge -y kubelet kubeadm kubectl
    apt purge -y docker-ce docker-ce-cli containerd.io
    apt autoremove -y
    rm -f /usr/bin/kubeadm  /usr/bin/kubelet /usr/bin/kubectl
    printf -- "$END __uninstall(): %s" "[$(date)]" >&2; 
    printf "\n" >&2
  fi
}

__init_setting(){
  WORKING_DIR=$HOME
  DEFAULT_LOG_FILE="$WORKING_DIR/$PROJECT_NAME.log"
}

logo(){
cat >&2<<- 'EOF'
 .S    S.    .S       S.    .S_SSSs      sSSs
.SS    SS.  .SS       SS.  .SS~SSSSS    d%%SP
S%S    S&S  S%S       S%S  S%S   SSSS  d%S'
S%S    d*S  S%S       S%S  S%S    S%S  S%S
S&S   .S*S  S&S       S&S  S%S SSSS%P  S&S
S&S_sdSSS   S&S       S&S  S&S  SSSY   S&S_Ss
S&S~YSSY%b  S&S       S&S  S&S    S&S  S&S~SP
S&S    `S%  S&S       S&S  S&S    S&S  S&S
S*S     S%  S*b       d*S  S*S    S&S  S*b
S*S     S&  S*S.     .S*S  S*S    S*S  S*S.
S*S     S&   SSSbs_sdSSS   S*S SSSSP    SSSbs
S*S     SS    YSSP~YSSY    S*S  SSY      YSSP
SP                         SP
Y                          Y
EOF
  _cleanup
  version

}

version() {
  echo "$PROJECT $VER"
  echo "Author: $AUTHOR"
  printf "$HOORAY Welome to use kube-cluster script! \n"
  printf "\n">&2
}

_process() {
  _CMD=""
  _confighome=""
  _home=""
  _logfile=""
  _log=""
  _log_level=""
  _debug "$@"

  while [ ${#} -gt 0 ]; do
    _debug "${1}"
    case "${1}" in
      --help | -h)
        showhelp
        return
        ;;
      --version | -v)
        version
        return
        ;;
      --init)
        _CMD="init"
        ;;
      --install-docker)
        _CMD="install_docker"
        ;;
      --install-kube)
        _CMD="install_kube"
        ;;
      --init-cluster)
        _CMD="init_cluster"
        ;;
      --install-dashboard)
        _CMD="install_dashboard"
        ;;
      --kube-config)
        _CMD="setup_kube_config"
        ;;
      --reset)
        _CMD="reset"
        ;;
      --disable-swap)
        _CMD="disable_swap"
        ;;
      --uninstall)
        _CMD="uninstall"
        ;;
      --user)
        _USER="$2"
        if [[ "$_USER" == "root" ]]; then
          WORKING_DIR="/$_USER"
          cd  /$_USER
        else
          WORKING_DIR="/home/$_USER"
          cd /home/$_USER
        fi
        shift
        ;;
      --verbose)
        VERBOSE=1
        ;;
      --log | --logfile)
        _log="1"
        _logfile="$2"
        if _startswith "$_logfile" '-'; then
          _logfile=""
        else
          DEFAULT_LOG_FILE="$WORKING_DIR/$_logfile"
          _debug "You can find log file from: $DEFAULT_LOG_FILE"
          shift
        fi
        LOG_FILE="$DEFAULT_LOG_FILE"
        _debug "LOG_FILE" "$LOG_FILE"
        if [ -z "$LOG_LEVEL" ]; then
          LOG_LEVEL="$DEFAULT_LOG_LEVEL"
        fi
        ;;
      --log-level)
        _log_level="$2"
        LOG_LEVEL="$_log_level"
        echo $LOG_LEVEL
        shift
        ;;
      *)
        _err "Unknown parameter : $1"
        __hints
        return 1
        ;;
    esac
    shift 1
  done

  _debug "${_CMD} - ${_USER}"


  case "${_CMD}" in
    init)
      init
      ;;
    reset)
      reset
      ;;
    install_docker)
      install_docker
      ;;
    install_kube)
      install_kube
      ;;
    init_cluster)
      init_cluster
      ;;
    install_dashboard)
      install_dashboard
      ;;
    setup_kube_config)
      setup_kube_config
      ;;
    disable_swap)
      disable_swap
      ;;
    uninstall)
      __uninstall
      ;;
    *)
      if [ "$_CMD" ]; then
        _err "Invalid command: $_CMD"
      fi
      showhelp
      return 1
      ;;
  esac
}


showhelp() {

  # version
  echo "Usage: $PROJECT_ENTRY  command ...parameters....
Commands:
  --help, -h                        Show this help message.
  --version, -v                     Show version info.
  --init                            Launch a few commands in order, including install docker and kubernetes, if they are not found in the system, and then create a new cluster. If existing cluster is found, the script will call --reset command to remove the existing cluster. After that, it will install dashboard and heapster. Finally, it will setup kube configuation to the user home dir.
  --reset                           Cleanup and remove the old cluster.
  --install-docker                  Install docker if the docker is not found.
  --install-kube                    Install kubeadm, kubelet and kubectl if kubernetes is not found.
  --init-cluster                    Initiate a new cluster if the kubelet is found. It will call --reset command to remove the existing one.
  --kube-config                     Setup a kube config to a new user home dir.
  --disable-swap                    Disable swap for kubernetes and comment out swap drive on /etd/fstab

Parameters:
  --user   <user_name>              Specifies a user and user's home dir as working dir for docker and kube. Root user and its home dir is not recommended.
  --log    [logfile]                Specifies the log file. The default is: \"$DEFAULT_LOG_FILE\" if you don't give a file path here.
  --log-level 1|2                   Specifies the log level, default is 1.

Examples:
- Sample 1
  Following command will commmit a few actions:
  * Install docker and kube if they are found
  * Reset old cluster if it is not available because of change of network
  * Initiate a new cluster and save configuration to dir /home/user_name
  * Log all information to /home/user_name/my-cluster.log
  * Print out all information to terminal

  ./kube-cluster.sh --init --user user_name  --verbose --log my-cluster.log

- Sample 2
  Use reset command to remove and cleanup the cluster 

  ./kube-cluster.sh --reset --user user_name --verbose --log reset.log

- Sample 3
  Install docker 

  ./kube-cluster.sh --install-docker --user user_name

- Sample 4
  Install kubeadm, kubelet and kubectl 

  ./kube-cluster.sh --install-kube --user user_name
"
}

main() {
  _check_permission
  logo
  [ -z "$1" ] && showhelp && return
  if _startswith "$1" '-'; then _process "$@"; else "$@"; fi
}

main "$@"

