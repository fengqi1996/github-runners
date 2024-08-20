```bash
# Check is the istio installation is using helm or istioctl

# Check Istio Version
kubectl get pods -n istio-system <pods-name> -o yaml='{.spec.containers[0].image}'
# Check istio profile
kubectl describe deployment istiod -n istio-system | grep REVISION
# List Custom Resource Definitions (CRDs)
kubectl get crds | grep 'istio'
# Check IstioD confifguration, Can check scrape 
kubectl get configmap istio -n istio-system -o yaml
kubectl describe deployment istiod -n istio-system

# Get Networking Configuration
kubectl get gateways,destinationrules,virtualservices -A -o yaml -n istio-system
# Check Security Policies
kubectl get peerauthentication,authorizationpolicies -A -o yaml -n istio-system
# Check Istio Ingress Gateway
kubectl describe deployment -n istio-system istio-ingressgateway
kubectl get svc -n istio-system istio-ingressgateway -o yaml -n istio-system
kubectl get meshconfig -n istio-system -o yaml

```

## Extra if needed. 
```bash
kubectl get configmap istio-sidecar-injector-usergroup-1 -n usergroup-1 -o yaml


```