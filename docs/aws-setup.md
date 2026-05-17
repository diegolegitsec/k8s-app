# AWS Setup — EKS

## Prerequisites

- AWS CLI configured (`aws configure`)
- `eksctl` installed: https://eksctl.io/installation/
- `kubectl` installed
- `docker` installed

## 1. Create EKS Cluster

```bash
eksctl create cluster \
  --name k8s-app \
  --region us-east-1 \
  --nodegroup-name workers \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3 \
  --managed
```

This takes ~15 minutes. It also updates your kubeconfig automatically.

## 2. Install EBS CSI Driver

Required for dynamic EBS volume provisioning (Redis persistent storage).

```bash
# Create the IAM role for the EBS CSI driver
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster k8s-app \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve

# Get the role ARN
ROLE_ARN=$(aws iam get-role --role-name AmazonEKS_EBS_CSI_DriverRole \
  --query 'Role.Arn' --output text)

# Install the addon
eksctl create addon \
  --name aws-ebs-csi-driver \
  --cluster k8s-app \
  --service-account-role-arn $ROLE_ARN \
  --force
```

## 3. Create ECR Repositories

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1

aws ecr create-repository --repository-name k8s-app/backend  --region $REGION
aws ecr create-repository --repository-name k8s-app/frontend --region $REGION
```

## 4. Build and Push Images to ECR

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
ECR=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com

# Authenticate
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $ECR

# Build and push backend
docker build -t $ECR/k8s-app/backend:latest ./backend
docker push $ECR/k8s-app/backend:latest

# Build and push frontend
docker build -t $ECR/k8s-app/frontend:latest ./frontend
docker push $ECR/k8s-app/frontend:latest
```

## 5. Update Image References in AWS Manifests

Replace the placeholder values in the AWS deployment files:

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1

sed -i '' \
  "s|<AWS_ACCOUNT_ID>|$ACCOUNT|g; s|<REGION>|$REGION|g" \
  k8s/aws/backend/deployment.yaml \
  k8s/aws/frontend/deployment.yaml
```

## 6. Deploy

```bash
# StorageClass and Namespace
kubectl apply -f k8s/aws/storageclass.yaml
kubectl apply -f k8s/local/namespace.yaml   # namespace is environment-agnostic

# Redis
kubectl apply -f k8s/aws/redis/pvc.yaml
kubectl apply -f k8s/aws/redis/deployment.yaml
kubectl apply -f k8s/aws/redis/service.yaml

# Backend
kubectl apply -f k8s/aws/backend/configmap.yaml
kubectl apply -f k8s/aws/backend/deployment.yaml
kubectl apply -f k8s/aws/backend/service.yaml

# Frontend
kubectl apply -f k8s/aws/frontend/deployment.yaml
kubectl apply -f k8s/aws/frontend/service.yaml
```

## 7. Get the App URL

```bash
kubectl rollout status deployment/frontend -n k8s-app

kubectl get svc frontend-service -n k8s-app
# EXTERNAL-IP column shows the NLB DNS name (may take 1-2 min to provision)
```

Access the app at `http://<NLB-DNS>`.

## 8. Verify

```bash
NLB=$(kubectl get svc frontend-service -n k8s-app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl http://$NLB/api/health
curl http://$NLB/api/entries
```

## 9. Tear Down

```bash
# Delete K8s resources (this also releases the EBS volume if reclaimPolicy is Delete)
kubectl delete namespace k8s-app
kubectl delete storageclass ebs-gp3

# Delete EKS cluster
eksctl delete cluster --name k8s-app --region us-east-1

# Delete ECR repositories (optional)
aws ecr delete-repository --repository-name k8s-app/backend  --force --region us-east-1
aws ecr delete-repository --repository-name k8s-app/frontend --force --region us-east-1
```

## Notes

- **Redis replicas must stay at 1.** EBS `ReadWriteOnce` only allows a single Pod to mount the volume.
- **EBS volumes are AZ-scoped.** If the Redis Pod is rescheduled to a node in a different AZ, it will fail to mount. For production, pin Redis to a specific AZ using node affinity.
- **NLB provisioning takes 1-2 minutes** after applying the frontend Service. The DNS name is immediately visible but may not resolve until the NLB is active.
- The `reclaimPolicy: Retain` on the StorageClass means EBS volumes are NOT deleted when the PVC is deleted. Delete them manually in the EC2 console if not needed.
