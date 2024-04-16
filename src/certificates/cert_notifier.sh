#!/usr/bin/env bash
# /usr/local/bin/cert_notifier.sh
set -eo pipefail

now=$(date +%s)
last_update=$(date -r /root/ca/date_self_signed_certs.txt +%s || echo 0)
self_signed_age_s=$(( now - last_update ))
last_update=$(date -r /root/acme/date_acme_certs.txt +%s || echo 0)
acme_age_s=$(( now - last_update ))

recipient='{{ site.email }}'
from='{{ site.email }}'
mime='MIME-Version: 1.0\nContent-Type: text/html\n'

# 1 year
if (( self_signed_age_s > 31536000 )); then
  subject='Reminder: renew your self-signed certificates'
  body='<h1>Renew your self-signed certs!</h1>\n<p>Use this command on the PVE1 host:</p>\n<code>sudo /usr/local/bin/self_signed_cert_gen.sh</code>'
  echo -e "To: $recipient\nFrom: $from\nSubject: $subject\n$mime\n\n$body" | msmtp -t
  sleep 10
fi

# 2 months
if (( acme_age_s > 5184000 )); then
  subject='Reminder: renew your acme certificates'
  body='<h1>Renew your ACME certs!</h1>\n<p>Use this command on the PVE1 host:</p>\n<code>sudo /usr/local/bin/acme_transfer.sh</code>'
  echo -e "To: $recipient\nFrom: $from\nSubject: $subject\n$mime\n\n$body" | msmtp -t
fi
