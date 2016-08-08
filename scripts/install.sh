#!/bin/bash

sudo -s
echo "Preparing the instance to be ready to run with Heat..."
echo "######################################################"
echo ""
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -f -y -q install git python-setuptools ipcalc wget
apt-get -f -y -q install python-argparse cloud-init python-psutil python-pip
pip install 'boto==2.5.2' heat-cfntools
cfn-create-aws-symlinks -s /usr/local/bin/

echo "Installing and configuring OpenVPN..."
echo "###################################"
echo ""
apt-get -f -y -q install openvpn easy-rsa
# TODO: get the floating IP from heat and avoid the following HACK
# when http://docs.openstack.org/developer/heat/template_guide/
# will be a little bit more readable.
export FLOATING_IP=$(wget -q -O - checkip.dyndns.org|sed -e 's/.*Current IP Address: //' -e 's/<.*$//')
export OVPN_IP=$(ipcalc -nb 10.8.0.0/24 | grep ^Address | awk '{print $2}')
export OVPN_MASK=$(ipcalc -nb 10.8.0.0/24 | grep ^Netmask | awk '{print $2}')
export PRIVATE_IP_CIDR=$(ip addr show dev eth0 | grep 'inet .*$' | awk '{print $2}')
export PRIVATE_NETWORK_CIDR=$(ipcalc -nb $PRIVATE_IP_CIDR | grep ^Network | awk '{print $2}')
export PRIVATE_NETWORK_IP=$(ipcalc -nb $PRIVATE_NETWORK_CIDR | grep ^Address | awk '{print $2}')
export PRIVATE_NETWORK_MASK=$(ipcalc -nb $PRIVATE_NETWORK_CIDR | grep ^Netmask | awk '{print $2}')


cat > /etc/openvpn/route-up.sh <<EOF
#!/bin/bash
/sbin/sysctl -n net.ipv4.conf.all.forwarding > /var/log/openvpn/net.ipv4.conf.all.forwarding.bak
/sbin/sysctl net.ipv4.conf.all.forwarding=1
/sbin/iptables-save > /var/log/openvpn/iptables.save
/sbin/iptables -t nat -F
/sbin/iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j MASQUERADE
EOF

# Down script
cat > /etc/openvpn/down.sh <<EOF
#!/bin/bash
FORWARDING=\$(cat /var/log/openvpn/net.ipv4.conf.all.forwarding.bak)
echo "restoring net.ipv4.conf.all.forwarding=\$FORWARDING"
/sbin/sysctl net.ipv4.conf.all.forwarding=\$FORWARDING
/etc/openvpn/fw.stop
echo "Restoring iptables"
/sbin/iptables-restore < /var/log/openvpn/iptables.save
EOF

# Firewall stop script
cat > /etc/openvpn/fw.stop <<EOF
#!/bin/sh
echo "Stopping firewall and allowing everyone..."
/sbin/iptables -F
/sbin/iptables -X
/sbin/iptables -t nat -F
/sbin/iptables -t nat -X
/sbin/iptables -t mangle -F
/sbin/iptables -t mangle -X
/sbin/iptables -P INPUT ACCEPT
/sbin/iptables -P FORWARD ACCEPT
/sbin/iptables -P OUTPUT ACCEPT
EOF
chmod 755 /etc/openvpn/down.sh /etc/openvpn/route-up.sh /etc/openvpn/fw.stop

# OpenVPN server configuration
cat > /etc/openvpn/server.conf <<EOF
port 1194
proto udp
dev tun
ca /etc/openvpn/ca.crt
cert /etc/openvpn/server.crt
key /etc/openvpn/server.key
crl-verify /etc/openvpn/crl.pem
dh /etc/openvpn/dh2048.pem
server $OVPN_IP $OVPN_MASK
ifconfig-pool-persist ipp.txt
push "route $PRIVATE_NETWORK_IP $PRIVATE_NETWORK_MASK"
keepalive 10 120
tls-auth ta.key 0 # This file is secret
comp-lzo
persist-key
persist-tun
status /var/log/openvpn/openvpn-status.log
log /var/log/openvpn/openvpn.log
verb 3
script-security 2
route-up /etc/openvpn/route-up.sh
down /etc/openvpn/down.sh
EOF

# Sample configuration for client
cat > /tmp/openvpn.template <<EOF
client
dev tun
proto udp
remote $FLOATING_IP 1194
resolv-retry infinite
nobind
user nobody
group nogroup
persist-key
persist-tun
ca keys/ca.crt
cert keys/client.crt
key keys/client.key
ns-cert-type server
tls-auth keys/ta.key 1
comp-lzo
verb 3
EOF

mkdir /etc/openvpn/easy-rsa
cp -r /usr/share/easy-rsa /etc/openvpn/
cd /etc/openvpn/easy-rsa
ln -s openssl-1.0.0.cnf openssl.cnf
source vars
./clean-all
./build-dh
KEY_EMAIL=ca@openvpn ./pkitool --initca
KEY_EMAIL=server@pilgrim ./pkitool --server server
KEY_EMAIL=client@pilgrim ./pkitool client
KEY_EMAIL=revoked@pilgrim ./pkitool revoked
./revoke-full revoked  # Generates a crl.pem revocation list
openvpn --genkey --secret keys/ta.key
ln keys/{ca.crt,server.crt,server.key,dh2048.pem,crl.pem,ta.key} /etc/openvpn/
mv /tmp/openvpn.template ./client.conf
tar -cvjpf vpnaccess.tar.bz2 client.conf keys/ca.crt keys/client.key keys/client.crt keys/ta.key
cp vpnaccess.tar.bz2 /home/cloud/
chown cloud:cloud /home/cloud/vpnaccess.tar.bz2
mkdir -p /var/log/openvpn
service openvpn start