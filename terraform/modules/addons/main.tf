################################################################################
# AWS EBS CSI Driver
################################################################################

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = var.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = data.aws_eks_addon_version.ebs_csi.version
  service_account_role_arn = var.ebs_csi_driver_irsa_arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
}

data "aws_eks_addon_version" "ebs_csi" {
  addon_name         = "aws-ebs-csi-driver"
  kubernetes_version = data.aws_eks_cluster.main.version
  most_recent        = true
}

data "aws_eks_cluster" "main" {
  name = var.cluster_name
}

################################################################################
# EFS CSI Driver (Optional)
################################################################################

resource "helm_release" "efs_csi_driver" {
  count = var.enable_efs ? 1 : 0

  name       = "aws-efs-csi-driver"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/aws-efs-csi-driver"
  chart      = "aws-efs-csi-driver"
  version    = "3.0.8"

  values = [
    yamlencode({
      controller = {
        serviceAccount = {
          create = true
          name   = "efs-csi-controller-sa"
        }
      }
      storageClasses = [
        {
          name = "efs"
          parameters = {
            provisioningMode = "efs-ap"
            fileSystemId     = var.efs_file_system_id
            directoryPerms   = "700"
          }
          reclaimPolicy      = "Delete"
          volumeBindingMode  = "Immediate"
        }
      ]
    })
  ]
}

################################################################################
# Metrics Server
################################################################################

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server"
  chart      = "metrics-server"
  version    = "3.12.2"

  values = [
    yamlencode({
      args = [
        "--cert-dir=/tmp",
        "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname",
        "--kubelet-use-node-status-port",
        "--metric-resolution=15s"
      ]
      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
      }
    })
  ]
}

################################################################################
# Traefik Ingress Controller
################################################################################

resource "helm_release" "traefik" {
  name             = "traefik"
  namespace        = var.traefik_namespace
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = "32.1.1"
  create_namespace = true

  values = [
    yamlencode({
      deployment = {
        replicas = 2
      }
      service = {
        type = "LoadBalancer"
        annotations = {
          "service.beta.kubernetes.io/aws-load-balancer-type"            = "nlb"
          "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
          "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
        }
      }
      ports = {
        web = {
          redirectTo = {
            port = "websecure"
          }
        }
        websecure = {
          tls = {
            enabled = true
          }
        }
      }
      ingressRoute = {
        dashboard = {
          enabled = false
        }
      }
      providers = {
        kubernetesCRD = {
          enabled = true
        }
        kubernetesIngress = {
          enabled                     = true
          publishedService = {
            enabled = true
          }
        }
      }
      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
      }
      affinity = {
        podAntiAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = [
            {
              weight = 100
              podAffinityTerm = {
                labelSelector = {
                  matchExpressions = [
                    {
                      key      = "app.kubernetes.io/name"
                      operator = "In"
                      values   = ["traefik"]
                    }
                  ]
                }
                topologyKey = "kubernetes.io/hostname"
              }
            }
          ]
        }
      }
      logs = {
        general = {
          level = "INFO"
        }
        access = {
          enabled = true
        }
      }
      globalArguments = []
      additionalArguments = [
        "--serverstransport.insecureskipverify=true",
        "--providers.kubernetesingress.ingressclass=traefik"
      ]
    })
  ]
}

################################################################################
# Cert Manager
################################################################################

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = var.cert_manager_namespace
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.16.2"
  create_namespace = true

  values = [
    yamlencode({
      crds = {
        enabled = true
      }
      global = {
        leaderElection = {
          namespace = var.cert_manager_namespace
        }
      }
      resources = {
        requests = {
          cpu    = "10m"
          memory = "64Mi"
        }
        limits = {
          cpu    = "100m"
          memory = "256Mi"
        }
      }
      webhook = {
        resources = {
          requests = {
            cpu    = "10m"
            memory = "64Mi"
          }
          limits = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
      }
      cainjector = {
        resources = {
          requests = {
            cpu    = "10m"
            memory = "64Mi"
          }
          limits = {
            cpu    = "100m"
            memory = "256Mi"
          }
        }
      }
    })
  ]
}

################################################################################
# Cloudflare API Token Secret
################################################################################

resource "kubernetes_secret" "cloudflare_api_token" {
  count = var.cloudflare_api_token != "" && var.cloudflare_zone_id != "" ? 1 : 0

  metadata {
    name      = "cloudflare-api-token"
    namespace = var.cert_manager_namespace
  }

  data = {
    api-token = var.cloudflare_api_token
  }

  type = "Opaque"

  depends_on = [helm_release.cert_manager]
}

################################################################################
# ClusterIssuer for Let's Encrypt with Cloudflare DNS
################################################################################

resource "kubectl_manifest" "letsencrypt_issuer" {
  count = var.cloudflare_api_token != "" && var.cloudflare_zone_id != "" ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        server = var.acme_server
        email  = var.acme_email
        privateKeySecretRef = {
          name = "letsencrypt-prod"
        }
        solvers = [
          {
            dns01 = {
              cloudflare = {
                apiTokenSecretRef = {
                  name = "cloudflare-api-token"
                  key  = "api-token"
                }
                zoneID = var.cloudflare_zone_id
              }
            }
          }
        ]
      }
    }
  })

  depends_on = [
    helm_release.cert_manager,
    kubernetes_secret.cloudflare_api_token
  ]
}

################################################################################
# Wildcard Certificate
################################################################################

resource "kubectl_manifest" "wildcard_certificate" {
  count = var.cloudflare_api_token != "" && var.cloudflare_zone_id != "" ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "wildcard-cert"
      namespace = var.traefik_namespace
    }
    spec = {
      secretName = "wildcard-tls"
      issuerRef = {
        name = "letsencrypt-prod"
        kind = "ClusterIssuer"
      }
      dnsNames = [
        var.domain_name,
        "*.${var.domain_name}"
      ]
    }
  })

  depends_on = [
    kubectl_manifest.letsencrypt_issuer,
    helm_release.traefik
  ]
}

################################################################################
# Default TLS Store for Traefik
################################################################################

resource "kubectl_manifest" "traefik_default_tls" {
  count = var.cloudflare_api_token != "" && var.cloudflare_zone_id != "" ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "traefik.io/v1alpha1"
    kind       = "TLSStore"
    metadata = {
      name      = "default"
      namespace = var.traefik_namespace
    }
    spec = {
      defaultCertificate = {
        secretName = "wildcard-tls"
      }
    }
  })

  depends_on = [
    helm_release.traefik,
    kubectl_manifest.wildcard_certificate
  ]
}
