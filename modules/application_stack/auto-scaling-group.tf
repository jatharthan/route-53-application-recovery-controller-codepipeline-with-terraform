# ---------------------------------------------------------------------------------------------------------------------
# Auto Scaling Groups
# ---------------------------------------------------------------------------------------------------------------------

data "aws_ami" "amazon-linux-2" {
  most_recent = true
  owners           = ["amazon"]

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
  
  filter {
   name   = "owner-alias"
   values = ["amazon"]
  }

  filter {
   name   = "name"
   values = ["amzn2-ami-hvm*"]
  }
}

resource "aws_iam_instance_profile" "app_profile" {
  name = "${var.stack}-${var.aws_region}-app-profile"
  role = aws_iam_role.app-role.name
}

resource "aws_launch_template" "launch_template" {
  name_prefix   = "${var.stack}-launch-template-"
  image_id      = data.aws_ami.amazon-linux-2.id
  instance_type = "t4g.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.app_profile.name
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      encrypted = true
      delete_on_termination = true
    }
  }

  network_interfaces {
    security_groups = [aws_security_group.asg-sg.id]
    associate_public_ip_address = true
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash -x
    exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

    echo "Installing dependencies"
    sleep 60

    sudo yum -y update
    sudo yum install -y aws-cli ruby jq
    sudo yum install -y wget

    echo "Setting REGION variable"
    cd /home/ec2-user
    echo 'export REGION="${var.aws_region}"' >> .bashrc

    echo "Deleting CodeDeploy agent"
    CODEDEPLOY_BIN="/opt/codedeploy-agent/bin/codedeploy-agent"
    $CODEDEPLOY_BIN stop
    sudo yum erase codedeploy-agent -y

    echo "Installing CodeDeploy agent"
    cd /home/ec2-user
    wget https://aws-codedeploy-${var.aws_region}.s3.${var.aws_region}.amazonaws.com/latest/install
    sudo chmod +x ./install
    if ./install auto; then
        echo "CodeDeploy Agent: Installation completed"
        exit 0
    else
        echo "CodeDeploy Agent: Installation script failed, please investigate"
        exit 1
    fi
  EOF
  )
}

resource "aws_autoscaling_group" "app_asg" {
  name                      = "${var.stack}-asg"
  min_size                  = 2
  max_size                  = 2
  desired_capacity          = 2
  health_check_grace_period = 30
  health_check_type         = "ELB"
  vpc_zone_identifier       = aws_subnet.private[*].id
  force_delete              = true

  launch_template {
    id      = aws_launch_template.launch_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "ARC_App"
    propagate_at_launch = true
  }
}