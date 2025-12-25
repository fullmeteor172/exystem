#!/bin/bash
set -e

echo "=== Cert-Manager Status ==="
kubectl get pods -n cert-manager

echo -e "\n=== ClusterIssuer Status ==="
kubectl get clusterissuer letsencrypt-prod -o yaml 2>/dev/null || echo "ClusterIssuer not found!"

echo -e "\n=== Certificate Status (Traefik Namespace) ==="
kubectl get certificate -n traefik
kubectl describe certificate wildcard-cert -n traefik 2>/dev/null || echo "Certificate not found in traefik namespace"

echo -e "\n=== Certificate Status (Observability Namespace) ==="
kubectl get certificate -n observability
kubectl describe certificate wildcard-cert -n observability 2>/dev/null || echo "Certificate not found in observability namespace"

echo -e "\n=== Secrets Status ==="
kubectl get secret wildcard-tls -n traefik 2>/dev/null || echo "wildcard-tls secret not found in traefik namespace"
kubectl get secret wildcard-tls -n observability 2>/dev/null || echo "wildcard-tls secret not found in observability namespace"

echo -e "\n=== CertificateRequests (if any issues) ==="
kubectl get certificaterequest -n traefik
kubectl get certificaterequest -n observability

echo -e "\n=== Cert-Manager Logs (last 50 lines) ==="
kubectl logs -n cert-manager deploy/cert-manager --tail=50

echo -e "\n=== External-DNS Logs (last 30 lines) ==="
kubectl logs -n external-dns deploy/external-dns --tail=30 2>/dev/null || echo "External-DNS not found"
