#!/usr/bin/env bash
. ~/.bashrc
if [ ! $AGORIC_NODENAME ]; then
	read -p "Enter node name: " AGORIC_NODENAME
	echo 'export AGORIC_NODENAME='$AGORIC_NODENAME >> $HOME/.bashrc
	. ~/.bashrc
fi

echo 'Your node name: ' $AGORIC_NODENAME
sleep 2
sudo dpkg --configure -a
sudo apt update
sudo apt install curl -y < "/dev/null"
sleep 1
wget -O nodesgurulogo https://api.nodes.guru/logo.sh
chmod +x nodesgurulogo
./nodesgurulogo
sleep 3

curl https://deb.nodesource.com/setup_12.x | sudo bash
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt upgrade -y < "/dev/null"
sudo apt install nodejs=12.* yarn build-essential jq git -y < "/dev/null"
sleep 1

sudo rm -rf /usr/local/go
curl https://dl.google.com/go/go1.15.7.linux-amd64.tar.gz | sudo tar -C/usr/local -zxvf -
cat <<'EOF' >> $HOME/.bash_profile
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export GO111MODULE=on
export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
EOF
. $HOME/.bash_profile
cp /usr/local/go/bin/go /usr/bin
go version

export GIT_BRANCH=agorictest-8
git clone https://github.com/Agoric/agoric-sdk -b $GIT_BRANCH
(cd agoric-sdk && npm --force install -g yarn && yarn install && yarn build)
. $HOME/.bashrc
(cd $HOME/agoric-sdk/packages/cosmic-swingset && make)
cd $HOME/agoric-sdk

curl https://testnet.agoric.net/network-config > chain.json
chainName=`jq -r .chainName < chain.json`
echo $chainName

ag-chain-cosmos init --chain-id $chainName $AGORIC_NODENAME
curl https://testnet.agoric.net/genesis.json > $HOME/.ag-chain-cosmos/config/genesis.json 
ag-chain-cosmos unsafe-reset-all
peers=$(jq '.peers | join(",")' < chain.json)
seeds=$(jq '.seeds | join(",")' < chain.json)
echo $peers
echo $seeds
sed -i.bak 's/^log_level/# log_level/' $HOME/.ag-chain-cosmos/config/config.toml
sed -i.bak -e "s/^seeds *=.*/seeds = $seeds/; s/^persistent_peers *=.*/persistent_peers = $peers/" $HOME/.ag-chain-cosmos/config/config.toml
sudo tee <<EOF >/dev/null /etc/systemd/system/ag-chain-cosmos.service
[Unit]
Description=Agoric Cosmos daemon
After=network-online.target

[Service]
User=$USER
ExecStart=$HOME/go/bin/ag-chain-cosmos start --log_level=warn
Restart=on-failure
RestartSec=3
LimitNOFILE=10000
Environment="OTEL_EXPORTER_PROMETHEUS_PORT="$OTEL_EXPORTER_PROMETHEUS_PORT

[Install]
WantedBy=multi-user.target
EOF
echo 'export OTEL_EXPORTER_PROMETHEUS_PORT=9464' >> $HOME/.bashrc
. ~/.bashrc
sed -i '/\[telemetry\]/{:a;n;/enabled/s/false/true/;Ta};/\[api\]/{:a;n;/enable/s/false/true/;Ta;}' $HOME/.ag-chain-cosmos/config/app.toml
sed -i "s/prometheus-retention-time = 0/prometheus-retention-time = 60/g" $HOME/.ag-chain-cosmos/config/app.toml
sed -i "s/prometheus = false/prometheus = true/g" $HOME/.ag-chain-cosmos/config/config.toml
sudo systemctl enable ag-chain-cosmos
sudo systemctl daemon-reload
sudo systemctl start ag-chain-cosmos
echo 'Metrics URL: http://'$(curl -s ifconfig.me)':9464/metrics'
echo 'Metric link will work after sync'
echo 'Node status:'$(sudo service ag-chain-cosmos status | grep active)
