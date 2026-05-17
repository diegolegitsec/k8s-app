# Option 3 — AWS (EKS)

Deploys to an EKS cluster using GHCR images built by CI. Redis is backed by an EBS gp3 volume provisioned dynamically.

> **Do [ci-setup.md](ci-setup.md) first.** The deploy script pulls images from GHCR — they must exist before you deploy.

## Prerequisites

- AWS CLI configured (`aws configure`)
- `eksctl` installed: https://eksctl.io/installation/
- `kubectl` installed
- GHCR images pushed at least once (push to `main` to trigger CI)

## 1. Configure

```bash
cp config.env.example config.env
```

Edit `config.env`:

```env
GITHUB_OWNER=diegolegitsec   # your GitHub username
IMAGE_TAG=latest              # or a specific Git SHA
AWS_REGION=us-east-1
EKS_CLUSTER_NAME=k8s-app
NODE_TYPE=t3.medium
NODE_COUNT=2
NODE_MIN=1
NODE_MAX=3
```

`config.env` is gitignored — it will never be committed.

## 2. Create EKS Cluster

Run once. Takes ~15 minutes.

```bash
source config.env

eksctl create cluster \
  --name "$EKS_CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --nodegroup-name workers \
  --node-type "$NODE_TYPE" \
  --nodes "$NODE_COUNT" \
  --nodes-min "$NODE_MIN" \
  --nodes-max "$NODE_MAX" \
  --managed
```

`eksctl` updates your kubeconfig automatically.

## 3. Install EBS CSI Driver

Required for dynamic EBS volume provisioning (Redis persistent storage). Run once per cluster.

```bash
source config.env

eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster "$EKS_CLUSTER_NAME" \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve

ROLE_ARN=$(aws iam get-role \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --query 'Role.Arn' --output text)

eksctl create addon \
  --name aws-ebs-csi-driver \
  --cluster "$EKS_CLUSTER_NAME" \
  --service-account-role-arn "$ROLE_ARN" \
  --force
```

## 4. Make GHCR Packages Public (or configure a pull secret)

By default GHCR packages are private. The easiest option is to make them public:

1. Go to `https://github.com/diegolegitsec?tab=packages`
2. Open each package → **Package settings** → **Change visibility** → Public

If you want to keep them private, create an imagePullSecret instead — see [ci-setup.md → Using private packages](ci-setup.md#using-private-packages).

## 5. Deploy

```bash
./scripts/deploy.sh aws
```

The script reads `config.env`, updates your kubeconfig, substitutes `GITHUB_OWNER` and `IMAGE_TAG` into the AWS manifests, and applies them. It then waits for rollout and prints the NLB URL.

## 6. Get the App URL

```bash
kubectl get svc frontend-service -n k8s-app
# EXTERNAL-IP shows the NLB DNS — may take 1-2 min to become active
```

Or run a verify check:
```bash
source config.env
NLB=$(kubectl get svc frontend-service -n k8s-app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl http://$NLB/api/health
curl http://$NLB/api/entries
```

## 7. Redeploy After a New CI Build

After CI pushes a new image to GHCR, force a rolling restart to pull `latest`:

```bash
kubectl rollout restart deployment/backend  -n k8s-app
kubectl rollout restart deployment/frontend -n k8s-app
```

To deploy a specific build, update `IMAGE_TAG` in `config.env` to the Git SHA and re-run:
```bash
./scripts/deploy.sh aws
```

## 8. Tear Down

```bash
./scripts/deploy.sh teardown

# Delete the EKS cluster
source config.env
eksctl delete cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION"
```

> The `reclaimPolicy: Retain` on the EBS StorageClass means volumes are NOT deleted when the PVC is removed. Delete them manually in the EC2 console (`Volumes` section) if no longer needed.

## Notes

- **Redis replicas must stay at 1.** EBS `ReadWriteOnce` allows only one Pod to mount the volume at a time.
- **EBS volumes are AZ-scoped.** If the Redis Pod reschedules to a different AZ, the mount will fail. For production, add a node affinity to pin Redis to a fixed AZ.
- **NLB provisioning takes 1-2 minutes** after the Service is created. The hostname is visible immediately but DNS may not resolve until the NLB is active.
