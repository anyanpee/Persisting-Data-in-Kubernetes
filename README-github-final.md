# Persisting Data in Kubernetes - 101

This project demonstrates different approaches to data persistence in Kubernetes using Amazon EKS. You'll learn how to implement stateful applications using Persistent Volumes (PV), Persistent Volume Claims (PVC), and ConfigMaps.

## Prerequisites

Before starting this project, ensure you have:

- AWS Account with appropriate permissions
- AWS CLI installed and configured
- kubectl installed
- eksctl installed (for cluster management)
- Basic understanding of Kubernetes concepts
- Git Bash or terminal access

---

## Project Structure

```
├── cluster-config.yaml         # EKS cluster configuration
├── nginx-pod.yaml              # Basic nginx deployment (no persistence)
├── nginx-ebs-volume.yaml       # Nginx with EBS volume
├── nginx-pvc.yaml              # Persistent Volume Claim
├── nginx-with-pvc.yaml         # Nginx using PVC
├── nginx-configmap.yaml        # ConfigMap for HTML content
├── nginx-with-configmap.yaml   # Nginx using ConfigMap
├── nginx-service.yaml          # Service to expose nginx
├── storageclass-example.yaml   # Example StorageClass
├── commands-reference.txt      # Useful kubectl commands
├── PROJECT-WORKFLOW.txt        # Complete workflow guide
└── README.md                   # This file
```

## Step-by-Step Implementation

### Step 1: Install eksctl

Download and install eksctl for cluster management:

```bash
# Download eksctl for Windows
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Windows_amd64.zip"

# Extract it
unzip eksctl_Windows_amd64.zip -d eksctl_dir

# Verify installation
./eksctl_dir/eksctl.exe version
```

**Expected Output:**
```
0.221.0
```

---

### Step 2: Create EKS Cluster with EBS CSI Driver

Create the cluster using the provided configuration file:

```bash
./eksctl_dir/eksctl.exe create cluster -f cluster-config.yaml
```

This command will:
- Create an EKS cluster named "k8s-persistence-lab"
- Enable OIDC provider for IAM integration
- Install AWS EBS CSI driver with proper IAM permissions
- Create 2 t3.medium worker nodes
- Take approximately 15-20 minutes

**Expected Output:**
```
[✔]  EKS cluster "k8s-persistence-lab" in "us-east-1" region is ready
```

**Screenshot:**

![EKS Cluster Created](screenshots/Eks%20cluster%20on%20console%20Screenshot%20.png)

---

### Step 3: Verify Cluster Setup

Verify that the cluster is running and the default StorageClass exists:

```bash
# Check nodes
kubectl get nodes

# Check StorageClass
kubectl get storageclass
```

**Expected Output:**
```
NAME                             STATUS   ROLES    AGE     VERSION
ip-192-168-30-201.ec2.internal   Ready    <none>   5m28s   v1.32.9-eks-ecaa3a6
ip-192-168-51-173.ec2.internal   Ready    <none>   5m28s   v1.32.9-eks-ecaa3a6

NAME   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
gp2    kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer   false                  13m
```

---

### Step 4: Deploy Basic Nginx (Ephemeral Storage)

Deploy nginx without any persistence to understand ephemeral storage:

```bash
kubectl apply -f nginx-pod.yaml
kubectl get pods -o wide
```

**Expected Output:**
```
NAME                                READY   STATUS    RESTARTS   AGE
nginx-deployment-76c94d7fbd-b8wck   1/1     Running   0          2m
nginx-deployment-76c94d7fbd-dzr72   1/1     Running   0          2m
nginx-deployment-76c94d7fbd-p6bh5   1/1     Running   0          2m
```

**Screenshot:**

![Nginx Pods Running](screenshots/ngnix%20pod%20created%20Screenshot%20.png)

---

### Step 5: Explore Ephemeral Storage

Exec into a pod to see the default nginx HTML file:

```bash
kubectl exec -it nginx-deployment-76c94d7fbd-b8wck -- bash
```

Inside the pod:
```bash
cd /usr/share/nginx/html
cat index.html
exit
```

**Key Learning:** This data is ephemeral and will be lost if the pod is deleted.

---

### Step 6: Create Manual EBS Volume

Get the availability zone of a node:

```bash
kubectl get nodes ip-192-168-30-201.ec2.internal -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}'
```

**Output:** `us-east-1c`

Create an EBS volume in the same AZ:

```bash
aws ec2 create-volume --size 1 --region us-east-1 --availability-zone us-east-1c --volume-type gp2
```

**Expected Output:**
```json
{
    "VolumeId": "vol-0bc429b40ba70230a",
    "Size": 1,
    "AvailabilityZone": "us-east-1c",
    "State": "creating"
}
```

**Screenshot:**

![EBS Volume Created](screenshots/Ebs%20volume%20created%20Screenshot%20.png)

**Note:** We created this volume but didn't use it due to IAM permission complexity. This demonstrates why PVC with dynamic provisioning is preferred.

---

### Step 7: Create Persistent Volume Claim (PVC)

Create a PVC that will dynamically provision an EBS volume:

```bash
kubectl apply -f nginx-pvc.yaml
kubectl get pvc
```

**Expected Output:**
```
NAME                 STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
nginx-volume-claim   Pending                                      gp2            3s
```

**Key Learning:** PVC is in "Pending" state because of `WaitForFirstConsumer` binding mode. It will bind when a pod uses it.

**Screenshot:**

![PVC Created](screenshots/PVC%20created%20Screenshot%20.png)

