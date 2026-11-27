# ELK Stack Lab

This lab runs Elasticsearch, Kibana, Logstash, and Filebeat on a single Ubuntu 22.04 Incus VM (`elk-lab`, `192.168.56.50`). Logstash reads a sample file directly and receives additional logs from Filebeat. It parses each event's timestamp and writes the events to daily `elk-lab-*` indices in Elasticsearch.

## Setup

1. Run `bash 01.init-vms.sh` on the Incus host. The VM uses 4 vCPUs, 8 GiB of RAM, and a 40 GiB disk.
2. Run scripts `02` through `06` in order inside the VM as root. Enroll Kibana with Elasticsearch and store the Logstash API key in the Logstash keystore as `ES_API_KEY`. Scope the key to `elk-lab-*`.
3. Copy `logstash.conf` to `/etc/logstash/conf.d/10-elk-lab.conf` and `filebeat.yml` to `/etc/filebeat/filebeat.yml`, then start both services.
4. Open Kibana at `http://192.168.56.50:5601`. Configure the `elk-lab-*` index template with `@timestamp` as a `date` field and attach the `elk-lab-retention` policy. The policy transitions indices to the warm phase after 7 days and deletes them after 30 days.

## Results

The `ELK Lab Logs` data view uses `@timestamp` as its time field. Discover shows the ingested logs, and the Lens chart plots the number of records over time.

- [Filebeat delivery](screenshots/06.filebeat-running.png)
- [Logs in Discover](screenshots/09.kibana-discover-logs.png)
- [Log count over time](screenshots/10.kibana-log-count-over-time.png)