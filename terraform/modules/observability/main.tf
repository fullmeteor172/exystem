################################################################################
# Observability Namespace
################################################################################

resource "kubernetes_namespace" "observability" {
  metadata {
    name = var.namespace
  }
}

################################################################################
# S3 Bucket for Loki Logs
################################################################################

resource "aws_s3_bucket" "loki" {
  bucket = "${var.cluster_name}-loki-logs"

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "loki" {
  bucket = aws_s3_bucket.loki.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    id     = "delete-old-logs"
    status = "Enabled"

    filter {}  # Apply to all objects in the bucket

    expiration {
      days = var.loki_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

resource "aws_s3_bucket_public_access_block" "loki" {
  bucket = aws_s3_bucket.loki.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

################################################################################
# IAM Role for Loki (IRSA)
################################################################################

resource "aws_iam_role" "loki" {
  name = "${var.cluster_name}-loki"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${replace(var.oidc_provider_arn, "/^(.*provider/)/", "")}:sub" = "system:serviceaccount:${var.namespace}:loki"
          "${replace(var.oidc_provider_arn, "/^(.*provider/)/", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "loki_s3" {
  name = "${var.cluster_name}-loki-s3"
  role = aws_iam_role.loki.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.loki.arn,
          "${aws_s3_bucket.loki.arn}/*"
        ]
      }
    ]
  })
}

################################################################################
# Prometheus Stack (includes Prometheus, Alertmanager, Node Exporter, Kube State Metrics)
################################################################################

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  namespace  = var.namespace
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "65.8.1"

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          retention         = "${var.prometheus_retention_days}d"
          retentionSize     = "45GB"
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
              cpu    = "500m"
              memory = "2Gi"
            }
            limits = {
              cpu    = "2000m"
              memory = "4Gi"
            }
          }
          # Scrape pods with prometheus.io/scrape annotation
          additionalScrapeConfigs = [
            {
              job_name = "kubernetes-pods"
              kubernetes_sd_configs = [
                {
                  role = "pod"
                }
              ]
              relabel_configs = [
                {
                  source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_scrape"]
                  action        = "keep"
                  regex         = true
                },
                {
                  source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_path"]
                  action        = "replace"
                  target_label  = "__metrics_path__"
                  regex         = "(.+)"
                },
                {
                  source_labels = ["__address__", "__meta_kubernetes_pod_annotation_prometheus_io_port"]
                  action        = "replace"
                  regex         = "([^:]+)(?::\\d+)?;(\\d+)"
                  replacement   = "$1:$2"
                  target_label  = "__address__"
                }
              ]
            }
          ]
        }
        ingress = {
          enabled = true
          ingressClassName = "traefik"
          annotations = {
            "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
          }
          hosts = [
            "prometheus.${var.domain_name}"
          ]
          tls = [
            {
              secretName = "prometheus-tls"
              hosts = [
                "prometheus.${var.domain_name}"
              ]
            }
          ]
        }
      }
      grafana = {
        enabled = false  # We'll install Grafana separately for more control
      }
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
                    storage = "10Gi"
                  }
                }
              }
            }
          }
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.observability]
}

################################################################################
# Loki
################################################################################

