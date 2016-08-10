#!/bin/bash

nohup openvpn --config client.conf > /dev/null 2>&1 &
