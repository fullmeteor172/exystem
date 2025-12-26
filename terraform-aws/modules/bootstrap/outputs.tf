output "ebs_csi_driver_version" {
  description = "Version of the EBS CSI driver addon"
  value       = aws_eks_addon.ebs_csi_driver.addon_version
}

output "default_storage_class" {
  description = "Name of the default storage class"
  value       = kubernetes_storage_class.gp3.metadata[0].name
}
