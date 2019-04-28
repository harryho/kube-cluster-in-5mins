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
HOORAY="\\(^o^)/"

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
  if [ "$VERBOSE" -gt "0" ]; then
    if [ -z "$NO_TIMESTAMP" ] || [ "$NO_TIMESTAMP" = "0" ]; then
      printf -- "%s" "[$(date)] "
    fi
    if [ -z "$2" ]; then
      printf -- "%s" "$1"
    else
      printf -- "%s" "$1='$2'"
    fi
     printf "\n" 
  fi
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
  # if [ -z "$NO_TIMESTAMP" ] || [ "$NO_TIMESTAMP" = "0" ]; then
    printf -- "ERROR: %s" "[$(date)] " >&2
  # fi
  if [ -z "$2" ]; then
    __red "$1" >&2
  else
    __red "$1='$2'" >&2
  fi
  printf "\n" >&2
  # return 1
}

_debug() {
  # echo "${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}"
  if [ "${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}" -ge "$LOG_LEVEL_1" ]; then
    _log "$@"
  fi
    if [ "${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}" -ge "$LOG_LEVEL_2" ]; then
    _printargs "$@" >&2
  fi
  # if [ "${DEBUG:-$DEBUG_LEVEL_NONE}" -ge "$DEBUG_LEVEL_1" ]; then
  #   _printargs "$@" >&2
  # fi
}

_cleanup() {
  _USER=""
  # DEBUG=$DEBUG_LEVEL_1
  LOG_LEVEL=$DEFAULT_LOG_LEVEL
  LOG_FILE=""
  VERBOSE=0
}

check_permission(){
  if [[ "$(whoami)" != "root" ]]
  then 
    __red "The script must be run as root"
    __red "Please switch to root user"
    __hints
    exit
  fi
}


_command_exists() {
    command -v "$@" > /dev/null 2>&1
}

install_docker(){
  _debug install_docker 

  echo $BEGIN_DOCKER
  
  if [ -z $(_command_exists docker) ]; then
    apt-get update;
    apt-get install -y apt-transport-https \
      ca-certificates curl \
      gnupg-agent software-properties-common;

    _finger=$(apt-key finger | egrep "0EBFCD88")
    echo $_finger
    if [ -z "$_finger" ];
    then 
     curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
       | sudo apt-key add -

     apt-key fingerprint 0EBFCD88
    fi;
  
    _docker_repo=$(apt-cache policy|egrep "docker")
    if [ -z "$_docker_repo" ] ;
    then
      add-apt-repository \
       "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
       $(lsb_release -cs) \
       stable"
    fi

    apt-get update

    apt-get install -y docker-ce docker-ce-cli containerd.io

    usermod -aG docker $_USER 
  else 
      _debug "$HOORAY: docker is found!"
  fi

  echo $END_DOCKER


}

__update_cgroup(){

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
}

__is_cluster_available(){

}

install_kube(){
  _debug install_kube

  echo $BEGIN_KUBE
  
  __update_cgroup
  if [ -z $( _command_exists kubeadm) ] \
     || [ -z $(_command_exists kubelet) ] \
     || [ -z $(_command_exists kubectl) ] ;
  then
    apt-get update && apt-get install -y apt-transport-https curl
  
    _kube_key=$(apt-key finger  | egrep  "Google Cloud")

    [[ -z "$_kube_key" ]] &&  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
    
     _kube_repo=$(apt-cache policy | egrep kube)
     [[ -z "$_kube_repo" ]] && echo "deb https://apt.kubernetes.io/ kubernetes-xenial main">/etc/apt/sources.list.d/kubernetes.list
  
    apt-get update
    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl
  else
      _debug "$HOORAY: kubeadm is found."   
  fi
  echo $END_KUDE

}

