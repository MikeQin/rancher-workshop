# Web
https://github.com/rancher/rodeo
https://github.com/rancher/rodeo/blob/master/guide/provisioning.md
https://github.com/rancher/rodeo/blob/master/guide/deploying-rancher-server.md

# Get source code
git clone https://github.com/rancher/rodeo.git

# Disconnect Remote Git, under rodeo root:
rm -rf .git .gitignore

# Move to vagrant
cd rodeo/vagrant

# Start
vagrant up

# check status
vagrant status

# ssh to server
vagrant ssh server-01

# connect to node
vagrant ssh node-01

# stop VMs
vagrant halt

# delete VMs
vagrant destroy -f

# on Server and Node after login, add user to docker group
sudo usermod -aG docker $USER

# Re-login to run docker

cat<<EOF >> rancher.sh
#!/bin/bash
docker run -d --rm -p 80:80 -p 443:443 -v /opt/rancher:/var/lib/rancher --name rancher rancher/rancher:stable
EOF
chmod 755 rancher.sh

cat<<EOF >> rancher-stop.sh
#!/bin/bash
docker stop rancher
EOF
chmod 755 rancher-stop.sh

cat<<EOF >> .profile
alias ll='ls -laF'
export PATH=$PATH:.
EOF
source .profile

# start rancher server
docker run -d --rm \
-p 80:80 -p 443:443 \
-v /opt/rancher:/var/lib/rancher \
--name rancher
rancher/rancher:stable

# stop rancher server
docker stop rancher

# Server UI
http://172.22.101.101/

# Login
admin:admin

# Training
https://www.youtube.com/results?search_query=rancher+kubernetes

# Intro
https://www.youtube.com/watch?v=sMSvjz-hyiA