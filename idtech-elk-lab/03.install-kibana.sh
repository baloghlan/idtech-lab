ES_VERSION="$(dpkg-query -W -f='${Version}' elasticsearch)"

apt-get update

apt-get install -y "kibana=$ES_VERSION"

# Set kibana host in kibana.yml
sed -i 's/#server.host: "localhost"/server.host: "0.0.0.0"' /etc/kibana/kibana.yml

systemctl enable --now kibana

/usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana