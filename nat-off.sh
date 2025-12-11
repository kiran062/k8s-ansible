#!/bin/bash
set -e

PRIVATE_ROUTE_TABLE_ID="rtb-08582cffdc2144575"

echo "Detecting active NAT Gateway..."
NAT_ID=$(aws ec2 describe-nat-gateways \
  --query "NatGateways[?State!='deleted'].NatGatewayId" \
  --output text)

if [[ -z "$NAT_ID" ]]; then
  echo "No active NAT Gateway found. Nothing to delete."
  exit 0
fi

echo "Found NAT Gateway: $NAT_ID"
echo "Removing 0.0.0.0/0 route from private route table: $PRIVATE_ROUTE_TABLE_ID ..."

aws ec2 delete-route \
  --route-table-id "$PRIVATE_ROUTE_TABLE_ID" \
  --destination-cidr-block 0.0.0.0/0 || true

echo "Deleting NAT Gateway..."
aws ec2 delete-nat-gateway --nat-gateway-id "$NAT_ID"

echo "Waiting for NAT Gateway to fully terminate..."
aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$NAT_ID"

echo "Fetching associated Elastic IP Allocation ID..."
ALLOC_ID=$(aws ec2 describe-nat-gateways \
  --nat-gateway-ids "$NAT_ID" \
  --query "NatGateways[0].NatGatewayAddresses[0].AllocationId" \
  --output text)

if [[ "$ALLOC_ID" == "None" || -z "$ALLOC_ID" ]]; then
  echo "Elastic IP already released or not found."
  exit 0
fi

echo "Releasing Elastic IP: $ALLOC_ID"
aws ec2 release-address --allocation-id "$ALLOC_ID"

echo "SUCCESS: NAT Gateway DISABLED and DELETED."
echo "Private subnet internet removed and Elastic IP released."
