# ---------------------------------------------------------------------------------------------------------------------
# Deploy an EC2 instance for Jenkins Controller  (centos7-based image), with no high-availabity setup
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_instance" "jenkins-controller" {
  count                  = (var.ha_high_availability_enabled == false) ? 1 : 0
  ami                    = var.aws_ami_id
  instance_type          = var.aws_instance_type
  iam_instance_profile   = var.iam_instance_profile
  subnet_id              = var.vpc.private_subnets_ids[0]
  vpc_security_group_ids = local.vpc_security_group_ids
  key_name               = var.aws_ssh_key_name
  root_block_device {
    delete_on_termination = true
    encrypted             = var.disk_root.encrypted
  }
  disable_api_termination = var.environment.resource_deletion_protection
  user_data = templatefile("${path.module}/user-data.yaml", {
    aws_ec2_instance_name                        = local.name
    aws_region                                   = var.aws_region,
    aws_zones                                    = join(" ", var.aws_zones[*]),
    disk_jenkins_home_enable                     = var.disk_jenkins_home.enabled
    disk_jenkins_home_type                       = var.disk_jenkins_home.type
    aws_efs_id                                   = (var.disk_jenkins_home.enabled && var.disk_jenkins_home.type == "EFS") ? aws_efs_file_system.jenkins-home-efs[0].id : ""
    ebs_device_name                              = (var.disk_jenkins_home.enabled && var.disk_jenkins_home.type == "EBS") ? "/dev/nvme1n1" : ""
    aws_asg_name                                 = ""
    check_efs_asg_max_attempts                   = var.ha_auto_scaling_group.check_efs_asg_max_attempts
    jenkins_linux_user_name                      = var.jenkins_linux_user_name
    jenkins_linux_user_group                     = var.jenkins_linux_user_group
    jenkins_user_ssh_public_key                  = var.jenkins_user_ssh_public_key
    jenkins_config_s3_bucket_name                = aws_s3_bucket.jenkins-config-files.bucket
    jenkins_admin_user_password_secret_id        = var.jenkins_admin_user_password_secret_id
    jenkins_nexus_user_password_secret_id        = var.jenkins_nexus_user_password_secret_id
    cloudwatch_enabled                           = var.cloudwatch_enabled ? "TRUE" : "FALSE"
    cloudwatch_refresh_interval_secs             = var.cloudwatch_refresh_interval_secs
    telegraf_enabled                             = var.telegraf_enabled ? "TRUE" : "FALSE"
    telegraf_influxdb_url                        = var.telegraf_influxdb_url
    telegraf_influxdb_password_secret_id         = var.telegraf_influxdb_password_secret_id
    telegraf_influxdb_retention_policy           = var.telegraf_influxdb_retention_policy
    telegraf_influxdb_https_insecure_skip_verify = var.telegraf_influxdb_https_insecure_skip_verify
  })
  tags = merge(var.global_default_tags, var.environment.default_tags, {
    Name            = local.name
    Zone            = var.aws_zones[0]
    Visibility      = "private"
    Application     = "jenkins-controller"
    ApplicationName = var.name_suffix
  })
  depends_on = [aws_efs_mount_target.jenkins-home-efs, aws_efs_file_system.jenkins-home-efs, aws_s3_bucket_object.jenkins-config-files-upload]
}
