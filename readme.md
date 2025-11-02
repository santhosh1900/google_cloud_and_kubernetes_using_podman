
# Google Cloud using Terraform

A detailed end to end explanation on how to deploy the cloud resources using Google cloud, Terraform Infrastructure as code, Kubernetes Engine and Podman.

## Prerequisites
Google Cloud service account with all the permisions mentioned below.

`Artifact Registry Reader` `Edge Container Admin` `Edge Container Admin` `Edge Container Admin` `Storage Admin`

Install Terraform In your local PC

Install Podman / Docker In your local PC for testing

Install Google Cli to use `gcloud auth login` for cloud deployment and cloud Infrastructure creation using Terraform.

```
gcloud components install gke-gcloud-auth-plugin
gcloud components install kubectl
gcloud components install beta
gcloud components install core
gcloud components install gsutil
gcloud components install compute
gcloud components install dns

```

#

## Podman Setup
Create a docker file for your app, here I have used Nestjs project 

DockerFile
```
# Stage 1 — build the NestJS app
FROM node:20-alpine AS builder

# ARG for dynamic app selection
WORKDIR /app

# Copy package files
COPY package*.json ./
COPY tsconfig*.json ./

# Copy all source code
COPY . .

# Install deps and build
RUN npm install && npm run build

# Stage 2 — runtime image
FROM node:20-alpine AS runtime
WORKDIR /app

# Copy compiled app from builder
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package*.json ./
COPY .env .env

RUN npm install --omit=dev

# Default port can be overridden
EXPOSE 3000
CMD ["sh", "-c", "node dist/main.js"]
```

.dockerignore

```
# Ignore unnecessary files
node_modules
.git
.gitignore
Dockerfile
dist
*.log
.vscode
.idea
coverage
```

Build the Container using Podman

```
podman build -t ${CONTAINER_NAME}:local .

podman run -d -p 3000:3000 --name ${CONTAINER_NAME} ${CONTAINER_NAME}:local
```

If the container is build and running fine move to to the setting up cloud Infrastructure using Terraform.

#

#### Step 1

Enable all the google APIs
```
gcloud services enable compute.googleapis.com container.googleapis.com artifactregistry.googleapis.com iam.googleapis.com
```

#### Step 2

Check the Podman is building and working locally

```
podman build -t ${CONTAINER_NAME}:local
podman run -d -p 3000:3000 --name ${CONTAINER_NAME} localhost/${CONTAINER_NAME}:local
```

#### Step 3
Run the Terraform Script to Create the Google Cloud Architecture

```
terraform init
terraform plan
terraform apply
```

This will create all the services mentioned in the main.tf files
You can configure all the cloud credentials in variables.tf

Output should be 
```
artifact_repo = "${YOUR_PROJECT_NAME}-repo"
cluster_name = "${YOUR_PROJECT_NAME}-cluster"
static_ip = "${GENERATED_STATIC_IP_ADDRESS}"
vpc_name = "${YOUR_PROJECT_NAME}-vpc"
```

#### Step 4

Google Auth for our Podman / Docker to connect with google cloud

```
gcloud auth configure-docker ${GOOGLE_REGION}-docker.pkg.dev
```

It will ask for Yes and give Yes to it

Output should be 

```
{
  "credHelpers": {
    "gcr.io": "gcloud",
    "us.gcr.io": "gcloud",
    "eu.gcr.io": "gcloud",
    "asia.gcr.io": "gcloud",
    "staging-k8s.gcr.io": "gcloud",
    "marketplace.gcr.io": "gcloud",
    "us-central1-docker.pkg.dev": "gcloud"
  }
}
Adding credentials for: ${GOOGLE_REGION}-docker.pkg.dev
gcloud credential helpers already registered correctly.
```

#### Step 5
Copy the generated google docker config to local container config so that our podman / docker can communicate with the google cloud

```
cp ~/.docker/config.json ~/.config/containers/auth.json
```

#### Step 6
Build the podman container in the google cloud (Artifact Container) with required zone/region

```
podman build -t ${GOOGLE_REGION}-docker.pkg.dev/${GOOGLE_PROJECT_ID}/${YOUR_PROJECT_NAME}-repo/${YOUR_PROJECT_NAME}:latest -f Dockerfile .
```

#### Step 7
Once the container is build push it to the Artifact Registry

```
podman push ${GOOGLE_REGION}-docker.pkg.dev/${GOOGLE_PROJECT_ID}/${YOUR_PROJECT_NAME}-repo/${YOUR_PROJECT_NAME}:latest
```

