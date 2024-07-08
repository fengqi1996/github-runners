```bash
kubectl create ns github
kubectl -n github create secret generic github-secret --from-literal GITHUB_OWNER= --from-literal GITHUB_REPOSITORY= --from-literal GITHUB_PERSONAL_TOKEN=""

kubectl -n github apply -f kubernetes.yaml
```