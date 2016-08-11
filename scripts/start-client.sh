#!/bin/bash -e

cd /home/cloud

sudo nohup openvpn --config client.conf > /dev/null 2>&1 &
