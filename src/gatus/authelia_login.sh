#!/usr/bin/env bash
# /etc/opt/gatus/authelia_login.sh
# Ref:
# https://github.com/TwiN/gatus?tab=readme-ov-file#reloading-configuration-on-the-fly
# https://www.authelia.com/configuration/security/access-control/#rule-matching-concept-2-subject-criteria-requires-authentication
# https://auth.{{ site.url }}/api/#/

set -euo pipefail
finish=0
trap 'finish=1' SIGTERM

export AUTH_COOKIE=""
test_url="https://ldap.{{ site.url }}"
last_health=""
last_status=""
last_login=""

echo "Gatus login automator is starting..."
while (( finish != 1 ))
do
  health_status=$(curl -s -o /dev/null -w "%{response_code}" --connect-timeout 10 -X GET https://auth.{{ site.url }}/api/health)
  if [[ $health_status == 200 ]]; then
    # Authelia is up

    test_status=$(curl -s -o /dev/null -w "%{response_code}" --connect-timeout 10 -X GET -H "cookie: $AUTH_COOKIE" $test_url)
    if [[ $test_status == 200 ]]; then
      # Gatus is logged in
      true
    elif [[ $test_status == 302 ]]; then
      # Gatus is not logged in

      # shellcheck disable=SC2155
      export AUTH_COOKIE=$(curl -s -o /tmp/login_status -w "%header{set-cookie}" --connect-timeout 10 -X POST -H "Content-Type: application/json" -d '{"username":"gatus","password":"'"$LDAP_PASSWORD"'","keepMeLoggedIn": true}' https://auth.{{ site.url }}/api/firstfactor)
      login_status=$(cat /tmp/login_status)

      if grep -q '"status":"OK"' /tmp/login_status; then
        # Trigger Gatus to reload the configuration
        touch /config/config.yaml
        echo "Automator successfully logged in"
      else
        if [[ $login_status != "$last_login" ]]; then
          echo "Automator login failed: $login_status"
        fi
      fi
      last_login=$login_status
    elif [[ $test_status == 000 ]]; then
      if [[ $test_status != "$last_status" ]]; then
        echo "Automator test URL is down: $test_url"
      fi
    else
      if [[ $test_status != "$last_status" ]]; then
        echo "Automator login test failed with an unexpected status code: $test_status"
      fi
    fi
    last_status=$test_status
  else
    if [[ $health_status != "$last_health" ]]; then
        echo "Automator, Authelia is down, status code: $health_status"
      fi
  fi
  last_health=$health_status

  sleep 60
done
echo "Gatus login automator has stopped."
