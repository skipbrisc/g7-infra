# G7 operations files

`taxglasses-deploy` is the source of `/usr/local/sbin/taxglasses-deploy` on G7
(root:root, 0755). Jenkins `TaxGlasses-Deploy` runs it as `jenkins-agent`; see
`docs/deploy.md` for the flow.

## Installing a change

From `D:\TaxGlasses-ops` in PowerShell, after the change is committed:

    scp g7/taxglasses-deploy g7-taxglasses:/tmp/taxglasses-deploy
    ssh -t g7-taxglasses "sudo -v && sudo diff -u /usr/local/sbin/taxglasses-deploy /tmp/taxglasses-deploy; sudo sh -n /tmp/taxglasses-deploy && sudo install -o root -g root -m 0755 /tmp/taxglasses-deploy /usr/local/sbin/taxglasses-deploy && rm -f /tmp/taxglasses-deploy && echo installed"

Read the diff before it installs. Do not install while a TaxGlasses-Deploy build is running.

## 51unattended-upgrades-java

Stops automatic updates from replacing Java under Jenkins (which made every build fail on
2026-10-28). Install:

    scp g7/51unattended-upgrades-java g7-taxglasses:/tmp/
    ssh -t g7-taxglasses "sudo -v && sudo install -o root -g root -m 0644 /tmp/51unattended-upgrades-java /etc/apt/apt.conf.d/51unattended-upgrades-java && rm -f /tmp/51unattended-upgrades-java && sudo apt-config dump >/dev/null && echo apt-config-ok"
