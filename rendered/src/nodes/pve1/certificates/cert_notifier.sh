#!/bin/bash
# Check when the SSH, self-signed and ACME cert upgrade scripts were last run.
# If those certs are in danger of expiring, send an email to the site owner.
# Usage:
#   /usr/local/bin/cert_notifier.sh

# shellcheck source=src/base/lib.sh
source /usr/local/lib/homelab/lib.sh
set +u

now=$(date +%s)
last_update=$(date -r /root/ssh/date_ssh_certs.txt +%s || echo 0)
ssh_age_s=$(( now - last_update ))
last_update=$(date -r /root/ssh/date_ssh_certs_windows.txt +%s || echo 0)
ssh_windows_age_s=$(( now - last_update ))
last_update=$(date -r /root/ca/date_self_signed_certs.txt +%s || echo 0)
self_signed_age_s=$(( now - last_update ))
last_update=$(date -r /root/acme/date_acme_certs.txt +%s || echo 0)
acme_age_s=$(( now - last_update ))

recipient='jdoe+cert@gmail.com'
from='Cert Notifier <admin@janedoe.com>'
mime='MIME-Version: 1.0\nContent-Type: text/html\n'

# 1 year
if (( ssh_age_s > 31536000 )); then
  subject='Reminder: renew your SSH certificates'
  body='<h1>Renew your SSH certs!</h1>\n<p>Use this command on the PVE1 host:</p>\n<code>sudo /root/homelab-rendered/src/nodes/pve1/certificates/ssh_cert_gen.sh</code>'
  echo -e "To: $recipient\nFrom: $from\nSubject: $subject\n$mime\n\n$body" | msmtp -t
  sleep 10
fi

# 1 year
if (( ssh_windows_age_s > 31536000 )); then
  subject='Reminder: renew your Windows SSH certificates'
  body='<h1>Renew your Windows SSH certs!</h1>\n<p>Use this command on the PVE1 host:</p>\n<code>sudo /root/homelab-rendered/src/nodes/pve1/certificates/ssh_cert_gen_windows.sh</code>'
  echo -e "To: $recipient\nFrom: $from\nSubject: $subject\n$mime\n\n$body" | msmtp -t
  sleep 10
fi

# 1 year
if (( self_signed_age_s > 31536000 )); then
  subject='Reminder: renew your self-signed certificates'
  body='<h1>Renew your self-signed certs!</h1>\n<p>Use this command on the PVE1 host:</p>\n<code>sudo /root/homelab-rendered/src/nodes/pve1/certificates/self_signed_cert_gen.sh</code>'
  echo -e "To: $recipient\nFrom: $from\nSubject: $subject\n$mime\n\n$body" | msmtp -t
  sleep 10
fi

# 3 weeks: the weekly backup run installs them, and one week can be skipped
if (( acme_age_s > 1814400 )); then
  subject='Reminder: install your acme certificates'
  body='<h1>The backup run has not installed the ACME certs in 3 weeks!</h1>\n<p>See <code>journalctl -u backup_orchestrator</code>, or use this command on the PVE1 host:</p>\n<code>sudo /root/homelab-rendered/src/nodes/pve1/certificates/acme_transfer.sh</code>'
  echo -e "To: $recipient\nFrom: $from\nSubject: $subject\n$mime\n\n$body" | msmtp -t
fi
