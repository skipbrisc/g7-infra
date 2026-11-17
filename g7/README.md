# G7 operations files

`taxglasses-deploy` is the source of `/usr/local/sbin/taxglasses-deploy` on G7
(root:root, 0755). Jenkins `TaxGlasses-Deploy` runs it as `jenkins-agent`; see
`docs/deploy.md` for the flow.

## Installing a change

Commit the change in `D:\g7-infra`, `git push g7 main`, then:

    ssh -t g7 "sudo g7-apply"

It shows the diff, checks the script's syntax, and installs it when you type `yes`. It refuses
while a deploy is running (`g7/apply/README.md`).

## Release history

`promote` and `rollback` tag the commit they put live in G7's TaxGlasses repository, written
as the `git` user: `live-<date>-<time>-<sha8>` and `rollback-<date>-<time>-<sha8>`, Pacific
time. The GitHub mirror copies the tags within a minute. A tag that cannot be written is
logged and sends one low-priority ntfy alert on `taxglasses` (with `/root/.ntfy-g7-token`);
the deploy itself is never failed or undone by it. On the PC:

    git fetch g7 --tags
    git tag -l --sort=-creatordate -n1 "live-*" "rollback-*"

## 51unattended-upgrades-java

Stops automatic updates from replacing Java under Jenkins (which made every build fail on
2026-10-28). Install:

    scp g7/51unattended-upgrades-java g7-taxglasses:/tmp/
    ssh -t g7-taxglasses "sudo -v && sudo install -o root -g root -m 0644 /tmp/51unattended-upgrades-java /etc/apt/apt.conf.d/51unattended-upgrades-java && rm -f /tmp/51unattended-upgrades-java && sudo apt-config dump >/dev/null && echo apt-config-ok"
