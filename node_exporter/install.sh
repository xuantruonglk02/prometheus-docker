#!/bin/bash

wget https://github.com/prometheus/node_exporter/releases/download/v1.10.2/node_exporter-1.10.2.linux-amd64.tar.gz
tar xvfz node_exporter-*.*-amd64.tar.gz

sudo cp node_exporter-1.10.2.linux-amd64/node_exporter /usr/local/bin/

rm -rf node_exporter-1.10.2.linux-amd64*

sudo useradd --no-create-home --shell /bin/false node_exporter
sudo groupadd node_exporter
sudo usermod -g node_exporter node_exporter

sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter \
  --collector.systemd \
  --collector.processes \
  --collector.diskstats \
  --collector.filesystem \
  --collector.netdev

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reexec
sudo systemctl start node_exporter
sudo systemctl enable node_exporter

sudo systemctl status node_exporter

# journalctl -u node_exporter -f

sudo htpasswd -c /etc/nginx/.htpasswd node_exporter
   
sudo tee /etc/nginx/sites-available/node_exporter > /dev/null <<'EOF'
server {
    listen 80;
    server_name domain;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name domain;

    ssl_certificate /etc/ssl/cloudflare/cert.pem;
    ssl_certificate_key /etc/ssl/cloudflare/key.pem;

    location / {
        auth_basic "Node Exporter";
        auth_basic_user_file /etc/nginx/.htpasswd;

        proxy_pass http://127.0.0.1:9100;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/node_exporter /etc/nginx/sites-enabled/

sudo systemctl restart nginx

sudo ufw allow 9100/tcp