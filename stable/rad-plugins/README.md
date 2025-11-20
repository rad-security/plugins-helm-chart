# RAD Security Plugins

## Introduction

This chart deploys the following plugins required for the [RAD Security](https://rad.security/) platform (formerly KSOC):

- rad-sync
- rad-watch
- rad-sbom
- rad-guard
- rad-runtime

These plugins perform several different tasks, which will be explained below.

### rad-sync plugin

`rad-sync` is the plugin component synchronising Kubernetes resources to the customer cluster. Currently, only the `GuardPolicy` CRD is supported, but the mechanism is extensible and allows RAD Security to sync different resource types in the future. The plugin fetches resources from the RAD Security API. After executing them on the customer's cluster, the execution statuses are reported to the RAD Security API via HTTP calls. By default, the interval between the fetches is 60 seconds.

### rad-watch plugin

`rad-watch` is the plugin component responsible for syncing cluster state back to RAD Security. On startup, a controller is created that follows the [Kubernetes Informer](https://pkg.go.dev/k8s.io/client-go/informers) pattern via the [SharedIndexInformer](https://pkg.go.dev/k8s.io/client-go@v0.26.0/tools/cache#SharedIndexInformer:~:text=type%20SharedIndexInformer-,%C2%B6,-type%20SharedIndexInformer%20interface) to target the resource types that we are interested in individually.
The first action of the service is to upload the entire inventory of the cluster. Once this inventory is up-to-date, the plugin tracks events only generated when we detect a change in the object (or resource) state.
In this way, we can avoid the degradation of the API server, which would occur if we were to poll for resources. Automatic reconciliation is run every 24h by default in case any delete events are lost and prevent RAD Security from keeping track of stale objects.

### rad-sbom plugin

`rad-sbom` is the plugin responsible for calculating [SBOMs](https://en.wikipedia.org/wiki/Software_supply_chain) directly on the customer cluster. The plugin is run as an admission/mutating webhook, adding an image digest next to its tag if it's missing. This mutation is performed so [TOCTOU](https://en.wikipedia.org/wiki/Time-of-check_to_time-of_use) does not impact the user. The image deployed is the image that RAD Security scanned. It sees all new workloads and calculates SBOMs for them. It continuously checks the RAD Security API to save time and resources to see if the SBOM is already known for any particular image digest. If not, it is being calculated and uploaded to RAD Security for further processing.

By default we use `cyclonedx-json` format for SBOMs, but it can be changed to `spdx-json` or `syft-json` by setting the `SBOM_FORMAT` environment variable in the `values.yaml` file.

To prevent the plugin from mutating the `Pod` resource, set the `MUTATE_IMAGE` and `MUTATE_ANNOTATIONS` environment variables to `false`. If observe a performance degradation while deploying new workloads, you can improve it significantly by disabling the mutation of the image tag and annotations.

In order to ignore images from scanning use the `IGNORE_IMAGE_PREFIXES` environment variable. It's a comma separated list of full image prefixes to ignore. Use `registry.io` to ignore the entire image registry, `registry.io/repo` to ignore a repository, `registry.io/repo/image` to ignore all versions of an image, or `registry.io/repo/image:tag` to ignore a specific version.

```yaml
sbom:
  env:
    SBOM_FORMAT: cyclonedx-json
    MUTATE_IMAGE: true
    MUTATE_ANNOTATIONS: false
    IGNORE_IMAGE_PREFIXES: "registry.io/repo/image,registry.io/repo/anotherImage:tag"
```

Currently, the plugin supports most of the popular container registries, via the `IMAGE_PULL_SECRETS` environment variable. Additionally we have native support for Azure Container Registries and ECR. See below for more details.

#### Private Azure Container Registry

To use a private Azure Container Registry, you need to set the `azureWorkloadIdentityClientId` in the `values.yaml` file. This will allow the plugin to use the Azure Workload Identity to authenticate to the registry. For more details see: [Scanning images from Azure ACR](https://docs.rad.security/docs/scanning-images-from-azure-acr).

#### Private ECR Registry

To use a private ECR Registry, you need to add and configure an AWS IAM role with the necessary permissions. For more details see: [Scanning images from ECR](https://docs.rad.security/docs/scanning-images-from-ecr).

### rad-guard plugin

`rad-guard` is the plugin responsible for executing `GuardPolicy` (in the form of Rego) against a specific set of Kubernetes resources during their admission to the cluster, either allowing the admission or denying it.
The configuration for the blocking logic can be found in the `guard` section of the helm chart values file; see below.

```yaml
guard:
  config:
    BLOCK_ON_POLICY_VIOLATION: true
```

If admission is blocked, it can be seen in the RAD Security application under the Events tab for the specific cluster. Finally, the plugin also acts as a mutating webhook that simply takes the `AdmissionReview.UID` and adds it as an annotation (`rad-guard/admission: xxx`). In the case of a blocked object, this gives RAD Security an identifier to track what would otherwise be an ephemeral event.

### rad-runtime

`rad-runtime` is the plugin responsible for gathering runtime information from the nodes in the cluster. The plugin is not enabled by default. To enable the plugin, set the `enabled` value to `true` in your values file.

```yaml
runtime:
  enabled: true
```

When `rad-runtime` is enabled, an additional daemonset can be seen in the cluster. The daemonset is responsible for collecting runtime information from the nodes in the cluster. The information collected includes the following:

- Process information
- Network information
- Filesystem information
- Container information

By default the plugin uses `containerd` as a container runtime. If you are using `docker` or `crio-o` as your container runtime, you can enable it by configuring collectors in the `values.yaml` file.

```yaml
runtime:
  enabled: true
  agent:
    collectors:
      containerd:
        enabled: true
        socket: /run/containerd/containerd.sock
      crio:
        enabled: false
        socket: /run/crio/crio.sock
      docker:
        enabled: false
        socket: /run/docker.sock
```

Each plugin pod contains `agent` and `exporter` containers. The `agent` container is responsible for collecting runtime information from the nodes in the cluster. The `exporter` container is responsible for exporting the collected information to the RAD Security platform.

#### Node Scheduling

You can control where `rad-runtime` pods are scheduled using standard Kubernetes scheduling mechanisms:

```yaml
runtime:
  enabled: true
  nodeSelector:
    kubernetes.io/os: linux
  tolerations:
    - key: "special-nodes"
      operator: "Equal"
      value: "true"
      effect: "NoSchedule"
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/arch
            operator: In
            values:
            - amd64
```

The information collected is sent to the RAD Security platform for further processing. For more information on the `rad-runtime` plugin, see the [RAD Security documentation](https://docs.rad.security/).

## Ephemeral Storage

RAD Security plugins support optional ephemeral storage using Generic ephemeral volumes. By default, plugins use standard container ephemeral storage, but you can enable dedicated ephemeral volumes for improved performance and resource control.

### Why Use Ephemeral Volumes?

**Performance Benefits:**
- **High-performance storage classes**: Use faster storage (NVMe, SSD) for improved I/O performance
- **Dedicated storage**: Avoid contention with other container processes sharing node storage
- **Larger capacity**: Allocate more space than default ephemeral storage limits

**Resource Control:**
- **Predictable space**: Guarantee specific storage capacity for each plugin
- **Storage isolation**: Prevent one plugin from affecting others' storage availability
- **Node resource management**: Better control over node storage usage

### Basic Configuration

Enable ephemeral storage for any component by setting `PLUGIN_NAME.ephemeralVolumes.enabled: true`. If `storageClassName` is not set, the default StorageClass will be used.

```yaml
sbom:
  ephemeralVolumes:
    enabled: true
    size: 25Gi
    storageClassName: "gp3"
    accessModes:
      - ReadWriteOnce

# Example: Basic setup for other plugins
# with default storage class and size
guard:
  ephemeralVolumes:
    enabled: true
```

**Note**: Ephemeral volumes are deleted when pods are terminated. They provide temporary, high-performance storage but do not persist data across pod restarts.

## Pod Scheduling

All RAD Security plugins support standard Kubernetes scheduling mechanisms including `nodeSelector`, `tolerations`, and `affinity`. This allows you to control where pods are scheduled based on your cluster requirements.

### Basic Example

```yaml
# Apply to any plugin (guard, sbom, sync, watch, runtime, piiAnalyzer, k9)
guard:
  nodeSelector:
    kubernetes.io/os: linux
  tolerations:
    - key: "example-key"
      operator: "Equal"
      value: "example-value"
      effect: "NoSchedule"
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/arch
            operator: In
            values:
            - amd64
```

## Sampling configuration

High frequency events are sampled by default. This applies to HTTP and Open File events. Use the configuration below to change the default values.

```yaml
runtime:
  agent:
    sampling:
      enabled: true
      minSamples: 10
      maxSamples: 100
      ratio: 5
      ttl: "5m"
```

## Prerequisites

The remainder of this page assumes the following:

- An Account in RAD Security already exists
- The user has obtained the `base64AccessKey` and `base64SecretKey` values required for the installation via the UI or the API
- The user has kubectl installed
- The user has Helm v3 installed
- The user has kubectl admin access to the cluster
- The RAD Security pods have outbound port 443 access to `https://api.rad.security`

## Installing the Chart

### 1. Install cert-manager

[cert-manager](https://github.com/cert-manager/cert-manager) must be installed, as RAD Security deploys [Admission Controllers](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/)  that create certificates to secure their communication with the Kubernetes API. At present RAD Security only supports cert-manager as the means of creating these certificates.

You can check if cert-manager is installed using the command below:

```bash
kubectl get pods -A | grep cert-manager
```

If the command above returns no results, you must install cert-manager into your cluster using the following commands:

**NOTE:** It may take up to 2 minutes for the `helm install`command below to complete.

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.0 \
  --set installCRDs=true
```

A full list of available Helm values is on[cert-manager's ArtifactHub page](https://artifacthub.io/packages/helm/cert-manager/cert-manager).

### 2. Verify cert-manager installation

Now we have installed cert-manager, we need to validate that it is running successfully. This can be achieved using the command below:

```bash
kubectl get pods -n cert-manager
```

You should see the following pods (with slightly different generated IDs at the end) with a status of Running:

```bash
NAME                                     	 READY   STATUS	RESTARTS   AGE
cert-manager-7dc9d6599-5fj6g             	 1/1 	   Running   0      	1m
cert-manager-cainjector-757dd96b8b-hlqgp 	 1/1 	   Running   0      	1m
cert-manager-webhook-854656c6ff-b4zqp    	 1/1 	   Running   0      	1m
```

### 3. Configure RAD Security helm repository

To install the RAD Security plugins Helm chart, we need to configure access to the RAD Security helm repository using the commands below:

```bash
helm repo add rad-security https://charts.rad.security/stable
helm repo update
```

If you already had RAD Security's Helm chart installed, it is recommended to update it.

```bash
helm repo update rad-security
```

Verify the RAD Security plugins Helm chart has been installed:

```bash
helm search repo rad-security
```

Example output (chart version may differ):

```bash
helm search repo rad-security
NAME                     	CHART	VERSION	APP	VERSION	DESCRIPTION
rad-security/rad-plugins 	1.0.0        	           	A Helm chart to run the RAD Security plugins
```

### 4. Create cluster-specific values file

Next, we need to create a values file called `values.yaml` with the following content that includes the [base64AccessKeyId and base64SecretKey](https://docs.rad.security/docs/installation#add-cluster):

```yaml
rad:
  base64AccessKeyId: "YOURACCESSKEYID"
  base64SecretKey: "YOURSECRETKEY"
  clusterName: "please add a name here"
```

You can manually create the file or use `values.yaml` file downloaded from the RAD Security UI.

**NOTE:** Be sure to set the `clusterName` value with a descriptive name of the cluster where you will be installing RAD Security.

#### 4.1 Recommended installation

By default, a secret is created as part of our Helm chart, which we use to securely connect to RAD Security. However, it is highly recommended that this secret is created outside of the helm installation and is just referenced in the Helm values.

The structure of the secret is as follows:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: rad-access-key
  namespace: rad
data:
  access-key-id: "YOURACCESSKEYID"
  secret-key: "YOURSECRETKEY"
```

The secret can now be referenced in the Helm chart using the following values.yaml configuration:

```yaml
rad:
  clusterName: "please add a name here"
  accessKeySecretNameOverride: "rad-access-key"
```

RAD Security rad-guard plugin integrates with the Kubernetes admission controller. All admission controller communications require TLS. RAD Security Helm chart installs and rad-guard utilizes Let's Encrypt to automate the issuance and renewal of certificates using the cert-manager add-on.

#### 4.2 AWS Secret Manager

If you are using AWS Secret Manager to store your access key, you can use the `awsSecretId` parameter to specify the secret ID. Secret ID could be the name of the secret or the full ARN. The service accounts need to have access to the secret in AWS, via IRSA or EKS Pod Identity. There is no need to provide `base64AccessKeyId` and `base64SecretKey` in this case.

```yaml
rad:
  awsSecretId: "arn:aws:secretsmanager:us-west-2:123456789012:secret:my-secret
```

Format of the secret in AWS Secret Manager:

```json
{
  "access-key-id": "value copied from the RAD Security UI, decoded from base64",
  "secret-key": "value copied from the RAD Security UI, decoded from base64"
}
```

If IRSA is used, following `serviceAccountAnnotations` should be added to the `values.yaml` file:

```yaml
guard:
  serviceAccountAnnotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/role-name-which-can-read-secrets
sbom:
  serviceAccountAnnotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/role-name-which-can-read-secrets
sync:
  serviceAccountAnnotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/role-name-which-can-read-secrets
watch:
  serviceAccountAnnotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/role-name-which-can-read-secrets
runtime:
  enabled: true
  serviceAccountAnnotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/role-name-which-can-read-secrets
```

### 5. Installing the RAD plugins

Finally, you can install rad-plugins using the following command:

**NOTE:** It may take up to 2 minutes for the `helm install`command below to complete.

```bash
helm install \
  rad rad-security/rad-plugins \
  --namespace rad \
  --create-namespace \
  -f values.yaml
```

### 6. Verify RAD plugins

Now we have installed the RAD plugins, we need to validate that it is running successfully. This can be achieved using the command below:

```bash
kubectl get pods -n rad
```

You should expect to see the following pods in a state of `Running`:

```bash
NAME                            READY   STATUS    RESTARTS   AGE
rad-guard-86959f7544-96hbl     1/1     Running   0          1m
rad-sbom-664bf566dc-bxm5c      1/1     Running   0          1m
rad-sync-769cd7c6fc-cxczq      1/1     Running   0          1m
rad-watch-7bf4d7b6b9-kqblh     1/1     Running   0          1m
```

If you have enabled the `rad-runtime` plugin you should also see the following pods in a state of Running:

```bash
NAME                READY   STATUS    RESTARTS   AGE
rad-runtime-7jjzg   2/2     Running   0          1m
rad-runtime-p45g6   2/2     Running   0          1m
rad-runtime-pmgtf   2/2     Running   0          1m
```

The number of pods below should equal the number of nodes in your cluster.

If you don't see all the pods running within 2 minutes, please check the [Installation Troubleshooting](https://docs.rad.security/docs/installation-troubleshooting) page or contact RAD Security support.

## Custom Resources support

`rad-watch` plugin optionally supports ingestion of _Custom Resources_ to the RAD Security platform. To use it
set `watch.ingestCustomResources` to `true` and configure `customResourceRules` in `values.yaml`.

For example, in order to ingest `your.com/ResourceA`, `your.com/ResourceB` and `your.com/ResourceC` `values.yaml` should include:

```yaml
watch:
  ingestCustomResources: true
  customResourceRules:
    allowlist:
    - apiGroups:
      - "your.com"
      resources:
      - "ResourceA"
      - "ResourceB"
      - "ResourceC"
```

Alternatively, you can ingest all _Custom Resources_ matching `your.com apiGroup` with a wildcard `*`:

```yaml
watch:
  ingestCustomResources: true
  customResourceRules:
    allowlist:
    - apiGroups:
      - "your.com"
      resources:
      - "*"
```

If you want to ingest `ResourceA` and `ResourceB` but exclude `ResourceC`, you should use `denylist`:

```yaml
watch:
  ingestCustomResources: true
  customResourceRules:
    allowlist:
    - apiGroups:
      - "your.com"
      resources:
      - "*"

    denylist:
    - apiGroups:
      - "your.com"
      resources:
      - "ResourceC"
```

## Node Agent Exec Filters

Node Agent allows to use wildcard rules to filtering command line arguments

To redact a secret used in `command secret=value`, you can use
the following Node Agent configuration:

```yaml
runtime:
  exporter:
    execFilters:
    - wildcard: "command secret=(*)"`.
```

All _wildcard groups_, i.e., `*` enclosed in parentheses will be redacted.

Wildcards not enclosed in parentheses can be used to match arguments that should not be redacted.

For example, the wildcard rule:
```yaml
runtime:
  exporter:
    execFilters:
    - wildcard: "command * secret=(*)"
```

results in the following redacted commands:

- `command -p secret=value` - `command -p secret=*****`
- `command --some-param secret=value` - `command --some-param secret=*****`

Simple patterns matching all commands can be also used. To redact `secret=value` in all commands, the following filter can be used:
```yaml
runtime:
  exporter:
    execFilters:
    - wildcard: "secret=(*)"
```

## Experimental PII detection
The runtime plugin has an experimental feature to detect PII in http requests. This feature is disabled by default and can be enabled by setting the following values in the `values.yaml` file:

```yaml
runtime:
  enabled: true
  httpTracingEnabled: true
  piiAnalyzer:
    enabled: true
```

**Note**: The PII analyzer component uses Microsoft Presidio, which only supports AMD64 architecture. This feature will not work on ARM64 nodes (including Apple Silicon Macs, ARM-based cloud instances, etc.). Ensure your cluster has AMD64 nodes available if you plan to use PII detection.

## Upgrading the Chart

Typically, we advise maintaining the most current versions of plugins. However, our [RAD Security](https://rad.security) plugins are designed to support upgrades between any two versions, with certain exceptions as outlined in our Helm chart changelog which you can access [here](https://artifacthub.io/packages/helm/rad/rad-plugins?modal=changelog).

The plugin image versions included in the Helm chart are collectively tested as a unified set. Individual plugin image versions are not tested in isolation for upgrades. It is strongly advised to upgrade the entire Helm chart as a complete package to ensure compatibility and stability.

### Workflow

To upgrade the version of the [RAD Security](https://rad.security) plugin's helm chart on your cluster, please follow the steps below.

1\. **Fetch the Latest Chart Version:** Acquire the most recent `rad-plugins` chart by running the following commands in your terminal

```bash
helm repo add rad-security https://charts.rad.security/stable
helm repo update rad-security
helm search repo rad-security
```

2\. **Perform the Upgrade:** Execute the upgrade by utilizing the following Helm command, making sure to retain your current configuration (values.yaml)

```bash
helm upgrade --install \
rad rad-security/rad-plugins \
--namespace rad \
--reuse-values
```

3\. **Confirm the Installation:** Verify that the upgrade was successful and the correct version is now deployed

```bash
helm list -n rad
```

### Helm chart changelog and updates

For full disclosure and to ensure you are kept up-to-date, we document every change, improvement, and correction in our detailed changelog for each version release. We encourage you to consult the changelog regularly to stay informed about the latest developments and understand the specifics of each update. Access the changelog for the [RAD Security](https://rad.security) plugins Helm chart at this [link](https://artifacthub.io/packages/helm/rad/rad-plugins?modal=changelog).

## Uninstalling the Chart

To uninstall the `rad-plugins` deployment:

```bash
helm uninstall rad -n rad
```

The command removes all the Kubernetes components associated with the chart and deletes the release.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| bootstrapper.affinity | object | `{}` |  |
| bootstrapper.env | object | `{}` |  |
| bootstrapper.image.repository | string | `"public.ecr.aws/n8h5y2v5/rad-security/rad-bootstrapper"` | The image to use for the rad-bootstrapper deployment |
| bootstrapper.image.tag | string | `"v1.1.24"` |  |
| bootstrapper.nodeSelector | object | `{}` |  |
| bootstrapper.podAnnotations | object | `{}` |  |
| bootstrapper.resources.limits.cpu | string | `"100m"` |  |
| bootstrapper.resources.limits.ephemeral-storage | string | `"100Mi"` |  |
| bootstrapper.resources.limits.memory | string | `"64Mi"` |  |
| bootstrapper.resources.requests.cpu | string | `"50m"` |  |
| bootstrapper.resources.requests.ephemeral-storage | string | `"100Mi"` |  |
| bootstrapper.resources.requests.memory | string | `"32Mi"` |  |
| bootstrapper.tolerations | list | `[]` |  |
| guard.affinity | object | `{}` |  |
| guard.config.BLOCK_ON_ERROR | bool | `false` | Whether to block on error. |
| guard.config.BLOCK_ON_POLICY_VIOLATION | bool | `false` | Whether to block on policy violation. |
| guard.config.BLOCK_ON_TIMEOUT | bool | `false` | Whether to block on timeout. |
| guard.config.ENABLE_WARNING_LOGS | bool | `false` | Whether to enable warning logs. |
| guard.config.LOG_LEVEL | string | `"info"` | The log level to use. |
| guard.enabled | bool | `true` |  |
| guard.ephemeralVolumes | object | `{"accessModes":["ReadWriteOnce"],"annotations":{},"enabled":false,"labels":{},"mountPath":"/tmp","size":"1Gi","storageClassName":""}` | Ephemeral volume configuration for rad-guard |
| guard.ephemeralVolumes.accessModes | list | `["ReadWriteOnce"]` | Access modes for the ephemeral volume |
| guard.ephemeralVolumes.annotations | object | `{}` | Additional annotations for the ephemeral volume |
| guard.ephemeralVolumes.enabled | bool | `false` | Enable ephemeral storage for rad-guard (used as /tmp filesystem when enabled) |
| guard.ephemeralVolumes.labels | object | `{}` | Additional labels for the ephemeral volume |
| guard.ephemeralVolumes.mountPath | string | `"/tmp"` | Mount path for the ephemeral volume in the guard container (used as /tmp when enabled) |
| guard.ephemeralVolumes.size | string | `"1Gi"` | Storage size for guard ephemeral volume |
| guard.ephemeralVolumes.storageClassName | string | `""` | Storage class to use. Use "" for default storage class, "-" for no storage class |
| guard.image.repository | string | `"public.ecr.aws/n8h5y2v5/rad-security/rad-guard"` | The image to use for the rad-guard deployment |
| guard.image.tag | string | `"v1.1.33"` |  |
| guard.nodeSelector | object | `{}` |  |
| guard.podAnnotations | object | `{}` |  |
| guard.replicas | int | `1` |  |
| guard.resources.limits.cpu | string | `"500m"` |  |
| guard.resources.limits.ephemeral-storage | string | `"1Gi"` |  |
| guard.resources.limits.memory | string | `"500Mi"` |  |
| guard.resources.requests.cpu | string | `"100m"` |  |
| guard.resources.requests.ephemeral-storage | string | `"100Mi"` |  |
| guard.resources.requests.memory | string | `"100Mi"` |  |
| guard.serviceAccountAnnotations | object | `{}` |  |
| guard.tolerations | list | `[]` |  |
| guard.webhook.objectSelector | object | `{}` |  |
| guard.webhook.timeoutSeconds | int | `10` |  |
| k9.affinity | object | `{}` |  |
| k9.backend.image.repository | string | `"public.ecr.aws/n8h5y2v5/rad-security/rad-k9-backend-agent"` |  |
| k9.backend.image.tag | string | `"v0.0.41"` |  |
| k9.capabilities.enableGetLogs | bool | `false` |  |
| k9.capabilities.enableLabelPod | bool | `false` |  |
| k9.capabilities.enableQuarantine | bool | `false` |  |
| k9.capabilities.enableTerminateNamespace | bool | `false` |  |
| k9.capabilities.enableTerminatePod | bool | `false` |  |
| k9.enabled | bool | `false` |  |
| k9.ephemeralVolumes | object | `{"accessModes":["ReadWriteOnce"],"annotations":{},"enabled":false,"labels":{},"mountPath":"/tmp","size":"1Gi","storageClassName":""}` | Ephemeral volume configuration for rad-k9 |
| k9.ephemeralVolumes.accessModes | list | `["ReadWriteOnce"]` | Access modes for the ephemeral volume |
| k9.ephemeralVolumes.annotations | object | `{}` | Additional annotations for the ephemeral volume |
| k9.ephemeralVolumes.enabled | bool | `false` | Enable ephemeral storage for rad-k9 (used as /tmp filesystem when enabled) |
| k9.ephemeralVolumes.labels | object | `{}` | Additional labels for the ephemeral volume |
| k9.ephemeralVolumes.mountPath | string | `"/tmp"` | Mount path for the ephemeral volume in the k9 containers (used as /tmp when enabled) |
| k9.ephemeralVolumes.size | string | `"1Gi"` | Storage size for k9 ephemeral volume |
| k9.ephemeralVolumes.storageClassName | string | `""` | Storage class to use. Use "" for default storage class, "-" for no storage class |
| k9.frontend.agentActionPollInterval | string | `"5s"` | The interval in which the agent polls the backend for new actions. |
| k9.frontend.image.repository | string | `"public.ecr.aws/n8h5y2v5/rad-security/rad-k9-frontend-agent"` |  |
| k9.frontend.image.tag | string | `"v0.0.41"` |  |
| k9.nodeSelector | object | `{}` |  |
| k9.replicas | int | `1` |  |
| k9.resources.limits.cpu | string | `"250m"` |  |
| k9.resources.limits.ephemeral-storage | string | `"1Gi"` |  |
| k9.resources.limits.memory | string | `"512Mi"` |  |
| k9.resources.requests.cpu | string | `"100m"` |  |
| k9.resources.requests.ephemeral-storage | string | `"100Mi"` |  |
| k9.resources.requests.memory | string | `"128Mi"` |  |
| k9.serviceAccountAnnotations | object | `{}` |  |
| k9.tolerations | list | `[]` |  |
| openshift.enabled | bool | `false` |  |
| priorityClass.description | string | `"The priority class for RAD Security components"` |  |
| priorityClass.enabled | bool | `false` |  |
| priorityClass.globalDefault | bool | `false` |  |
| priorityClass.name | string | `"rad-priority"` |  |
| priorityClass.preemptionPolicy | string | `"PreemptLowerPriority"` |  |
| priorityClass.value | int | `10` |  |
| rad.accessKeySecretNameOverride | string | `""` | The name of the custom secret containing Access Key. |
| rad.apiKey | string | `""` | The combined API key to authenticate with RAD Security |
| rad.apiUrl | string | `"https://api.rad.security"` | The base URL for the RAD Security API. |
| rad.awsSecretId | string | `""` | The Secret Name or Secret ARN containing the Access Key. If provided, plugins try to read the Access Key from the AWS Secret Manager. Plugins expect following keys in the secret: `access-key-id` and `secret-key`. If the secret is not found, the plugin falls back to the `base64AccessKeyId` and `base64SecretKey` values. If `awsSecretId` is provided service accounts needs to have access to the secret in AWS, via IRSA or EKS Pod Identity. |
| rad.azureWorkloadIdentityClientId | string | `""` | The client ID of the Azure Workload Identity. If `azureWorkloadIdentityClientId` is provided, the plugin will assume that 'rad-sbom' identity is the Azure Workload Identity and will use it to authenticate private Azure Container Registries. |
| rad.base64AccessKeyId | string | `""` | The ID of the Access Key used in this cluster (base64). |
| rad.base64SecretKey | string | `""` | The secret key part of the Access Key used in this cluster (base64). |
| rad.clusterName | string | `""` | The name of the cluster you want displayed in RAD Security. |
| rad.deployment | object | `{"kubeSystem":true,"releaseNamespace":true}` | Control which namespaces to deploy resources to |
| rad.deployment.kubeSystem | bool | `true` | Deploy resources in the kube-system namespace. If false, no resources will be deployed in the kube-system namespace. |
| rad.deployment.releaseNamespace | bool | `true` | Deploy resources in the release namespace (the namespace where the chart is installed). If false, no resources will be deployed in the release namespace. |
| rad.seccompProfile | object | `{"enabled":true}` | Enable seccompProfile for all RAD Security pods |
| runtime.affinity | object | `{}` |  |
| runtime.agent.collectors.containerd.enabled | string | `nil` |  |
| runtime.agent.collectors.containerd.socket | string | `"/run/containerd/containerd.sock"` |  |
| runtime.agent.collectors.crio.enabled | string | `nil` |  |
| runtime.agent.collectors.crio.socket | string | `"/run/crio/crio.sock"` |  |
| runtime.agent.collectors.docker.enabled | bool | `false` |  |
| runtime.agent.collectors.docker.socket | string | `"/run/docker.sock"` |  |
| runtime.agent.collectors.runtimePath | string | `""` |  |
| runtime.agent.env.LOG_LEVEL | string | `"INFO"` |  |
| runtime.agent.env.TRACER_IGNORE_NAMESPACES | string | `"cert-manager,\nrad,\nksoc,\nkube-node-lease,\nkube-public,\nkube-system\n"` |  |
| runtime.agent.eventQueueSize | int | `20000` |  |
| runtime.agent.grpcServerBatchSize | int | `2000` |  |
| runtime.agent.hostPID | string | `nil` |  |
| runtime.agent.image.repository | string | `"public.ecr.aws/n8h5y2v5/rad-security/rad-runtime"` |  |
| runtime.agent.image.tag | string | `"v0.1.33"` |  |
| runtime.agent.mounts.volumeMounts | list | `[]` |  |
| runtime.agent.mounts.volumes | list | `[]` |  |
| runtime.agent.resources.limits.cpu | string | `"200m"` |  |
| runtime.agent.resources.limits.ephemeral-storage | string | `"1Gi"` |  |
| runtime.agent.resources.limits.memory | string | `"1Gi"` |  |
| runtime.agent.resources.requests.cpu | string | `"100m"` |  |
| runtime.agent.resources.requests.ephemeral-storage | string | `"100Mi"` |  |
| runtime.agent.resources.requests.memory | string | `"128Mi"` |  |
| runtime.agent.sampling.enabled | bool | `true` |  |
| runtime.agent.sampling.maxSamples | int | `100` |  |
| runtime.agent.sampling.minSamples | int | `10` |  |
| runtime.agent.sampling.ratio | int | `5` |  |
| runtime.agent.sampling.ttl | string | `"5m"` |  |
| runtime.enabled | bool | `false` |  |
| runtime.ephemeralVolumes | object | `{"accessModes":["ReadWriteOnce"],"annotations":{},"enabled":false,"labels":{},"mountPath":"/tmp","size":"1Gi","storageClassName":""}` | Ephemeral volume configuration for rad-runtime |
| runtime.ephemeralVolumes.accessModes | list | `["ReadWriteOnce"]` | Access modes for the ephemeral volume |
| runtime.ephemeralVolumes.annotations | object | `{}` | Additional annotations for the ephemeral volume |
| runtime.ephemeralVolumes.enabled | bool | `false` | Enable ephemeral storage for rad-runtime (used as /tmp filesystem when enabled) |
| runtime.ephemeralVolumes.labels | object | `{}` | Additional labels for the ephemeral volume |
| runtime.ephemeralVolumes.mountPath | string | `"/tmp"` | Mount path for the ephemeral volume in the runtime containers (used as /tmp when enabled) |
| runtime.ephemeralVolumes.size | string | `"1Gi"` | Storage size for runtime ephemeral volume |
| runtime.ephemeralVolumes.storageClassName | string | `""` | Storage class to use. Use "" for default storage class, "-" for no storage class |
| runtime.exporter.env.LOG_LEVEL | string | `"INFO"` |  |
| runtime.exporter.execFilters | list | `[]` | Allows to specify wildcard rules for filtering command arguments. |
| runtime.exporter.image.repository | string | `"public.ecr.aws/n8h5y2v5/rad-security/rad-runtime-exporter"` |  |
| runtime.exporter.image.tag | string | `"v0.1.33"` |  |
| runtime.exporter.resources.limits.cpu | string | `"500m"` |  |
| runtime.exporter.resources.limits.ephemeral-storage | string | `"1Gi"` |  |
| runtime.exporter.resources.limits.memory | string | `"1Gi"` |  |
| runtime.exporter.resources.requests.cpu | string | `"100m"` |  |
| runtime.exporter.resources.requests.ephemeral-storage | string | `"100Mi"` |  |
| runtime.exporter.resources.requests.memory | string | `"128Mi"` |  |
| runtime.httpTracingEnabled | bool | `false` |  |
| runtime.nodeName | string | `""` |  |
| runtime.nodeSelector | object | `{}` |  |
| runtime.piiAnalyzer.affinity | object | `{}` |  |
| runtime.piiAnalyzer.enabled | bool | `false` |  |
| runtime.piiAnalyzer.env.LOG_LEVEL | string | `"WARNING"` |  |
| runtime.piiAnalyzer.ephemeralVolumes | object | `{"accessModes":["ReadWriteOnce"],"annotations":{},"enabled":false,"labels":{},"mountPath":"/tmp","size":"1Gi","storageClassName":""}` | Ephemeral volume configuration for pii-analyzer |
| runtime.piiAnalyzer.ephemeralVolumes.accessModes | list | `["ReadWriteOnce"]` | Access modes for the ephemeral volume |
| runtime.piiAnalyzer.ephemeralVolumes.annotations | object | `{}` | Additional annotations for the ephemeral volume |
| runtime.piiAnalyzer.ephemeralVolumes.enabled | bool | `false` | Enable ephemeral storage for pii-analyzer (used for temporary processing) |
| runtime.piiAnalyzer.ephemeralVolumes.labels | object | `{}` | Additional labels for the ephemeral volume |
| runtime.piiAnalyzer.ephemeralVolumes.mountPath | string | `"/tmp"` | Mount path for the ephemeral volume |
| runtime.piiAnalyzer.ephemeralVolumes.size | string | `"1Gi"` | Storage size for ephemeral volume |
| runtime.piiAnalyzer.ephemeralVolumes.storageClassName | string | `""` | Storage class to use. Use "" for default storage class, "-" for no storage class |
| runtime.piiAnalyzer.image.repository | string | `"mcr.microsoft.com/presidio-analyzer"` |  |
| runtime.piiAnalyzer.image.tag | string | `"2.2.357"` |  |
| runtime.piiAnalyzer.maxRequestsPerSecond | int | `10` |  |
| runtime.piiAnalyzer.nodeSelector | object | `{}` |  |
| runtime.piiAnalyzer.replicas | int | `3` |  |
| runtime.piiAnalyzer.resources.limits.cpu | string | `"2000m"` |  |
| runtime.piiAnalyzer.resources.limits.ephemeral-storage | string | `"4Gi"` |  |
| runtime.piiAnalyzer.resources.limits.memory | string | `"2Gi"` |  |
| runtime.piiAnalyzer.resources.requests.cpu | string | `"500m"` |  |
| runtime.piiAnalyzer.resources.requests.ephemeral-storage | string | `"2Gi"` |  |
| runtime.piiAnalyzer.resources.requests.memory | string | `"128Mi"` |  |
| runtime.piiAnalyzer.tolerations | list | `[]` |  |
| runtime.reachableVulnerabilitiesEnabled | bool | `true` |  |
| runtime.serviceAccountAnnotations | object | `{}` |  |
| runtime.tolerations | list | `[]` |  |
| runtime.updateStrategy.rollingUpdate.maxSurge | int | `0` | The maximum number of pods that can be scheduled above the desired number of pods. Can be an absolute number or percent, e.g. `5` or `"10%"` |
| runtime.updateStrategy.rollingUpdate.maxUnavailable | string | `"25%"` | The maximum number of pods that can be unavailable during the update. Can be an absolute number or percent, e.g.  `5` or `"10%"` |
| runtime.updateStrategy.type | string | `"RollingUpdate"` |  |
| sbom.affinity | object | `{}` |  |
| sbom.enabled | bool | `true` |  |
| sbom.env.IGNORE_IMAGE_PREFIXES | string | `""` | Comma separated list of full image prefixes to ignore. Use `registry.io` to ignore the entire image registry, `registry.io/repo` to ignore a repository, `registry.io/repo/image` to ignore all versions of an image, or `registry.io/repo/image:tag` to ignore a specific version. |
| sbom.env.IMAGE_PULL_SECRETS | string | `""` | Comma separated list of image pull secrets to use to pull container images. Important: The secrets must be created in the same namespace as the rad-sbom deployment. By default 'rad-sbom' tries to read imagePullSecrets from the manifest spec, but additionally, you can specify the secrets here. If you use AWS ECR private registry, we recommend to use EKS Pod Identity or IRSA to add access to "rad-sbom" to the ECR registry. |
| sbom.env.LOG_LEVEL | string | `"info"` | The log level to use. Options are trace, debug, info, warn, error |
| sbom.env.MUTATE_ANNOTATIONS | bool | `false` | Whether to mutate the annotations in pod spec by adding images digests. Annotations can be used to track image digests in addition to, or instead of the image tag mutation. |
| sbom.env.MUTATE_IMAGE | bool | `true` | Whether to mutate the image in pod spec by adding digest at the end. By default, digests are added to images to ensure that the image that runs in the cluster matches the digest of the build.  Disable this if your continuous deployment reconciler requires a strict image tag match. |
| sbom.env.SBOM_CHECK_LATEST | bool | `false` | Experimental: Whether to check for the latest image in the container registry and generate SBOM for it. If deployed image has tag with semver format, rad-sbom tries to get the newest image, newest minor version, or newest patch version. If the tag is not in semver format, rad-sbom tries to get the newest image from the container registry based on the tag time. Please be aware that time-based algorithm requires many requests to the container registry and may be slow. It works only if credentials are provided. Please note that this feature is experimental and may not work with all container registries. |
| sbom.env.SBOM_FORMAT | string | `"cyclonedx-json"` | The format of the generated SBOM. Currently we support: syft-json,cyclonedx-json,spdx-json |
| sbom.ephemeralVolumes | object | `{"accessModes":["ReadWriteOnce"],"annotations":{},"enabled":false,"labels":{},"mountPath":"/tmp","size":"25Gi","storageClassName":""}` | Ephemeral volume configuration for rad-sbom |
| sbom.ephemeralVolumes.accessModes | list | `["ReadWriteOnce"]` | Access modes for the ephemeral volume |
| sbom.ephemeralVolumes.annotations | object | `{}` | Additional annotations for the ephemeral volume |
| sbom.ephemeralVolumes.enabled | bool | `false` | Enable ephemeral storage for rad-sbom (used as /tmp for image processing and layer caching) |
| sbom.ephemeralVolumes.labels | object | `{}` | Additional labels for the ephemeral volume |
| sbom.ephemeralVolumes.mountPath | string | `"/tmp"` | Mount path for the ephemeral volume in the SBOM container (also used as /tmp when enabled) |
| sbom.ephemeralVolumes.size | string | `"25Gi"` | Storage size for SBOM ephemeral volume (larger size recommended for image processing) |
| sbom.ephemeralVolumes.storageClassName | string | `""` | Storage class to use. Use "" for default storage class, "-" for no storage class |
| sbom.image.repository | string | `"public.ecr.aws/n8h5y2v5/rad-security/rad-sbom"` | The image to use for the rad-sbom deployment |
| sbom.image.tag | string | `"v1.1.56"` |  |
| sbom.labels | object | `{}` |  |
| sbom.nodeSelector | object | `{}` |  |
| sbom.podAnnotations | object | `{}` |  |
| sbom.resources.limits.cpu | string | `"1000m"` |  |
| sbom.resources.limits.ephemeral-storage | string | `"25Gi"` | The ephemeral storage limit is set to 25Gi to cache and reuse image layers for the sbom generation. |
| sbom.resources.limits.memory | string | `"2Gi"` |  |
| sbom.resources.requests.cpu | string | `"500m"` |  |
| sbom.resources.requests.ephemeral-storage | string | `"1Gi"` |  |
| sbom.resources.requests.memory | string | `"1Gi"` |  |
| sbom.serviceAccountAnnotations | object | `{}` |  |
| sbom.tolerations | list | `[]` |  |
| sbom.webhook.timeoutSeconds | int | `10` |  |
| sync.affinity | object | `{}` |  |
| sync.enabled | bool | `true` |  |
| sync.env | object | `{}` |  |
| sync.ephemeralVolumes | object | `{"accessModes":["ReadWriteOnce"],"annotations":{},"enabled":false,"labels":{},"mountPath":"/tmp","size":"1Gi","storageClassName":""}` | Ephemeral volume configuration for rad-sync |
| sync.ephemeralVolumes.accessModes | list | `["ReadWriteOnce"]` | Access modes for the ephemeral volume |
| sync.ephemeralVolumes.annotations | object | `{}` | Additional annotations for the ephemeral volume |
| sync.ephemeralVolumes.enabled | bool | `false` | Enable ephemeral storage for rad-sync (used as /tmp filesystem when enabled) |
| sync.ephemeralVolumes.labels | object | `{}` | Additional labels for the ephemeral volume |
| sync.ephemeralVolumes.mountPath | string | `"/tmp"` | Mount path for the ephemeral volume in the sync container (used as /tmp when enabled) |
| sync.ephemeralVolumes.size | string | `"1Gi"` | Storage size for sync ephemeral volume |
| sync.ephemeralVolumes.storageClassName | string | `""` | Storage class to use. Use "" for default storage class, "-" for no storage class |
| sync.image.repository | string | `"public.ecr.aws/n8h5y2v5/rad-security/rad-sync"` | The image to use for the rad-sync deployment |
| sync.image.tag | string | `"v1.1.28"` |  |
| sync.nodeSelector | object | `{}` |  |
| sync.podAnnotations | object | `{}` |  |
| sync.resources.limits.cpu | string | `"200m"` |  |
| sync.resources.limits.ephemeral-storage | string | `"1Gi"` |  |
| sync.resources.limits.memory | string | `"256Mi"` |  |
| sync.resources.requests.cpu | string | `"100m"` |  |
| sync.resources.requests.ephemeral-storage | string | `"100Mi"` |  |
| sync.resources.requests.memory | string | `"128Mi"` |  |
| sync.serviceAccountAnnotations | object | `{}` |  |
| sync.tolerations | list | `[]` |  |
| watch.affinity | object | `{}` |  |
| watch.customResourceRules | object | `{"allowlist":[],"denylist":[]}` | Rules for Custom Resource ingestion containing allow- and denylists of rules specifying `apiGroups` and `resources`. E.g. `allowlist: apiGroups: ["custom.com"], resources: ["someResource", "otherResoure"]` Wildcards (`*`) can be used to match all. `customResourceRules.denylist` sets resources that should not be ingested. It has a priority over `customResourceRules.allowlist` to  deny resources allowed using a wildcard (`*`) match.  E.g. you can use `allowlist: apiGroups: ["custom.com"], resources: ["*"], denylist: apiGroups: ["custom.com"], resources: "excluded"` to ingest all resources within `custom.com` group but `excluded`. |
| watch.enabled | bool | `true` |  |
| watch.env.RECONCILIATION_AT_START | bool | `false` | Whether to trigger reconciliation at startup. |
| watch.ephemeralVolumes | object | `{"accessModes":["ReadWriteOnce"],"annotations":{},"enabled":false,"labels":{},"mountPath":"/tmp","size":"1Gi","storageClassName":""}` | Ephemeral volume configuration for rad-watch |
| watch.ephemeralVolumes.accessModes | list | `["ReadWriteOnce"]` | Access modes for the ephemeral volume |
| watch.ephemeralVolumes.annotations | object | `{}` | Additional annotations for the ephemeral volume |
| watch.ephemeralVolumes.enabled | bool | `false` | Enable ephemeral storage for rad-watch (used as /tmp filesystem when enabled) |
| watch.ephemeralVolumes.labels | object | `{}` | Additional labels for the ephemeral volume |
| watch.ephemeralVolumes.mountPath | string | `"/tmp"` | Mount path for the ephemeral volume in the watch container (used as /tmp when enabled) |
| watch.ephemeralVolumes.size | string | `"1Gi"` | Storage size for watch ephemeral volume |
| watch.ephemeralVolumes.storageClassName | string | `""` | Storage class to use. Use "" for default storage class, "-" for no storage class |
| watch.image.repository | string | `"public.ecr.aws/n8h5y2v5/rad-security/rad-watch"` | The image to use for the rad-watch deployment |
| watch.image.tag | string | `"v1.1.41"` |  |
| watch.ingestCustomResources | bool | `false` | If set will allow ingesting Custom Resources specified in `customResourceRules` |
| watch.nodeSelector | object | `{}` |  |
| watch.podAnnotations | object | `{}` |  |
| watch.resources.limits.cpu | string | `"250m"` |  |
| watch.resources.limits.ephemeral-storage | string | `"1Gi"` |  |
| watch.resources.limits.memory | string | `"512Mi"` |  |
| watch.resources.requests.cpu | string | `"100m"` |  |
| watch.resources.requests.ephemeral-storage | string | `"100Mi"` |  |
| watch.resources.requests.memory | string | `"128Mi"` |  |
| watch.serviceAccountAnnotations | object | `{}` |  |
| watch.tolerations | list | `[]` |  |
| workloads.disableServiceMesh | bool | `true` | Whether to disable service mesh integration. |
| workloads.imagePullSecretName | string | `""` | The image pull secret name to use to pull container images. |

| rad.clusterName | The name of the cluster you want displayed in RAD Security. | `""` |
| rad.accessKeySecretNameOverride | The name of the custom secret containing Access Key. | `""` |
| rad.seccompProfile.enabled | Enable seccompProfile for all RAD Security pods | `true` |
| rad.deployment.releaseNamespace | Deploy resources in the release namespace (the namespace where the chart is installed). If false, no resources will be deployed in the release namespace. | `true` |
| rad.deployment.kubeSystem | Deploy resources in the kube-system namespace. If false, no resources will be deployed in the kube-system namespace. | `true` |
| workloads.disableServiceMesh | Whether to disable service mesh integration. | `true` |
