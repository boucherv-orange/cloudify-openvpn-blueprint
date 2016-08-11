#!/bin/bash

cd /home/cloud

nohup openvpn --config client.conf > /dev/null 2>&1 &
