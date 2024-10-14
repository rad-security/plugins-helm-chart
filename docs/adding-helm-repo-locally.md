# Adding the helm repository locally

To add the RAD Security chart repository for your local client, run the following:

```sh
helm repo add rad-security https://charts.rad.security/stable
"rad-security" has been added to your repositories
```

You can then run `helm search repo rad-security` to see the charts and their available versions.

You can now install charts using `helm install rad-security/<chart>`.

For more information on using Helm, refer to the [Helm documentation](https://github.com/kubernetes/helm#docs).
