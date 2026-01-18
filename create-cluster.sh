#!/bin/bash
# Create EKS cluster using eksctl

eksctl create cluster \
  --name k8s-persistence-lab \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3 \
  --managed