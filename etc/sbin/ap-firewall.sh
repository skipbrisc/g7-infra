#!/bin/sh
# AP (192.168.4.0/24 on wlp0s20f3) NAT out via enp59s0 uplink
iptables -t nat -C POSTROUTING -s 192.168.4.0/24 -o enp59s0 -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -s 192.168.4.0/24 -o enp59s0 -j MASQUERADE
iptables -C FORWARD -i wlp0s20f3 -o enp59s0 -s 192.168.4.0/24 -j ACCEPT 2>/dev/null \
  || iptables -I FORWARD 1 -i wlp0s20f3 -o enp59s0 -s 192.168.4.0/24 -j ACCEPT
iptables -C FORWARD -i enp59s0 -o wlp0s20f3 -d 192.168.4.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null \
  || iptables -I FORWARD 1 -i enp59s0 -o wlp0s20f3 -d 192.168.4.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
