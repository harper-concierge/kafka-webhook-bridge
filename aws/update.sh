#!/bin/bash

set -e

if [ $# -lt 1 ]; then
    echo "Usage: ./update.sh <subdomain> [image_tag]"
    exit 1
fi

./run_stack_command.sh update-stack "$1" "$2"
