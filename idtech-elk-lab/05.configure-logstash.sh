/usr/share/logstash/bin/logstash-keystore --path.settings /etc/logstash create
/usr/share/logstash/bin/logstash-keystore --path.settings /etc/logstash add ES_API_KEY
chown logstash:root /etc/logstash/logstash.keystore
chmod 0600 /etc/logstash/logstash.keystore