#!/bin/bash

apt install openvpn

wget http://84.39.46.78/vpnaccess.tar.bz2

tar -xvf vpnaccess.tar.bz2

sed -i "s/user nobody/user cloud/g" client.conf 

sysctl -w net.ipv4.ip_forward=1