### Step 8
Get credentials fromGKE cluster so that kubectl can deploy container to google cloud

zone Example - us-central1-a

```
gcloud container clusters get-credentials ${YOUR_PROJECT_NAME}-cluster --zone ${GOOGLE_REGION + ZONE} --project ${PROJECT_ID}
```

#### Step 9
Refer the yaml files inside the directory k8s

```
kubectl apply -f k8s/${PROJECT_NAME}.yaml
kubectl apply -f k8s/${PROJECT_NAME_HS}.yaml
```
This will deploy the Containers in the google artifacts to the Kubernetes with the horizontal Scalling


#### Step 10
Download the kuberneties metrices system for autoscalling provision

```
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

#### Step 11
Wait for rollout

```
kubectl rollout status deployment/${PROJECT_NAME}-deployment

<!-- List of services available -->
kubectl get services

<!-- List Nodes -->
kubectl get nodes

<!-- List Pods -->
kubectl get pods

<!-- Describe pods -->
kubectl describe pod ${POD_NAME}

<!-- Get Nodes -->
kubectl get nodes -L cloud.google.com/gke-nodepool

```



# Github Auto deployment
```
name: Auto Deploy to GKE (dev)

on:
  push:
    branches:
      - dev

env:
  PROJECT_ID: ${{ secrets.GCP_PROJECT_ID }}
  GKE_CLUSTER: ${{ secrets.GKE_CLUSTER_NAME }}
  GKE_ZONE: ${{ secrets.GKE_ZONE }}
  IMAGE: ${{ secrets.GKE_ZONE }}-docker.pkg.dev/${{ secrets.GCP_PROJECT_ID }}/${{secrets.PROJECT_NAME}}-repo/${{secrets.PROJECT_NAME}}
  NAMESPACE: default
  DEPLOYMENT_NAME: ${{secrets.PROJECT_NAME}}

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest

    steps:
      # Step 1: Checkout the code
      - name: Checkout repository
        uses: actions/checkout@v4

      # Step 2: Authenticate with Google Cloud
      - name: Authenticate with Google Cloud
        uses: google-github-actions/auth@v2
        with:
          credentials_json: ${{ secrets.GCP_SA_KEY }}

      # Step 3: Setup gcloud CLI
      - name: Setup gcloud CLI
        uses: google-github-actions/setup-gcloud@v2
        with:
          project_id: ${{ env.PROJECT_ID }}

      # Step 4: Install Podman
      - name: Install Podman
        run: |
          sudo apt-get update
          sudo apt-get install -y podman

      # Step 5: Authenticate Podman to Google Artifact Registry
      - name: Configure Podman authentication for GAR
        run: |
          echo "${{ secrets.GCP_SA_KEY }}" | podman login -u _json_key --password-stdin https://us-central1-docker.pkg.dev

      # Step 6: Build and push the image to Artifact Registry
      - name: Build and Push Image
        run: |
          IMAGE_TAG=${GITHUB_SHA::7}
          podman build --format docker \
            -t $IMAGE:$IMAGE_TAG \
            -t $IMAGE:latest .
          podman push $IMAGE:$IMAGE_TAG
          podman push $IMAGE:latest

      # Step 7: Connect to the GKE cluster
      - name: Connect to GKE
        run: |
          gcloud container clusters get-credentials $GKE_CLUSTER --zone $GKE_ZONE --project $PROJECT_ID

      # Step 8: Deploy Kubernetes manifests (apply all YAMLs in /k8s)
      - name: Apply Kubernetes manifests
        run: |
          kubectl apply -f k8s/

      # Step 9: Update image in deployment and verify rollout
      - name: Update image and rollout
        run: |
          kubectl set image deployment/$DEPLOYMENT_NAME \
            $DEPLOYMENT_NAME=$IMAGE:latest -n $NAMESPACE
          kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NAMESPACE

```


# Domain NAME Mapping
Once the Static IP address is added to the pod using the setup mentioned in k8s/PROJECT_NAME.yaml

Add that ip address to the domain configuration 


| Type | Name   | Value         | TTL  |
|:-----|:-------|:--------------|:-----|
| A    | api    | IP-ADDRESS    | 3600 |

```
kubectl apply -f k8s/managed-cert.yaml
kubectl apply -f k8s/ingress.yaml

curl https://${DOMAIN_NAME}

```


