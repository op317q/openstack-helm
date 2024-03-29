#!/bin/bash

# Copyright 2017 The Openstack-Helm Authors.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
set -xe

#NOTE: Lint and package chart
: ${OSH_INFRA_PATH:="../openstack-helm-infra"}
make -C ${OSH_INFRA_PATH} openvswitch

tee /tmp/openvswitch.yaml << EOF
images:
  tags:
    openvswitch_db_server: docker.io/rihabbanday/openvswitch:latest-debian-dpdk
    openvswitch_vswitchd: docker.io/rihabbanday/openvswitch:latest-debian-dpdk
pod:
  resources:
    enabled: true
    ovs:
      vswitchd:
        requests:
          memory: "2Gi"
          cpu: "2"
        limits:
          memory: "2Gi"
          cpu: "2"
          hugepages-1Gi: "1Gi"
conf:
  dpdk:
    enabled: true
    hugepages_mountdir: /dev/hugepages
    socket_memory: 1024

EOF

#NOTE: Deploy command
: ${OSH_EXTRA_HELM_ARGS:=""}
helm upgrade --install openvswitch ${OSH_INFRA_PATH}/openvswitch \
  --namespace=openstack \
  --values=/tmp/openvswitch.yaml \
  --set manifests.network_policy=true \
  ${OSH_EXTRA_HELM_ARGS} \
  ${OSH_EXTRA_HELM_ARGS_OPENVSWITCH}

#NOTE: Wait for deploy
./tools/deployment/common/wait-for-pods.sh openstack

#NOTE: Validate Deployment info
helm status openvswitch
