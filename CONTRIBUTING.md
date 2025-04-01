# Contributing Guidelines

Contributions are welcome via GitHub pull requests. This document outlines the process to help get your contribution accepted.

## Sign off Your Work

The Developer Certificate of Origin (DCO) is a lightweight way for contributors to certify that they wrote or otherwise have the right to submit the code they are contributing to the project. Here is the full text of the [DCO](http://developercertificate.org/). Contributors must sign-off that they adhere to these requirements by adding a `Signed-off-by` line to commit messages.

```text
This is my commit message

Signed-off-by: Random J Developer <random@developer.example.org>
```

See `git help commit`:

```text
-s, --signoff
    Add Signed-off-by line by the committer at the end of the commit log
    message. The meaning of a signoff depends on the project, but it typically
    certifies that committer has the rights to submit this work under the same
    license and agrees to a Developer Certificate of Origin (see
    http://developercertificate.org/ for more information).
```

## How to Contribute

1. Fork this repository
2. Install all pre-commit hooks - `make initialise` in the root of the repository
3. Make your changes
4. Test your changes
5. Remember to sign off your commits as described above
6. Submit a pull request

***NOTE***: In order to make testing and merging of PRs easier, please submit changes to multiple charts in separate PRs.

### Technical Requirements

* Must pass [DCO check](#sign-off-your-work)
* Must follow [Charts best practices](https://helm.sh/docs/topics/chart_best_practices/)
* Must pass all pre-commit hooks. To install pre-commit hooks, run `make initialise` in the root of the repository
* Any change to a chart requires a version bump following [semver](https://semver.org/) principles. See [Immutability](#immutability) and [Versioning](#versioning) below
* Please remember to update the [README.md.gotmpl](./stable/rad-plugins/README.md.gotmpl)
* Please remember to update the [Chart.yaml](./stable/rad-plugins/Chart.yaml) with the new version number and update `artifacthub.io/changes` section with the changes made in the chart

Once changes have been merged, the release job will automatically run to package and release changed charts.

### Immutability

Chart releases must be immutable. Any change to a chart warrants a chart version bump even if it is only a change to the documentation.

### Versioning

The chart `version` should follow [semver](https://semver.org/).

Charts should start at `1.0.0`. Any breaking (backwards incompatible) changes to a chart should:

1. Bump the MAJOR version
2. In the README, under a section called "Upgrading", describe the manual steps necessary to upgrade to the new (specified) MAJOR version
3. New issue should be started to discuss the changes and the need for a new MAJOR version

## Contribution Guidelines

The following guidelines are to be followed when making changes to the Helm charts:

* All templates should use 2 spaces for indentation
* New dependencies should be added to the Chart.yaml file, not requirements.yaml (deprecated)
* All resources should have meaningful labels, including but not limited to recommended labels like app, version, component, etc.
* Always update the Chart.yaml when making changes to the templates
* Always make sure to run the tests locally before submitting a PR

## Namespace-Based Deployment

This Helm chart supports the ability to deploy resources to different namespaces separately. This allows users to:

1. Deploy only in the release namespace (`rad.deployment.releaseNamespace=true`, `rad.deployment.kubeSystem=false`)
2. Deploy only in the kube-system namespace (`rad.deployment.releaseNamespace=false`, `rad.deployment.kubeSystem=true`)
3. Deploy in both namespaces (default behavior)

When adding new resources to the chart, you must ensure they respect this namespace separation:

* For resources in the release namespace:
  ```yaml
  {{- if eq (include "rad-plugins.deployInReleaseNamespace" .) "true" -}}
  apiVersion: v1
  kind: ServiceAccount
  metadata:
    namespace: {{ .Release.Namespace }}
  # ...
  {{- end }}
  ```

* For resources in the kube-system namespace:
  ```yaml
  {{- if eq (include "rad-plugins.deployInKubeSystem" .) "true" -}}
  apiVersion: rbac.authorization.k8s.io/v1
  kind: Role
  metadata:
    namespace: kube-system
  # ...
  {{- end }}
  ```

* For cluster-wide resources (ClusterRoles, ClusterRoleBindings, etc.), determine if they should be conditionally rendered based on their purpose and associated namespaced resources.

This separation allows users to deploy resources selectively by namespace, which is important for organizations with different teams managing different namespaces.

### Testing Namespace-Based Deployment

Changes should maintain the namespace-based deployment capability. You can test this locally:

```bash
# Test default (both namespaces)
helm template stable/rad-plugins --set runtime.enabled=true

# Test release namespace only
helm template stable/rad-plugins --set runtime.enabled=true --set rad.deployment.kubeSystem=false

# Test kube-system namespace only
helm template stable/rad-plugins --set runtime.enabled=true --set rad.deployment.releaseNamespace=false
```

There are also automated tests in our CI pipeline that will verify this capability.

## Pull Request Process

1. Ensure all pre-commit hooks are passing by running `make pre-commit`.
2. Update the README.md.gotmpl with details of changes to the chart, including new values, exposed ports, useful settings, and any other information that would be relevant to users.
3. Update the Chart.yaml version following the [versioning](#versioning) guidelines.
4. Add an entry to the `artifacthub.io/changes` section in Chart.yaml describing your changes.
5. Run local tests to ensure your changes don't break existing functionality:
   ```bash
   # Lint the chart
   helm lint stable/rad-plugins

   # Test the rendered templates
   helm template stable/rad-plugins

   # If you've made namespace-based deployment changes, run the namespace tests
   # as described in the previous section
   ```
6. Create a Pull Request explaining the changes you've made and why they're needed.
7. Your PR will be reviewed by maintainers, who may request changes or ask for clarifications.
8. Once approved, your changes will be merged, and a new chart release will be automatically created.
