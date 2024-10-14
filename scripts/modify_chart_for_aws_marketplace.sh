#!/bin/bash

FILE="./stable/rad-plugins/values.yaml"

SOURCE_REGISTRY_NAME="public.ecr.aws/n8h5y2v5/rad-security"
ECR_PUBLIC_REGISTRY="public.ecr.aws/eks-distro/kubernetes"

ECR_REGISTRY_NAME="709825985650.dkr.ecr.us-east-1.amazonaws.com/rad-security"

sed -i "s|$ECR_PUBLIC_REGISTRY|$ECR_REGISTRY_NAME|g" "$FILE"
sed -i "s|$SOURCE_REGISTRY_NAME|$ECR_REGISTRY_NAME|g" "$FILE"
sed -i '/# --/d' "$FILE"

yq e -i '.eksAddon.enabled = true' $FILE

rm ./stable/rad-plugins/templates/access-key-secret.yaml
