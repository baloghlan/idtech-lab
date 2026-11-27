apt-get update

apt-get install -y ca-certificates curl gnupg

curl -fsSLo /tmp/elastic-signing-key.asc \
  https://artifacts.elastic.co/GPG-KEY-elasticsearch

gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg \
  /tmp/elastic-signing-key.asc

printf '%s\n' 'deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/9.x/apt stable main' > /etc/apt/sources.list.d/elastic-9.x.list

apt-get update

apt-get install -y elasticsearch

systemctl enable --now elasticsearch