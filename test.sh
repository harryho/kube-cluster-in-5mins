_command_exists() {
    command -v "$@" > /dev/null 2>&1
}

test(){
 if [ -z $(_command_exists kubelet)]; then
    echo "not exists"
 fi

}

test


