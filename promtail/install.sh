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

  - job_name: application
    static_configs:
      - targets:
          - localhost
        labels:
          job: application
          host: $(hostname)
          __path__: /home/ubuntu/photobooth-manager/logs/*.log
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