apt-get update
apt-get install -y 'logstash=1:9.5.7-1'

install -D -o root -g logstash -m 0640 \
  /etc/elasticsearch/certs/http_ca.crt /etc/logstash/certs/http_ca.crt

install -d -o root -g logstash -m 0750 /var/log/elk-lab-direct