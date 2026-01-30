#!/bin/bash

VERSION="3.6.4"
wget https://github.com/grafana/loki/releases/download/v${VERSION}/promtail-linux-amd64.zip
sudo apt-get install unzip -y
unzip promtail-linux-amd64.zip
sudo mv promtail-linux-amd64 /usr/local/bin/promtail
rm promtail-linux-amd64.zip

sudo useradd --no-create-home --shell /bin/false promtail
sudo groupadd promtail
sudo usermod -g promtail promtail

sudo mkdir -p /etc/promtail
sudo mkdir -p /var/lib/promtail

sudo tee /etc/promtail/config.yml > /dev/null <<EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: https://loki.domain/loki/api/v1/push
    basic_auth:
      username: promtail
      password: CHANGE_ME

scrape_configs:
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          host: $(hostname)
          __path__: /var/log/*.log

  - job_name: journal
    journal:
      max_age: 12h
      labels:
        job: systemd-journal
        host: $(hostname)
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: 'unit'

  - job_name: nginx
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx
          host: $(hostname)
          __path__: /var/log/nginx/*log
    pipeline_stages:
      - regex:
          expression: '^(?P<remote_addr>[\w\.:]+) - (?P<remote_user>[^ ]+) \[(?P<time_local>[^\]]+)\] "(?P<method>\w+) (?P<request_uri>[^ ]+) (?P<protocol>[^"]+)" (?P<status>\d+) (?P<body_bytes_sent>\d+) "(?P<http_referer>[^"]*)" "(?P<http_user_agent>[^"]*)"'
      - labels:
          method:
          status:
      - structured_metadata:
          remote_addr:
          request_uri:
          http_user_agent:
          body_bytes_sent:
      - timestamp:
          source: time_local
          format: 02/Jan/2006:15:04:05 -0700

  - job_name: application
    static_configs:
      - targets:
          - localhost
        labels:
          job: application
          host: $(hostname)
          __path__: /home/ubuntu/photobooth-manager/logs/*.log
    pipeline_stages:
      - match:
          selector: '{job="application"}'
          stages:
            - regex:
                expression: '^(?P<timestamp>\S+) \[(?P<level>\w+)\] (?P<app_name>[\w\-]+) (?P<source>\w+) -- (?P<remote_addr>[\w\.:]+) \[(?P<email>[^\s\]]+)(\s+(?P<role>\w+))?(\s+(?P<tenant_id>[\w]+))?\] (?P<method>\w+) (?P<request_uri>\S+) (?P<status>\d+) (?P<response_time>[\d\.]+ms)$'
            - labels:
                level:
                app_name:
                status:
            - structured_metadata:
                remote_addr:
                email:
                tenant_id:
                response_time:
            - timestamp:
                source: timestamp
                format: RFC3339
      - match:
          selector: '{job="application"}'
          stages:
            - regex:
                expression: '^(?P<timestamp>\S+) \[(?P<level>\w+)\] (?P<app_name>[\w\-]+) (?P<service>[\w]+) -- (?P<message>.+)$'
            - labels:
                level:
                app_name:
                service:
            - timestamp:
                source: timestamp
                format: RFC3339
EOF

sudo chown -R promtail:promtail /etc/promtail
sudo chown -R promtail:promtail /var/lib/promtail

sudo usermod -a -G systemd-journal promtail
sudo usermod -a -G adm promtail

sudo tee /etc/systemd/system/promtail.service > /dev/null <<EOF
[Unit]
Description=Promtail Log Collector
Wants=network-online.target
After=network-online.target

[Service]
User=promtail
Group=promtail
Type=simple
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/config.yml
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl start promtail
sudo systemctl enable promtail

sudo systemctl status promtail

# journalctl -u promtail -f