__disable_swap(){

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

  printf -- "$BEGIN init_cluster(): %s" "[$(date)] " >&2
  _debug init_cluster

  __disable_swap
   
  kubeadm init>kube-init.log
  cat kube-init.log
  
  # reload daemon and restart kubelet
  systemctl daemon-reload
  systemctl restart kubelet

  printf -- "$END init_cluster(): %s" "[$(date)] " >&2

}

install_dashboard() {
  
  printf -- "$BEGIN install_dashboard(): %s" "[$(date)] " >&2
  _debug install_dashboard
  # echo $BEGIN_DASHBOARD

  export KUBECONFIG=/etc/kubernetes/admin.conf
  
  ## Install pod network
  sysctl net.bridge.bridge-nf-call-iptables=1
  
  kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
  
  
  # set node be able to schedule
  kubectl taint nodes --all node-role.kubernetes.io/master-
  
  # create new account and role bind for dashboard
  # cat<<EOF | kubectl apply -f - 
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

  printf -- "$END install_dashboard(): %s" "[$(date)] " >&2

 }

__install_heapster() {
   
  #  echo $BEGIN_HEAPSTER
   _debug __install_heapster
   printf -- "$BEGIN __install_heapster(): %s" "[$(date)] " >&2


   [[ -d "harryho-heapster" ]] && rm -rf harryho-heapster
   git clone https://github.com/harryho/heapster  harryho-heapster
   kubectl apply -f harryho-heapster/deploy/kube-config/rbac/
   kubectl apply -f harryho-heapster/deploy/kube-config/influxdb/
   rm -rf harryho-heapster

   printf -- "$END __install_heapster(): %s" "[$(date)] " >&2


}

setup_kube_config(){

  printf -- "$BEGIN setup_kube_config(): %s" "[$(date)] " >&2


   # setup kube config for a regular user
  if [[ -d "/home/$_USER/.kube" ]]
  then 
      _debug "$WORKING: Backup old .kube folder to .kube_backup"
      mv -f  /home/$_USER/.kube /home/$_USER/.kube_backup
  fi
  
  mkdir -p /home/$_USER/.kube
  cp -i /etc/kubernetes/admin.conf /home/$_USER/.kube/config
  chown -R $_USER:$_USER /home/$_USER/.kube/
  
  # sleep 5
  
  __green "$SMILING:new cluster is ready."
  printf "It will take some time (30 seconds ~ 3 mins) to get all pods \n"
  printf "and services up, which depends your hardware and VM setting. "
  __green  "\n$HOORAY: You can use kubeclt proxy to access the dashboard from localhost:8001"
  
  _debug $END_KUBE_CONFIG
  unset KUBECONFIG
  
  printf -- "$END setup_kube_config(): %s" "[$(date)] " >&2
  # cd $_USER 
  su $_USER && cd

}

init() {
   printf -- "$BEGIN init(): %s" "[$(date)] " >&2
   _debug init

   install_docker 
   install_kube

   reset

   init_cluster
   install_dashboard
  #  _install_heapster
   setup_kube_config
   
   printf -- "$END--init(): %s" "[$(date)] " >&2  
}

reset() {

  printf -- "$BEGIN--reset(): %s" "[$(date)] " >&2

  if [ -z $(_command_exists kubelet)]; then
    msg="$CRYING: Kubelet is not found! Please install kubelet first"
    echo $msg
    _debug $msg
    __hints
    exit
  else
  # check if the cluster is still available
  NodeNotFound=$(systemctl status kubelet | grep "not found" | wc --lines)
  
  if [ $NodeNotFound > 0 ] ;
  then
      printf "\n $CRYING: WARNING: Your IP address has been changed!!!"
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
  
  printf -- "$END--reset(): %s" "[$(date)] " >&2

}

