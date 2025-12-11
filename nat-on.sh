#!/bin/bash
set -e

PUBLIC_SUBNET_ID="subnet-06fd9f68778c6ccc5"
PRIVATE_ROUTE_TABLE_ID="rtb-08582cffdc2144575"
EIP_ALLOC_ID="eipalloc-087ab2fd1beb62b6e"

echo "Using your existing Elastic IP Allocation ID: $EIP_ALLOC_ID"

echo "Creating NAT Gateway in public subnet: $PUBLIC_SUBNET_ID ..."

NAT_ID=$(aws ec2 create-nat-gateway \
  --subnet-id "$PUBLIC_SUBNET_ID" \
  --allocation-id "$EIP_ALLOC_ID" \
  --tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=MyNATGateway}]' \
  --query 'NatGateway.NatGatewayId' \
  --output text)

echo "NAT Gateway created: $NAT_ID"
echo "Waiting for NAT Gateway to become AVAILABLE (~60 seconds)..."

aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_ID"

echo "Adding route for Internet access in private route table: $PRIVATE_ROUTE_TABLE_ID"

aws ec2 create-route \
  --route-table-id "$PRIVATE_ROUTE_TABLE_ID" \
  --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id "$NAT_ID" || \
aws ec2 replace-route \
  --route-table-id "$PRIVATE_ROUTE_TABLE_ID" \
  --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id "$NAT_ID"

echo "SUCCESS: NAT Gateway ENABLED."
echo "Private EC2 instances now have internet access."
echo "NAT Gateway ID: $NAT_ID"
