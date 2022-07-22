function da/checkout() {
    if [[ $# < 2 || $1 == '--help' ]] ; then
        cat <<EOF
da/checkout - create a docker volume containing a git checkout.

Usage: da/checkout <checkout name> <git url>

Examples: da/checkout myproj http://github.com/myorg/myproj.git
EOF
        return
    fi

    NAME=$(echo $1 | tr '\-_' '..')
    GIT_URL=$2

    docker network create ${NAME}_default

    cat ~/.gitconfig > /tmp/g1
    cat ~/.git-credentials > /tmp/g2
    chmod ugo+r /tmp/g1 /tmp/g2
    docker run \
        --rm \
        --volume ${NAME}_checkout:/home/dev/work:rw \
        --volume /tmp/g1:/home/dev/g1 \
        --volume /tmp/g2:/home/dev/g2 \
        linkuistics/devanyware-headless:4.0.2 \
        zsh -c "(cd ; cat g1 > .gitconfig ; cat g2 > .git-credentials) && git clone $GIT_URL"
   rm /tmp/g1 /tmp/g2
}

function da/run-prod() {
    if [[ $# < 2 || $1 == '--help' ]] ; then
        cat <<EOF
da/run-prod - run a docker volume containing a checkout using the prod profile

Usage: da/run-prod <checkout name> <port base>

Example: da/run-prod myproj 6000
EOF
        return
    fi

    NAME=$(echo $1 | tr '\-_' '..')
    PORT_PREFIX=${2%[0-9][0-9]}

    STARTUP_SCRIPT="\
               sudo chmod go+w /var/run/docker.sock \
            && export PORT_PREFIX=$PORT_PREFIX \
            && export COMPOSE_PROJECT_NAME=$NAME \
            && cd *\
            && docker-compose --profile prod up -d --build
    "

    docker run \
        --rm \
        --volume /var/run/docker.sock:/var/run/docker.sock:rw \
        --volume ${NAME}_checkout:/home/dev/work:rw \
        --network ${NAME}_default \
        linkuistics/devanyware-headless:4.0.2 \
        zsh -c "$STARTUP_SCRIPT"
}

function da/logs() {
    if [[ $# < 1 || $1 == '--help' ]] ; then
        cat <<EOF
da/logs - show the logs from a running checkout

Usage: da/logs <checkout name>

Example: da/logs myproj

Ctrl-C to stop the logs
EOF
        return
    fi

    NAME=$(echo $1 | tr '\-_' '..')

    STARTUP_SCRIPT="\
               sudo chmod go+w /var/run/docker.sock \
            && export PORT_PREFIX=$PORT_PREFIX \
            && export COMPOSE_PROJECT_NAME=$NAME \
            && cd *\
            && docker-compose logs -f
    "

    docker run \
        --rm \
        --volume /var/run/docker.sock:/var/run/docker.sock:rw \
        --volume ${NAME}_checkout:/home/dev/work:rw \
        --network ${NAME}_default \
        linkuistics/devanyware-headless:4.0.2 \
        zsh -c "$STARTUP_SCRIPT"
}

function da/delete() {
    if [[ $# < 1 || $1 == '--help' ]] ; then
        cat <<EOF
da/delete - delete everything associated with a checkout

Usage: da/delete <checkout name>

Example: da/delete myproj

Note that this deletes absolutely everything associated with the checkout, including volumes.
EOF
        return
    fi

    NAME=$(echo $1 | tr '\-_' '..')

    for container in $(docker container list -a --format '{{.Names}}' | grep ^${NAME}'[-_]') ; do
        docker rm -f $container
    done

    for network in $(docker network list --format '{{.Name}}' | grep ^${NAME}'[-_]') ; do
        docker network rm $network
    done

    for volume in $(docker volume list --format '{{.Name}}' | grep ^${NAME}'[-_]') ; do
        docker volume rm $volume
    done
}

function da/dev-start() {
    if [[ $# < 2 || $1 == '--help' ]] ; then
        cat <<EOF
da/dev-start - start a development container for a checkout

Usage: da/dev-start <checkout name> <ssh port> [<subname>]

Examples: da/dev-start myproj 6000      # container is myproj-dev
          da/dev-start myproj 6001 rust # container is myproj-rust

Note that the first two digiti of the ssh port name provides the port prefix for the services
EOF
        return
    fi

    NAME=$(echo $1 | tr '\-_' '..')
    PORT=$2
    PORT_PREFIX=${PORT%[0-9][0-9]}
    CONTAINER_NAME=${NAME}-${3-dev}

    STARTUP_SCRIPT="\
               sudo chmod go+w /var/run/docker.sock \
            && echo \"export PORT_PREFIX=$PORT_PREFIX ; export COMPOSE_PROJECT_NAME=$NAME\" > /home/dev/.config/zsh/docker-compose-config.zshrc \
            && start-headless
    "

    docker run \
        --detach \
        --name $CONTAINER_NAME \
        --volume /var/run/docker.sock:/var/run/docker.sock:rw \
        --volume ${NAME}_checkout:/home/dev/work:rw \
        --publish ${PORT}:22 \
        --network ${NAME}_default \
        --restart unless-stopped \
        linkuistics/devanyware-headless:4.0.2 \
        zsh -c "$STARTUP_SCRIPT"
}

function da/dev-stop() {
    if [[ $# < 1 || $1 == '--help' ]] ; then
        cat <<EOF
da/dev-stop - stop (delete) a development container for a checkout

Usage: da/dev-stop <checkout name> [<subname>]

Examples: da/dev-stop myproj
          da/dev-stop myproj rust
EOF
        return
    fi

    NAME=$(echo $1 | tr '\-_' '..')
    CONTAINER_NAME=${NAME}-${2-dev}

    docker rm -f $CONTAINER_NAME
}
