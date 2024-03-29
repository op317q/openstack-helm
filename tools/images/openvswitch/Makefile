# Copyright 2017 The Openstack-Helm Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# It's necessary to set this because some environments don't link sh -> bash.
SHELL := /bin/bash

DOCKER_REGISTRY            ?= docker.io
IMAGE_NAME                 ?= openvswitch
IMAGE_PREFIX               ?= openstackhelm
OVS_VERSION                ?= 2.8.1
IMAGE_TAG                  ?= latest-debian
LABEL                      ?= putlabelshere

IMAGE := ${DOCKER_REGISTRY}/${IMAGE_PREFIX}/${IMAGE_NAME}:${IMAGE_TAG}

# Build openvswitch Docker image for this project
.PHONY: images
images: build_$(IMAGE_NAME)

# Make targets intended for use by the primary targets above.
.PHONY: build_$(IMAGE_NAME)
build_$(IMAGE_NAME):
	docker build \
	--network=host \
	--build-arg OVS_VERSION=$(OVS_VERSION) \
	--label $(LABEL) \
	-t $(IMAGE) \
	.
