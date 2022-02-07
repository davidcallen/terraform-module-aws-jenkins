# ---------------------------------------------------------------------------------------------------------------------
# HighAvailablity/Failover AutoScalingGroup for Jenkins Controller
# ---------------------------------------------------------------------------------------------------------------------
locals {
  asg_name = local.name
}
resource "aws_autoscaling_group" "jenkins-controller" {
  count = (var.ha_high_availability_enabled) ? 1 : 0
  name  = local.asg_name
  target_group_arns = concat(
    ((var.ha_high_availability_enabled && var.ha_public_load_balancer.arn != "")
      ? [
        aws_lb_target_group.jenkins-controller-public-https[count.index].arn
    ] : []),
    ((var.ha_high_availability_enabled && var.ha_private_load_balancer.arn != "")
      ? [
        aws_lb_target_group.jenkins-controller-private-https[count.index].arn
    ] : [])
  )
  max_size = var.ha_auto_scaling_group.max_size
  min_size = var.ha_auto_scaling_group.min_size
  # desired_capacity          = var.ha_auto_scaling_group.scaling_policy.desired_capacity
  health_check_grace_period = var.ha_auto_scaling_group.health_check_grace_period
  health_check_type         = "ELB"
  force_delete              = false
  # placement_group           = "${aws_placement_group.test.id}"
  launch_configuration = aws_launch_configuration.jenkins-controller[0].name
  vpc_zone_identifier  = var.vpc.private_subnets_ids
  default_cooldown     = var.ha_auto_scaling_group.default_cooldown # Start the failover instance quickly
  termination_policies = ["OldestInstance"]
  suspended_processes  = var.ha_auto_scaling_group.suspended_processes
  tags = [
    {
      key                 = "Name"
      value               = local.asg_name
      propagate_at_launch = true
    }
  ]
}
locals {
  vpc_security_group_ids_storage = (var.disk_jenkins_home.enabled && var.disk_jenkins_home.type == "EFS") ? [aws_security_group.jenkins-home-efs[0].id] : []
  vpc_security_group_ids         = concat([aws_security_group.jenkins-controller.id], local.vpc_security_group_ids_storage)
}
# TODO : Consider change from aws_launch_configuration to the newer aws_launch_template
resource "aws_launch_configuration" "jenkins-controller" {
  count                = (var.ha_high_availability_enabled) ? 1 : 0
  name_prefix          = "${local.asg_name}-"
  image_id             = var.aws_ami_id
  instance_type        = var.aws_instance_type
  iam_instance_profile = var.iam_instance_profile
  security_groups      = [aws_security_group.jenkins-controller.id]
  key_name             = var.aws_ssh_key_name
  root_block_device {
    delete_on_termination = true
    encrypted             = var.disk_root.encrypted
  }
  user_data = templatefile("${path.module}/user-data.yaml", {
    aws_ec2_instance_name                        = local.name
    aws_region                                   = var.aws_region,
    aws_zones                                    = join(" ", var.aws_zones[*]),
    disk_jenkins_home_enable                     = var.disk_jenkins_home.enabled
    disk_jenkins_home_type                       = var.disk_jenkins_home.type
    aws_efs_id                                   = (var.disk_jenkins_home.enabled && var.disk_jenkins_home.type == "EFS") ? aws_efs_file_system.jenkins-home-efs[0].id : ""
    ebs_device_name                              = (var.disk_jenkins_home.enabled && var.disk_jenkins_home.type == "EBS") ? "/dev/nvme1n1" : ""
    aws_asg_name                                 = local.asg_name
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
    telegraf_influxdb_password                   = var.telegraf_influxdb_password
    telegraf_influxdb_retention_policy           = var.telegraf_influxdb_retention_policy
    telegraf_influxdb_https_insecure_skip_verify = var.telegraf_influxdb_https_insecure_skip_verify
  })
  lifecycle {
    create_before_destroy = true
  }
  depends_on = [aws_efs_mount_target.jenkins-home-efs, aws_efs_file_system.jenkins-home-efs, aws_s3_bucket_object.jenkins-config-files-upload]
}
resource "aws_autoscaling_notification" "jenkins-controller" {
  count       = (var.ha_high_availability_enabled) ? 1 : 0
  group_names = [aws_autoscaling_group.jenkins-controller[0].name]
  notifications = [
    //    "autoscaling:EC2_INSTANCE_LAUNCH",
    //    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]
  topic_arn = ((var.ha_auto_scaling_group.cloudwatch_alarm_sns_topic_arn == "")
    ? var.cloudwatch_alarm_default_sns_topic_arn
    : var.ha_auto_scaling_group.cloudwatch_alarm_sns_topic_arn
  )
}