---

### Step 8: Deploy Nginx with PVC

Deploy nginx that uses the PVC:

```bash
kubectl delete -f nginx-pod.yaml
kubectl apply -f nginx-with-pvc.yaml
kubectl get pvc
kubectl get pv
kubectl get pods
```

**Expected Output:**
```
NAME                 STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
nginx-volume-claim   Bound    pvc-c38160b1-b93c-400a-b442-8b5c25ab085c   2Gi        RWO            gp2            49s

NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM
pvc-c38160b1-b93c-400a-b442-8b5c25ab085c   2Gi        RWO            Delete           Bound    default/nginx-volume-claim

NAME                                READY   STATUS    RESTARTS   AGE
nginx-deployment-594869bdbd-266db   1/1     Running   0          2m
```

**Key Learning:** 
- PVC is now "Bound" to a dynamically created PV
- EBS volume was automatically created in AWS
- Volume is mounted at `/tmp/dare` in the container

---

### Step 9: Test Data Persistence

Write data to the persistent volume:

```bash
kubectl exec -it nginx-deployment-594869bdbd-266db -- bash
```

Inside the pod:
```bash
echo "This data persists!" > /tmp/dare/test.txt
cat /tmp/dare/test.txt
exit
```

Delete the pod to test persistence:

```bash
kubectl delete pod nginx-deployment-594869bdbd-266db
kubectl get pods
```

Wait for new pod to start, then verify data persisted:

```bash
kubectl exec -it nginx-deployment-594869bdbd-gqhmn -- sh -c "cat /tmp/dare/test.txt"
```

**Expected Output:**
```
This data persists!
```

**Screenshot:**

![Data Persistence Test](screenshots/Testing%20persistence%20data%20Screenshot%20.png)

**Key Learning:** Data written to the PVC survives pod restarts and deletions!

---

### Step 10: Deploy with ConfigMap

Clean up PVC deployment and create ConfigMap:

```bash
kubectl delete deployment nginx-deployment
kubectl delete pvc nginx-volume-claim
kubectl apply -f nginx-configmap.yaml
kubectl get configmap
```

**Expected Output:**
```
NAME                   DATA   AGE
website-index-file     1      2s
```

**Screenshot:**

![ConfigMap Created](screenshots/persisting%20data%20for%20config%20map%20Screenshot%20.png)

---

### Step 11: Deploy Nginx with ConfigMap

Deploy nginx that uses ConfigMap for HTML content:

```bash
kubectl apply -f nginx-with-configmap.yaml
kubectl apply -f nginx-service.yaml
kubectl get pods
```

**Expected Output:**
```
NAME                                READY   STATUS    RESTARTS   AGE
nginx-deployment-54b59bc9cd-5bwkv   1/1     Running   0          9s
```

---

### Step 12: Verify ConfigMap Content

Test that nginx is serving content from ConfigMap:

```bash
kubectl exec -it nginx-deployment-54b59bc9cd-5bwkv -- sh -c "curl localhost:80"
```

**Expected Output:**
```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...
</html>
```

**Screenshot:**

![Nginx Serving ConfigMap](screenshots/Nginx%20website%20on%20browser%20Screenshot%20.png)

**Key Learning:** ConfigMaps are perfect for storing configuration files that don't contain sensitive data.

---

## Key Concepts Learned

### 1. Ephemeral vs Persistent Storage
- **Ephemeral:** Data lost when pod is deleted
- **Persistent:** Data survives pod lifecycle

### 2. Volume Types
- **awsElasticBlockStore:** Direct EBS volume mount (manual, complex)
- **PersistentVolumeClaim:** Dynamic provisioning (automated, preferred)
- **ConfigMap:** Configuration file storage (non-confidential data)

### 3. PV/PVC Lifecycle
1. **Provisioning:** Static (manual) or Dynamic (automatic)
2. **Binding:** PVC binds to PV (one-to-one mapping)
3. **Using:** Pod mounts PVC as volume
4. **Reclaiming:** Volume cleanup after PVC deletion

### 4. Access Modes
- **ReadWriteOnce (RWO):** Single node read-write
- **ReadOnlyMany (ROX):** Multiple nodes read-only
- **ReadWriteMany (RWX):** Multiple nodes read-write

### 5. Volume Binding Modes
- **Immediate:** PV created immediately when PVC is created
- **WaitForFirstConsumer:** PV created when pod uses PVC (ensures correct AZ)

### 6. Reclaim Policies
- **Delete:** PV and underlying storage deleted when PVC is deleted
- **Retain:** PV kept for manual cleanup
- **Recycle:** Volume scrubbed and made available again (deprecated)

### 7. Important Notes
- EBS volumes are AZ-specific (pod must be in same AZ)
- PVs are cluster-wide resources (not namespaced)
- PVCs are namespace-scoped
- EBS CSI driver requires IAM permissions (OIDC + IAM roles)
- StorageClass controls dynamic provisioning behavior

## Project Summary

This project successfully demonstrated:

✅ Creating an EKS cluster with proper IAM/OIDC configuration  
✅ Understanding ephemeral vs persistent storage  
✅ Implementing dynamic volume provisioning with PVC  
✅ Testing data persistence across pod restarts  
✅ Using ConfigMaps for configuration management  
✅ Complete cluster lifecycle management  

**Congratulations on completing the Kubernetes Data Persistence project!** 🎉

---

## License

This project is for educational purposes.

## Author
Peter Anyankpele  
Created as part of Kubernetes learning journey.