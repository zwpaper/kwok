#!/usr/bin/env bash
# Copyright 2023 The Kubernetes Authors.
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

DIR="$(dirname "${BASH_SOURCE[0]}")"

DIR="$(realpath "${DIR}")"

RELEASES=()

function usage() {
  echo "Usage: $0 <kube-version...>"
  echo "  <kube-version> is the version of kubernetes to test against."
}

function args() {
  if [[ $# -eq 0 ]]; then
    usage
    exit 1
  fi
  while [[ $# -gt 0 ]]; do
    RELEASES+=("${1}")
    shift
  done
}

function show_info() {
    local name="${1}"
    echo kwokctl get clusters
    kwokctl get clusters
    echo
    echo kwokctl --name="${name}" kubectl get pod -o wide --all-namespaces
    kwokctl --name="${name}" kubectl get pod -o wide --all-namespaces
    echo
    echo kwokctl --name="${name}" logs etcd
    kwokctl --name="${name}" logs etcd
    echo
    echo kwokctl --name="${name}" logs kube-apiserver
    kwokctl --name="${name}" logs kube-apiserver
    echo
    echo kwokctl --name="${name}" logs kube-controller-manager
    kwokctl --name="${name}" logs kube-controller-manager
    echo
    echo kwokctl --name="${name}" logs kube-scheduler
    kwokctl --name="${name}" logs kube-scheduler
    echo
}

function test_create_cluster() {
  local release="${1}"
  local name="${2}"

  KWOK_KUBE_VERSION="${release}" kwokctl -v=-4 create cluster --name "${name}" --timeout 10m --wait 10m --quiet-pull --kube-scheduler-config="${DIR}/scheduler-config.yaml"
  if [[ $? -ne 0 ]]; then
    echo "Error: Cluster ${name} creation failed"
    exit 1
  fi
}

function test_delete_cluster() {
  local release="${1}"
  local name="${2}"
  kwokctl delete cluster --name "${name}"
}

function test_scheduler() {
  local release="${1}"
  local name="${2}"

  for ((i = 0; i < 30; i++)); do
    kwokctl --name "${name}" kubectl apply -f "${DIR}/fake-node.yaml"
    if kwokctl --name="${name}" kubectl get node | grep Ready >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  for ((i = 0; i < 30; i++)); do
    kwokctl --name "${name}" kubectl apply -f "${DIR}/fake-scheduler-deployment.yaml"
    if kwokctl --name="${name}" kubectl get pod | grep Running >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if ! kwokctl --name="${name}" kubectl get pod | grep Running >/dev/null 2>&1; then
    echo "Error: cluster not ready"
    show_info "${name}"
    return 1
  fi
}

function main() {
  local failed=()
  for release in "${RELEASES[@]}"; do
    echo "------------------------------"
    echo "Testing scheduler on ${KWOK_RUNTIME} for ${release}"
    name="scheduler-cluster-${KWOK_RUNTIME}-${release//./-}"
    test_create_cluster "${release}" "${name}" || failed+=("create_cluster_${name}")
    test_scheduler "${release}" "${name}" || failed+=("scheduler_${name}")
    test_delete_cluster "${release}" "${name}" || failed+=("delete_cluster_${name}")
  done

  if [[ "${#failed[@]}" -ne 0 ]]; then
    echo "------------------------------"
    echo "Error: Some tests failed"
    for test in "${failed[@]}"; do
      echo " - ${test}"
    done
    exit 1
  fi
}

args "$@"

main
