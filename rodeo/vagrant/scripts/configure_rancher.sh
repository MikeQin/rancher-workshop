#!/bin/bash

set -xeu

export DEBIAN_FRONTEND=noninteractive
export APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1
DIR=/usr/local/share/ca-certificates

# Install ca-certificates first
apt-get install -y ca-certificates

# Copy /tmp/single_file_all_certs.crt to /usr/local/share/ca-certificates
cp /tmp/single_file_all_certs.pem $DIR/single_file_all_certs.crt

# Update CERTS before curl
update-ca-certificates

# Add apt-key for docker, --insecure
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
# Add apt-repository config for docker
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# Update and upgrade first
apt-get update && apt-get upgrade -y

# Install docker
apt-get install -y docker-ce docker-ce-cli containerd.io

# Post install docker
## groupadd docker
usermod -aG docker vagrant
systemctl enable docker
systemctl start docker

# Docker version
docker version

## Set up Docker Compose: --insecure can be an option
curl -sSL "https://github.com/docker/compose/releases/download/1.23.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Check version
docker-compose --version

# Create Docker config
if [ ! -d "/home/vagrant/.docker" ]; then
  mkdir /home/vagrant/.docker
fi

# Configure Docker proxy, and create it if not existed
cat <<EOF >> /home/vagrant/.docker/config.json
{
  "proxies":
  {
    "default":
    {
      "httpProxy": "$HTTP_PROXY",
      "httpsProxy": "$HTTP_PROXY",
      "noProxy": "127.0.0.1,localhost,.zscloud.net"
    }
  }
}
EOF

chown -R vagrant:vagrant /home/vagrant/.docker

export curlimage=appropriate/curl
export jqimage=stedolan/jq

function do_login() {
  local count=0
  local max_count=12
  local password

  if [[ -n ${1+x} ]]; then
    password=$1
  else
    password=${admin_password}
  fi

  while true; do

      LOGINRESPONSE=$(docker run \
          --rm \
          --net=host \
          ${curlimage} \
          -s "https://${rancher_server_ip}/v3-public/localProviders/local?action=login" -H 'content-type: application/json' --data-binary '{"username":"admin","password":"'"${password}"'"}' --insecure)
      LOGINTOKEN=$(echo ${LOGINRESPONSE} | docker run --rm -i ${jqimage} -r .token)
      echo "Login Token is ${LOGINTOKEN}"
      if [ "${LOGINTOKEN}" != "null" ]; then
          break
      else
          sleep 5
          count=$(( ${count} + 1 ))

          if [[ ${count} -eq ${max_count} ]]; then
            echo "Unable to login within ${max_count} tries."
            exit 1
          fi
      fi
  done
}

function build_server() {
  # install NFS support
  apt-get -qq -y install nfs-kernel-server

  docker run -d --restart=unless-stopped -p 80:80 -p 443:443 -v /opt/rancher:/var/lib/rancher rancher/rancher:${rancher_version}

  while true; do
    docker run --rm --net=host ${curlimage} -sLk https://127.0.0.1/ping && break
    sleep 5
  done

  # do initial login with default password
  do_login "admin"

  # Change password
  docker run --rm --net=host ${curlimage} -s 'https://127.0.0.1/v3/users?action=changepassword' -H 'content-type: application/json' -H "Authorization: Bearer ${LOGINTOKEN}" --data-binary '{"currentPassword":"admin","newPassword":"'"${admin_password}"'"}' --insecure

  # Create API key
  APIRESPONSE=$(docker run --rm --net=host ${curlimage} -s 'https://127.0.0.1/v3/token' -H 'content-type: application/json' -H "Authorization: Bearer ${LOGINTOKEN}" --data-binary '{"type":"token","description":"automation"}' --insecure)

  # Extract and store token
  APITOKEN=`echo ${APIRESPONSE} | docker run --rm -i ${jqimage} -r .token`

  # Configure server-url
  docker run --rm --net=host ${curlimage} -s 'https://127.0.0.1/v3/settings/server-url' -H 'content-type: application/json' -H "Authorization: Bearer ${APITOKEN}" -X PUT --data-binary '{"name":"server-url","value":"https://'"${rancher_server_ip}"'/"}' --insecure

  # Create cluster
  CLUSTERRESPONSE=$(docker run --rm --net=host ${curlimage} -s 'https://127.0.0.1/v3/cluster' -H 'content-type: application/json' -H "Authorization: Bearer ${APITOKEN}" --data-binary '{"type":"cluster","rancherKubernetesEngineConfig":{"addonJobTimeout":30,"ignoreDockerVersion":true,"sshAgentAuth":false,"type":"rancherKubernetesEngineConfig","authentication":{"type":"authnConfig","strategy":"x509"},"network":{"type":"networkConfig","plugin":"canal"},"ingress":{"type":"ingressConfig","provider":"nginx"},"services":{"type":"rkeConfigServices","kubeApi":{"podSecurityPolicy":false,"type":"kubeAPIService"},"etcd":{"snapshot":false,"type":"etcdService","extraArgs":{"heartbeat-interval":500,"election-timeout":5000}}}},"name":"'"${cluster_name}"'"}' --insecure)

  # Extract clusterid to use for generating the docker run command
  CLUSTERID=`echo ${CLUSTERRESPONSE} | docker run --rm -i ${jqimage} -r .id`

  # Generate registrationtoken
  docker run --rm --net=host ${curlimage} -s 'https://127.0.0.1/v3/clusterregistrationtoken' -H 'content-type: application/json' -H "Authorization: Bearer ${APITOKEN}" --data-binary '{"type":"clusterRegistrationToken","clusterId":"'"${CLUSTERID}"'"}' --insecure

}

