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
# Storage Classes
################################################################################

# GP3 Storage Class (default)
resource "kubernetes_storage_class" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
    fsType    = "ext4"
  }

  depends_on = [aws_eks_addon.ebs_csi_driver]
}

# GP3 with immediate binding (for StatefulSets that need it)
resource "kubernetes_storage_class" "gp3_immediate" {
  metadata {
    name = "gp3-immediate"
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "Immediate"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
    fsType    = "ext4"
  }

  depends_on = [aws_eks_addon.ebs_csi_driver]
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

  timeout         = 300  # 5 minutes
  wait            = true
  atomic          = true
  cleanup_on_fail = true

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

  timeout         = 300  # 5 minutes
  wait            = true
  atomic          = true
  cleanup_on_fail = true

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

  timeout       = 600  # 10 minutes
  wait          = true
  atomic        = true  # Rollback on failure to avoid stuck releases
  cleanup_on_fail = true

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
          # Trust X-Forwarded-* headers from Cloudflare proxy
          # This prevents redirect loops when Cloudflare terminates SSL
          forwardedHeaders = {
            trustedIPs = [
              # Cloudflare IP ranges (IPv4)
              "173.245.48.0/20",
              "103.21.244.0/22",
              "103.22.200.0/22",
              "103.31.4.0/22",
              "141.101.64.0/18",
              "108.162.192.0/18",
              "190.93.240.0/20",
              "188.114.96.0/20",
              "197.234.240.0/22",
              "198.41.128.0/17",
              "162.158.0.0/15",
              "104.16.0.0/13",
              "104.24.0.0/14",
              "172.64.0.0/13",
              "131.0.72.0/22",
              # Cloudflare IP ranges (IPv6)
              "2400:cb00::/32",
              "2606:4700::/32",
              "2803:f800::/32",
              "2405:b500::/32",
              "2405:8100::/32",
              "2a06:98c0::/29",
              "2c0f:f248::/32"
            ]
          }
          redirectTo = {
            port = "websecure"
          }
        }
        websecure = {
          forwardedHeaders = {
            trustedIPs = [
              # Cloudflare IP ranges (IPv4)
              "173.245.48.0/20",
              "103.21.244.0/22",
              "103.22.200.0/22",
              "103.31.4.0/22",
              "141.101.64.0/18",
              "108.162.192.0/18",
              "190.93.240.0/20",
              "188.114.96.0/20",
              "197.234.240.0/22",
              "198.41.128.0/17",
              "162.158.0.0/15",
              "104.16.0.0/13",
              "104.24.0.0/14",
              "172.64.0.0/13",
              "131.0.72.0/22",
              # Cloudflare IP ranges (IPv6)
              "2400:cb00::/32",
              "2606:4700::/32",
              "2803:f800::/32",
              "2405:b500::/32",
              "2405:8100::/32",
              "2a06:98c0::/29",
              "2c0f:f248::/32"
            ]
          }
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

  timeout         = 600  # 10 minutes
  wait            = true
  atomic          = true  # Rollback on failure to avoid stuck releases
  cleanup_on_fail = true

  values = [
    yamlencode({
      crds = {
        enabled = true
        keep    = var.cert_manager_keep_crds
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

################################################################################
# External DNS (auto-creates DNS records from Ingress resources)
# Only deployed when enable_automatic_dns is true and Cloudflare credentials are provided
################################################################################

resource "helm_release" "external_dns" {
  count = var.enable_automatic_dns && var.cloudflare_api_token != "" && var.cloudflare_zone_id != "" ? 1 : 0

  name             = "external-dns"
  namespace        = "external-dns"
  repository       = "https://kubernetes-sigs.github.io/external-dns"
  chart            = "external-dns"
  version          = "1.15.0"
  create_namespace = true

  timeout         = 300  # 5 minutes
  wait            = true
  atomic          = true
  cleanup_on_fail = true

  values = [
    yamlencode({
      provider = {
        name = "cloudflare"
      }

      env = [
        {
          name = "CF_API_TOKEN"
          valueFrom = {
            secretKeyRef = {
              name = "cloudflare-api-token"
              key  = "api-token"
            }
          }
        }
      ]

      extraArgs = [
        "--cloudflare-proxied",
        "--cloudflare-dns-records-per-page=5000"
      ]

      domainFilters = [var.domain_name]

      policy = "sync"

      sources = ["ingress", "service"]

      txtOwnerId = var.cluster_name

      resources = {
        requests = {
          cpu    = "50m"
          memory = "64Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "128Mi"
        }
      }
    })
  ]

  depends_on = [kubernetes_secret.cloudflare_api_token_external_dns]
}

# Cloudflare secret for external-dns namespace
resource "kubernetes_namespace" "external_dns" {
  count = var.enable_automatic_dns && var.cloudflare_api_token != "" && var.cloudflare_zone_id != "" ? 1 : 0

  metadata {
    name = "external-dns"
  }
}

resource "kubernetes_secret" "cloudflare_api_token_external_dns" {
  count = var.enable_automatic_dns && var.cloudflare_api_token != "" && var.cloudflare_zone_id != "" ? 1 : 0

  metadata {
    name      = "cloudflare-api-token"
    namespace = "external-dns"
  }

  data = {
    api-token = var.cloudflare_api_token
  }

  type = "Opaque"

  depends_on = [kubernetes_namespace.external_dns]
}
