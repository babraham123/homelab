
  install_postgres)
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh postgres
    ;;
  install_lldap)
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh lldap
    ;;
  install_authelia)
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh authelia
    ;;
  install_traefik)
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh traefik
    ;;
  install_victoriametrics)
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh victoriametrics
    ;;
  install_victorialogs)
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh victorialogs
    ;;
  install_alertmanager)
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh alertmanager
    ;;
  install_gatus)
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh gatus
    ;;
  install_vmalert)
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh vmalert
    ;;
  install_grafana)
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh grafana
    ;;
  install_ntfy)
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh ntfy
    ;;
  install_ntfy-alertmanager)
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh ntfy-alertmanager
    ;;
  install_olive_tin)
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh olive_tin
    ;;
  install_fluentbit)
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh fluentbit
    ;;
  install_all_svcs)
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh postgres
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh lldap
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh authelia
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh traefik
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh victoriametrics
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh victorialogs
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh alertmanager
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh gatus
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh vmalert
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh grafana
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh ntfy
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh ntfy-alertmanager
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh olive_tin
    sudo /root/homelab-rendered/src/nodes/secsvcs/install_svcs.sh fluentbit
    ;;