function build_node() {
  while true; do
  docker run --rm ${curlimage} -sLk https://${rancher_server_ip}/ping && break
    sleep 5
  done

  # Login
  do_login

  # Get the Agent Image from the rancher server
  while true; do
    AGENTIMAGE=$(docker run \
      --rm \
      ${curlimage} \
        -sLk \
        -H "Authorization: Bearer ${LOGINTOKEN}" \
        "https://${rancher_server_ip}/v3/settings/agent-image" | docker run --rm -i ${jqimage} -r '.value')

    if [ -n "${AGENTIMAGE}" ]; then
      break
    else
      sleep 5
    fi
  done

  until docker inspect ${AGENTIMAGE} > /dev/null 2>&1; do
    docker pull ${AGENTIMAGE}
    sleep 2
  done

  # Test if cluster is created
  while true; do
    CLUSTERID=$(docker run \
      --rm \
      ${curlimage} \
        -sLk \
        -H "Authorization: Bearer ${LOGINTOKEN}" \
        "https://${rancher_server_ip}/v3/clusters?name=${cluster_name}" | docker run --rm -i ${jqimage} -r '.data[].id')

    if [ -n "${CLUSTERID}" ]; then
      break
    else
      sleep 5
    fi
  done

  # Get role flags from hostname
  ROLEFLAG=${rancher_role}
  if [[ "${ROLEFLAG}" == "all" ]]; then
    ROLEFLAG="all-roles"
  fi

  # Get token
  # Test if cluster is created
  while true; do
    AGENTCMD=$(docker run \
      --rm \
      ${curlimage} \
        -sLk \
        -H "Authorization: Bearer ${LOGINTOKEN}" \
        "https://${rancher_server_ip}/v3/clusterregistrationtoken?clusterId=${CLUSTERID}" | docker run --rm -i ${jqimage} -r '.data[].nodeCommand' | head -1)

    if [ -n "${AGENTCMD}" ]; then
      break
    else
      sleep 5
    fi
  done

  # Combine command and flags
  COMPLETECMD="${AGENTCMD} --${ROLEFLAG} --address ${node_ip}"

  # Run command
  ${COMPLETECMD}

}

function install_docker() {
  set +e
  which docker > /dev/null
  docker_installed=$?

  if [[ ${docker_installed} -ne 0 ]]; then
    # install docker
    if [ `command -v curl` ]; then
      curl -sL https://releases.rancher.com/install-docker/${docker_version}.sh | sh
    elif [ `command -v wget` ]; then
      wget -qO- https://releases.rancher.com/install-docker/${docker_version}.sh | sh
    fi
  else
    echo "Skipping Docker install."
  fi

  set -e
}

function install_prereqs() {
  for image in ${curlimage} ${jqimage}; do
    until docker inspect ${image} > /dev/null 2>&1; do
      docker pull ${image}
      sleep 2
    done
  done
}

# main execution

# Make sure we have Docker installed before continuing
install_docker

# If we're in a rodeo, we don't want to build the cluster for them.
if [[ -z ${rodeo} || ${rodeo} == "true" ]]; then
  exit 0
fi

install_prereqs

case ${rancher_role} in
  server )
    build_server
    ;;
  node|all|controlplane|worker|etcd )
    build_node
    ;;
  *)
    echo "Unknown role ${rancher_role}."
    exit 1
esac

exit 0