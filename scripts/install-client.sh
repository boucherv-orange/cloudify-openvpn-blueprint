#!/bin/bash -e

sudo apt install -y openvpn

cd /home/cloud

wget http://$OPENVPN_SERVER_IP/vpnaccess.tar.bz2

tar -xvf vpnaccess.tar.bz2

sed -i "s/user nobody/user ubuntu/g" client.conf 

sudo sysctl -w net.ipv4.ip_forward=1

ctx instance runtime_properties ip $(ctx instance host_ip)