resource "helm_release" "loki" {
  name       = "loki"
  namespace  = var.namespace
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "6.22.0"

  timeout       = 600
  wait          = true
  wait_for_jobs = true

  values = [
    yamlencode({
      deploymentMode = "SingleBinary"
      loki = {
        auth_enabled = false
        commonConfig = {
          replication_factor = 1
        }
        storage = {
          type = "s3"
          bucketNames = {
            chunks = aws_s3_bucket.loki.id
            ruler  = aws_s3_bucket.loki.id
            admin  = aws_s3_bucket.loki.id
          }
          s3 = {
            region = data.aws_region.current.name
          }
        }
        schemaConfig = {
          configs = [
            {
              from = "2024-01-01"
              store = "tsdb"
              object_store = "s3"
              schema = "v13"
              index = {
                prefix = "index_"
                period = "24h"
              }
            }
          ]
        }
        limits_config = {
          retention_period = "${var.loki_retention_days}d"
        }
        # Add storage configuration for filesystem cache
        storageConfig = {
          filesystem = {
            chunks_directory = "/var/loki/chunks"
            rules_directory  = "/var/loki/rules"
          }
        }
      }
      singleBinary = {
        replicas = 1
        persistence = {
          enabled      = true
          storageClass = "gp3"
          size         = "10Gi"
        }
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "1000m"
            memory = "1Gi"
          }
        }
      }
      # Explicitly disable simple scalable components when using SingleBinary mode
      read = {
        replicas = 0
      }
      write = {
        replicas = 0
      }
      backend = {
        replicas = 0
      }
      serviceAccount = {
        create = true
        name   = "loki"
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.loki.arn
        }
      }
      gateway = {
        enabled = false
      }
      test = {
        enabled = false
      }
      # Enable monitoring for debugging
      monitoring = {
        serviceMonitor = {
          enabled = false
        }
        selfMonitoring = {
          enabled = false
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.observability,
    aws_s3_bucket.loki,
    aws_iam_role.loki
  ]
}

################################################################################
# Promtail (Log Shipper)
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
        snippets = {
          pipelineStages = [
            {
              cri = {}
            }
          ]
        }
      }
      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
      }
    })
  ]

  depends_on = [helm_release.loki]
}

################################################################################
# Grafana
################################################################################

resource "kubernetes_secret" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = var.namespace
  }

  data = {
    admin-user     = "admin"
    admin-password = var.grafana_admin_password != "" ? var.grafana_admin_password : random_password.grafana_admin[0].result
  }

  type = "Opaque"

  depends_on = [kubernetes_namespace.observability]
}

resource "random_password" "grafana_admin" {
  count   = var.grafana_admin_password == "" ? 1 : 0
  length  = 16
  special = true
}

resource "helm_release" "grafana" {
  name       = "grafana"
  namespace  = var.namespace
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = "8.6.2"

  values = [
    yamlencode({
      adminUser     = "admin"
      adminPassword = var.grafana_admin_password != "" ? var.grafana_admin_password : random_password.grafana_admin[0].result
      persistence = {
        enabled      = true
        storageClassName = "gp3"
        size         = "10Gi"
      }
      datasources = {
        "datasources.yaml" = {
          apiVersion = 1
          datasources = [
            {
              name      = "Prometheus"
              type      = "prometheus"
              url       = "http://kube-prometheus-stack-prometheus:9090"
              access    = "proxy"
              isDefault = true
            },
            {
              name   = "Loki"
              type   = "loki"
              url    = "http://loki:3100"
              access = "proxy"
            }
          ]
        }
      }
      dashboardProviders = {
        "dashboardproviders.yaml" = {
          apiVersion = 1
          providers = [
            {
              name      = "default"
              orgId     = 1
              folder    = ""
              type      = "file"
              disableDeletion = false
              editable  = true
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
          "kubernetes-pods" = {
            gnetId     = 6417
            revision   = 1
            datasource = "Prometheus"
          }
          "node-exporter" = {
            gnetId     = 1860
            revision   = 37
            datasource = "Prometheus"
          }
          "loki-logs" = {
            gnetId     = 13639
            revision   = 2
            datasource = "Loki"
          }
        }
      }
      ingress = {
        enabled = true
        ingressClassName = "traefik"
        annotations = {
          "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
        }
        hosts = [
          "grafana.${var.domain_name}"
        ]
        tls = [
          {
            secretName = "grafana-tls"
            hosts = [
              "grafana.${var.domain_name}"
            ]
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
    })
  ]

  depends_on = [
    helm_release.kube_prometheus_stack,
    helm_release.loki,
    kubernetes_secret.grafana_admin
  ]
}

data "aws_region" "current" {}
