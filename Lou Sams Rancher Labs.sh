Lou.Sams@rancher.com

Rancher Labs

https://vagrantcloud.com/ubuntu/xenial64
#peru/ubuntu-18.04-desktop-amd64
vagrant box add --clean --insecure --location-trusted ubuntu/xenial64

docker run -d -p 80:80 -p 443:443 -v /opt/rancher:/var/lib/rancher --name rancher rancher/rancher:stable

git config --global http.sslVerify false
git config --global http.proxy http://qin682:Tnd571101@gateway.zscloud.net:10336/

cat<<EOF >>rancher.sh
#!/bin/bash
docker run -d --restart=unless-stopped -p 80:80 -p 443:443 -v /opt/rancher:/var/lib/rancher --name rancher -e http_proxy=http://gateway.zscloud.net:10336/ -e https_proxy=http://gateway.zscloud.net:10336/ -e no_proxy=127..0.0.1 rancher/rancher:stable
EOF
chmod 755 rancher.sh

# proxy
docker run --rm -p 80:80 -p 443:443 -v /opt/rancher:/var/lib/rancher --name rancher -e HTTP_PROXY=http://qin682:Tnd571101@gateway.zscloud.net:10336/ -e HTTPS_PROXY=http://qin682:Tnd571101@gateway.zscloud.net:10336/ -e NO_PROXY=127.0.0.1,0.0.0.0,172.22.101.101,172.22.101.* -v ~/certs/single_file_all_certs.pem:/etc/rancher/ssl/single_file_all_certs.pem rancher/rancher:stable

# base run
docker run --rm -p 8000:80 -p 443:443 -v /opt/rancher:/var/lib/rancher --name rancher rancher/rancher:stable

"insecure-registries" : ["myregistrydomain.com:5000"]
sudo cp installaiton/certificates/docker-registry.crt /usr/local/share/ca-certificates

http://172.22.101.101/

[ERROR] CatalogController library [catalog] failed with : Error in HTTP GET to [https://git.rancher.io/charts/index.yaml], error: Get https://git.rancher.io/charts/index.yaml: x509: certificate signed by unknown authority