################################################################################
# Observability Namespace
################################################################################

resource "kubernetes_namespace" "observability" {
  metadata {
    name = var.namespace
  }
}

################################################################################
# Prometheus Stack (Prometheus + Alertmanager + Grafana + Node Exporter)
# Single Helm release - simple and works out of the box
################################################################################

resource "random_password" "grafana_admin" {
  count   = var.grafana_admin_password == "" ? 1 : 0
  length  = 16
  special = false
}

locals {
  grafana_password = var.grafana_admin_password != "" ? var.grafana_admin_password : random_password.grafana_admin[0].result
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "prometheus"
  namespace  = var.namespace
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "65.8.1"

  timeout = 600
  wait    = true

  values = [
    yamlencode({
      # Prometheus configuration
      prometheus = {
        prometheusSpec = {
          retention     = "${var.prometheus_retention_days}d"
          retentionSize = "45GB"

          # Use default gp3 storage class (WaitForFirstConsumer)
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp3"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = var.prometheus_storage_size
                  }
                }
              }
            }
          }

          resources = {
            requests = {
              cpu    = "200m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "2Gi"
            }
          }
        }
      }

      # Grafana configuration (built into the stack)
      grafana = {
        enabled       = true
        adminUser     = "admin"
        adminPassword = local.grafana_password

        persistence = {
          enabled          = true
          storageClassName = "gp3"
          size             = "10Gi"
        }

        # Loki data source will be added after Loki is deployed
        additionalDataSources = [
          {
            name      = "Loki"
            type      = "loki"
            url       = "http://loki:3100"
            access    = "proxy"
            isDefault = false
          }
        ]

        # Pre-configured dashboards
        dashboardProviders = {
          "dashboardproviders.yaml" = {
            apiVersion = 1
            providers = [
              {
                name            = "default"
                orgId           = 1
                folder          = ""
                type            = "file"
                disableDeletion = false
                editable        = true
                options = {
                  path = "/var/lib/grafana/dashboards/default"
                }
              }
            ]
          }
        }

        dashboards = {
          default = {
            "kubernetes-cluster" = {
              gnetId     = 7249
              revision   = 1
              datasource = "Prometheus"
            }
            "node-exporter" = {
              gnetId     = 1860
              revision   = 37
              datasource = "Prometheus"
            }
          }
        }

        ingress = {
          enabled          = true
          ingressClassName = "traefik"
          annotations = {
            # Use wildcard certificate instead of requesting a new one
            # Prevent redirect loop when behind Cloudflare proxy
            "traefik.ingress.kubernetes.io/router.entrypoints" = "web,websecure"
          }
          hosts = ["grafana.${var.domain_name}"]
          tls = [
            {
              secretName = "wildcard-tls"
              hosts      = ["grafana.${var.domain_name}"]
            }
          ]
        }

        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }

      # Alertmanager - basic config
      alertmanager = {
        enabled = true
        alertmanagerSpec = {
          storage = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp3"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "5Gi"
                  }
                }
              }
            }
          }
          resources = {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
        }
      }

      # Node exporter for node metrics
      nodeExporter = {
        enabled = true
      }

      # Kube state metrics for k8s object metrics
      kubeStateMetrics = {
        enabled = true
      }
    })
  ]

  depends_on = [kubernetes_namespace.observability]
}

################################################################################
# Loki - Simple filesystem mode (no S3 complexity)
################################################################################

resource "helm_release" "loki" {
  name       = "loki"
  namespace  = var.namespace
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "6.22.0"

  timeout = 600
  wait    = true

  values = [
    yamlencode({
      deploymentMode = "SingleBinary"

      loki = {
        auth_enabled = false

        commonConfig = {
          replication_factor = 1
        }

        # Simple filesystem storage - no S3 complexity
        storage = {
          type = "filesystem"
        }

        schemaConfig = {
          configs = [
            {
              from         = "2024-01-01"
              store        = "tsdb"
              object_store = "filesystem"
              schema       = "v13"
              index = {
                prefix = "index_"
                period = "24h"
              }
            }
          ]
        }

        limits_config = {
          retention_period = "${var.loki_retention_days * 24}h"
        }
      }

      singleBinary = {
        replicas = 1
        persistence = {
          enabled          = true
          storageClass     = "gp3"
          size             = "20Gi"
        }
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "1Gi"
          }
        }
      }

      # Disable distributed mode components
      read = {
        replicas = 0
      }
      write = {
        replicas = 0
      }
      backend = {
        replicas = 0
      }

      # Disable caching components (require too much memory for small clusters)
      chunksCache = {
        enabled = false
      }
      resultsCache = {
        enabled = false
      }

      gateway = {
        enabled = false
      }

      test = {
        enabled = false
      }

      monitoring = {
        selfMonitoring = {
          enabled = false
        }
        lokiCanary = {
          enabled = false
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.observability]
}

################################################################################
# Promtail - Log collector (DaemonSet on all nodes)
################################################################################

resource "helm_release" "promtail" {
  name       = "promtail"
  namespace  = var.namespace
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = "6.16.6"

  values = [
    yamlencode({
      config = {
        clients = [
          {
            url = "http://loki:3100/loki/api/v1/push"
          }
        ]
      }
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

  depends_on = [helm_release.loki]
}

################################################################################
# Wildcard Certificate for Observability Namespace
################################################################################

resource "kubectl_manifest" "wildcard_certificate" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "wildcard-cert"
      namespace = var.namespace
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

  depends_on = [kubernetes_namespace.observability]
}
