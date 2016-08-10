#!/bin/bash

sudo apt install -y openvpn

wget http://$OPENVPN_SERVER_IP/vpnaccess.tar.bz2

tar -xvf vpnaccess.tar.bz2

sed -i "s/user nobody/user cloud/g" client.conf 

sudo sysctl -w net.ipv4.ip_forward=1