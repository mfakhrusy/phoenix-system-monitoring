#!/usr/bin/env bash

set -e

VM_NAME=${1:-myvm}

uvt-kvm create "$VM_NAME" release=noble --memory=512 --cpu=1
