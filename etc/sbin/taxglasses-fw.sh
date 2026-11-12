#!/bin/sh
set -e
PATH=/usr/sbin:/usr/bin:/sbin:/bin
P=10.77.0.20/31

# Dedicated chain for the two TaxGlasses peers
iptables -N TG-WG 2>/dev/null || iptables -F TG-WG
iptables -A TG-WG -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A TG-WG -p tcp -m conntrack --ctorigdst 10.77.0.1 --ctorigdstport 8090 -j ACCEPT
iptables -A TG-WG -j DROP

# Always pin the peer jump at the top of DOCKER-USER
while iptables -D DOCKER-USER -s $P -j TG-WG 2>/dev/null; do :; done
iptables -I DOCKER-USER 1 -s $P -j TG-WG

# Always pin the host block at the top of INPUT
while iptables -D INPUT -i wg0 -s $P -j DROP 2>/dev/null; do :; done
iptables -I INPUT 1 -i wg0 -s $P -j DROP

# Frank (10.77.0.32): internet + 192.168.0.100 only
F=10.77.0.32
iptables -N WG-FRANK 2>/dev/null || iptables -F WG-FRANK
iptables -A WG-FRANK -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A WG-FRANK -d 192.168.0.100 -j ACCEPT
iptables -A WG-FRANK -d 10.0.0.0/8 -j DROP
iptables -A WG-FRANK -d 172.16.0.0/12 -j DROP
iptables -A WG-FRANK -d 192.168.0.0/16 -j DROP
iptables -A WG-FRANK -d 169.254.0.0/16 -j DROP
iptables -A WG-FRANK -d 100.64.0.0/10 -j DROP
iptables -A WG-FRANK -o enp59s0 -j ACCEPT
iptables -A WG-FRANK -j DROP
while iptables -D DOCKER-USER -s $F -j WG-FRANK 2>/dev/null; do :; done
iptables -I DOCKER-USER 1 -s $F -j WG-FRANK
while iptables -D INPUT -i wg0 -s $F -j DROP 2>/dev/null; do :; done
iptables -I INPUT 1 -i wg0 -s $F -j DROP

# Will (10.77.0.31): internet + LAN, but nothing on G7 itself
W=10.77.0.31
iptables -N WG-WILL 2>/dev/null || iptables -F WG-WILL
iptables -A WG-WILL -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A WG-WILL -d 172.16.0.0/12 -j DROP
iptables -A WG-WILL -d 10.77.0.0/24 -j DROP
iptables -A WG-WILL -o enp59s0 -j ACCEPT
iptables -A WG-WILL -j DROP
while iptables -D DOCKER-USER -s $W -j WG-WILL 2>/dev/null; do :; done
iptables -I DOCKER-USER 1 -s $W -j WG-WILL
while iptables -D INPUT -i wg0 -s $W -j DROP 2>/dev/null; do :; done
iptables -I INPUT 1 -i wg0 -s $W -j DROP
