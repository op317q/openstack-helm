#!/bin/bash

{{/*
Copyright 2017 The Openstack-Helm Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/}}

set -ex

chown neutron: /run/openvswitch/db.sock

OVS_SOCKET=/run/openvswitch/db.sock

function bind_nic {
  echo $2 > /sys/bus/pci/devices/$1/driver_override
  echo $1 > /sys/bus/pci/drivers/$2/bind
}

function unbind_nic {
  echo $1 > /sys/bus/pci/drivers/$2/unbind
  echo > /sys/bus/pci/devices/$1/driver_override
}

function get_name_by_pci_id {
  path=$(find /sys/bus/pci/devices/$1/ -name net)
  if [ -n "${path}" ] ; then
    echo $(ls -1 $path/)
  fi
}

function get_ip_address_from_interface {
  local interface=$1
  local ip=$(ip a s ${interface} | grep 'inet ' | awk '{print $2}' | awk -F "/" '{print $1}')
  if [ -z "${ip}" ] ; then
    echo "Interface ${interface} has no valid IP address."
    exit 1
  fi
  echo ${ip}
}

function get_ip_prefix_from_interface {
  local interface=$1
  local prefix=$(ip a s ${interface} | grep 'inet ' | awk '{print $2}' | awk -F "/" '{print $2}')
  if [ -z "${prefix}" ] ; then
    echo "Interface ${interface} has no valid IP address."
    exit 1
  fi
  echo ${prefix}
}

function bind_dpdk_nics {
  target_driver={{ .Values.conf.ovs_dpdk.driver }}
  {{- range .Values.conf.ovs_dpdk.nics }}

    #
    # handle NIC {{ .pci_id }}
    #
    migrateIP=.migrate_ip
    echo "1stmigrateIP = ${migrateIP}"
    echo "2nd.migrate_ip = ${.migrate_ip}"
    echo "3rd.migrate_ip = .migrate_ip"
    {{ if and .migrate_ip (eq .migrate_ip true)}}
      echo "entering into migrate_ip if loop
      name=$(get_name_by_pci_id {{ .pci_id | quote }})
      if [ -n "${name}" ] ; then
        ip=$(get_ip_address_from_interface ${name})
        prefix=$(get_ip_prefix_from_interface ${name})

        # Enabling explicit error handling: We must avoid to lose the IP
        # address in the migration process. Hence, on every error, we
        # attempt to assign the IP back to the original NIC and exit.
        set +e
        ip addr flush dev ${name}
        if [ $? -ne 0 ] ; then
          ip addr add ${ip}/${prefix} dev ${name}
          echo "Error while flushing IP from ${name}."
          exit 1
        fi

        bridge=$(ip a s {{ .bridge | quote }} 2> /dev/null)
        if [ -z "${bridge}" ] ; then
          echo "Bridge {{ .bridge }} does not exist. Creating it on demand."
          init_ovs_dpdk_bridge {{ .bridge | quote }}
        fi

        ip addr add ${ip}/${prefix} dev {{ .bridge | quote }}
        if [ $? -ne 0 ] ; then
          echo "Error assigning IP to bridge {{ .bridge }}."
          ip addr add ${ip}/${prefix} dev ${name}
          exit 1
        fi
        set -e
      fi
    {{- end }}

    current_driver="$(get_driver_by_address {{ .pci_id | quote }} )"
    if [ "$current_driver" != "$target_driver" ]; then
      if [ "$current_driver" != "" ]; then
        unbind_nic {{ .pci_id | quote }} $current_driver
      fi
      bind_nic {{ .pci_id | quote }} $target_driver
    fi

    ovs-vsctl --db=unix:${OVS_SOCKET} --if-exists del-port {{ .name | quote }}

    dpdk_options=""
    {{- if .ofport_request }}
      dpdk_options+='ofport_request={{ .ofport_request }} '
    {{- end }}
    {{- if .n_rxq }}
      dpdk_options+='options:n_rxq={{ .n_rxq }} '
    {{- end }}
    {{- if .pmd_rxq_affinity }}
      dpdk_options+='other_config:pmd-rxq-affinity={{ .pmd_rxq_affinity }} '
    {{- end }}

    ovs-vsctl --db=unix:${OVS_SOCKET} --may-exist add-port {{ .bridge | quote }} {{ .name | quote}} \
       -- set Interface {{ .name }} type=dpdk options:dpdk-devargs={{ .pci_id | quote }} ${dpdk_options}
  {{- end }}
}

function get_driver_by_address {
  if [[ -e /sys/bus/pci/devices/$1/driver ]]; then
    echo $(ls /sys/bus/pci/devices/$1/driver -al | awk '{n=split($NF,a,"/"); print a[n]}')
  fi
}

function init_ovs_dpdk_bridge {
  bridge=$1
  ovs-vsctl --db=unix:${OVS_SOCKET} --may-exist add-br ${bridge} \
  -- set Bridge ${bridge} datapath_type=netdev
  ip link set ${bridge} up
}

# create all additional bridges defined in the DPDK section
function init_ovs_dpdk_bridges {
  {{- range .Values.conf.ovs_dpdk.bridges }}
    init_ovs_dpdk_bridge {{ .name | quote }}
  {{- end }}
}


# FIXME(portdirect): There is a neutron bug in Queens that needs resolved
# for now, if we cannot even get the version of neutron-sanity-check, skip
# this validation.
# see: https://bugs.launchpad.net/neutron/+bug/1769868
if neutron-sanity-check --version >/dev/null 2>/dev/null; then
  # ensure we can talk to openvswitch or bail early
  # this is until we can setup a proper dependency
  # on deaemonsets - note that a show is not sufficient
  # here, we need to communicate with both the db and vswitchd
  # which means we need to do a create action
  #
  # see https://github.com/att-comdev/openstack-helm/issues/88
  timeout 3m neutron-sanity-check --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/openvswitch_agent.ini --ovsdb_native --nokeepalived_ipv6_support
fi

# handle any bridge mappings
# /tmp/auto_bridge_add is one line json file: {"br-ex1":"eth1","br-ex2":"eth2"}
for bmap in `sed 's/[{}"]//g' /tmp/auto_bridge_add | tr "," "\n"`
do
  bridge=${bmap%:*}
  iface=${bmap#*:}
  echo "Adding bridge ${bridge}."
  ovs-vsctl --no-wait --may-exist add-br $bridge
  if [ -n "$iface" ] && [ "$iface" != "null" ]
  then
    ovs-vsctl --no-wait --may-exist add-port $bridge $iface
    ip link set dev $iface up
  fi
done

tunnel_interface="{{- .Values.network.interface.tunnel -}}"
echo "Adding tunnel_interface ${tunnel_interface}."
if [ -z "${tunnel_interface}" ] ; then
    # search for interface with tunnel network routing
    tunnel_network_cidr="{{- .Values.network.interface.tunnel_network_cidr -}}"
    if [ -z "${tunnel_network_cidr}" ] ; then
        tunnel_network_cidr="0/0"
    fi
    # If there is not tunnel network gateway, exit
    tunnel_interface=$(ip -4 route list ${tunnel_network_cidr} | awk -F 'dev' '{ print $2; exit }' \
        | awk '{ print $1 }') || exit 1
fi

{{- if .Values.conf.ovs_dpdk.enabled }}
init_ovs_dpdk_bridges
bind_dpdk_nics
{{- end }}

# determine local-ip dynamically based on interface provided but only if tunnel_types is not null
LOCAL_IP=$(get_ip_address_from_interface ${tunnel_interface})
if [ -z "${LOCAL_IP}" ] ; then
  echo "Var LOCAL_IP is empty"
  exit 1
fi

tee > /tmp/pod-shared/ml2-local-ip.ini << EOF
[ovs]
local_ip = "${LOCAL_IP}"
EOF