__uninstall(){
  __red "WARNING!!! It is a hidden feature. You are supposed to know what you are doinig. \n"

  read -s "Do you want to continue? Y or N [yYnN]" _yes_or_no

  if [ "$__yes_or_no" = "Y"] ; then
    
    printf -- "$BEGIN__uninstall(): %s" "[$(date)] " >&2
    _debug __uninstall
   
    __red "The script will start uninstallation process in 5 seconds. You can cancel by pressing Ctrl + C or Ctrl + D or Ctrl + Z".
    
    sleep 5

    _debug "Stop and disable kubelet and docker"

    systemctl stop kubelet
    systemctl stop docker*
    systemctl disable kubelet
    systemctl disable docker*
    
    _debug "Uninstall kubelet and docker"

    apt-mark unhold kubectl kubeadm kubelet
    apt purge -y kubelet kubeadm kubectl
    apt purge -y docker-ce docker-ce-cli containerd.io
    apt autoremove -y
    rm -f /usr/bin/kubeadm  /usr/bin/kubelet /usr/bin/kubectl

    printf -- "$END__uninstall(): %s" "[$(date)] " >&2

  fi
}



__init_setting(){
  WORKING_DIR=$HOME
  DEFAULT_LOG_FILE="$WORKING_DIR/$PROJECT_NAME.log"
}

logo(){
  # echo |  cat < $LOGO
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
  echo "$HOORAY Welome to use kube-cluster script!"
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
      --uninstall)
        _CMD="uninstall" 
        ;;       
      --user)
        _USER="$2"
        if [ "$_USER" ="root" ]; then
           cd  /$_USER
        else 
           cd /home/$_USER 
        fi
        shift 
        ;;
      --verbose)
        VERBOSE=1
        ;;
      # --debug)
      #   if [ -z "$2" ] || _startswith "$2" "-"; then
      #     DEBUG="$DEBUG_LEVEL_DEFAULT"
      #   else
      #     DEBUG="$2"
      #     shift
      #   fi
        ;;
      --log | --logfile)
        _log="1"
        _logfile="$2"
        if _startswith "$_logfile" '-'; then
          _logfile=""
        else
          _debug "You can find log file from: $DEFAULT_LOG_FILE"
          shift
        fi
        LOG_FILE="$_logfile"
        if [ -z "$LOG_LEVEL" ]; then
          LOG_LEVEL="$DEFAULT_LOG_LEVEL"
        fi
        ;;
      --log-level)
        _log_level="$2"
        LOG_LEVEL="$_log_level"
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
    setup_kube_config
      setup_kube_config
      ;;
    uninstall
      uninstall
      ;;
    *)
      if [ "$_CMD" ]; then
        _err "Invalid command: $_CMD"
      fi
      showhelp
      return 1
  esac
}


showhelp() {

  version
  echo "Usage: $PROJECT_ENTRY  command ...parameters....
Commands:
  --help, -h                        Show this help message.
  --version, -v                     Show version info.
  --init                            Create a new cluster. If existing cluster is found, the script will launch --reset command to remove the old cluster
  --reset                           Cleanup and remove the old cluster.               
  --install-docker                  Install docker if the docker is not found.
  --install-kube                    Install kubeadm, kubelet and kubectl if kubernetes is not found.
  --log    [/path/to/logfile]       Specifies the log file. The default is: \"$DEFAULT_LOG_FILE\" if you don't give a file path here.
  --log-level 1|2                   Specifies the log level, default is 1.
  
Parameters:
  --user   <user_name>              Specifies a user and user's home dir as working dir for docker and kube. Root user and its home dir is not recommended.

Examples:
  Following command will commmit a few actions:
  * Install docker and kube if they are found
  * Reset old cluster if it is not available because of change of network
  * Initiate a new cluster and save configuration to dir /home/my_user_name
  * Log all information to /home/my_user_name/my-cluster.log
  * Print out all information to terminal

  kube-cluster.sh --init my_user_name  --verbose --log my-cluster.log --log-level 2
"
}

main() {
  check_permission
  logo
  [ -z "$1" ] && showhelp && return
  if _startswith "$1" '-'; then _process "$@"; else "$@"; fi
}

main "$@"

