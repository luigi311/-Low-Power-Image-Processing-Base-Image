#!/usr/bin/env bash

docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

BUILDX_BUILDERS=$(docker buildx ls)

# if multiarch does not exist, create it
if [[ $BUILDX_BUILDERS != *"multiarch"* ]]; then
    echo "Creating multiarch"
    docker buildx create --name multiarch --driver docker-container
fi

docker buildx use multiarch

docker buildx build --platform linux/amd64,linux/arm64 -t luigi311/low-power-image-processing-base-image:latest --push .
