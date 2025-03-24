#!/bin/bash

set -e

if [ $# -lt 1 ]; then
    echo "Usage: ./deploy.sh <subdomain> [image_tag]"
    exit 1
fi

./run_stack_command.sh create-stack "$1" "$2"
